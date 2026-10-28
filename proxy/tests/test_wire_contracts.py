"""Actual SDK/httpx serialization against notes; MockTransport never leaves process."""
import json
from email import policy
from email.parser import BytesParser
from pathlib import Path

import httpx
import pytest

from app.budget import Budget
from app.clients import RealMetaClient
from app.config import Settings
from app.errors import AppError, ModelOutputError
from app.images import prepare_request
from app.mock_data import textile_tear
from app.models import ClassifyResult, StepHelpRequest
from app.pipeline import analyze
from tests.conftest import make_req
from tests.test_api import wav_bytes

SAM = Path(__file__).parent / 'fixtures/sam/thin_tear.txt'
CLASSIFY = {'category': 'textile', 'risk_level': 'allowed', 'reason': 'Textil'}


def chat_response(data):
    return httpx.Response(200, json={
        'id': 'offline', 'object': 'chat.completion', 'created': 0, 'model': 'muse-spark-1.3',
        'choices': [{'index': 0, 'finish_reason': 'stop', 'message': {'role': 'assistant', 'content': json.dumps(data)}}],
        'usage': {'prompt_tokens': 100, 'completion_tokens': 40, 'total_tokens': 140},
    })


def sam_response(text, status='completed'):
    # Real SSE framing, parsed by the installed OpenAI SDK. Split in the middle
    # of a token so the client must concatenate deltas rather than parse chunks.
    events = []
    for delta in (text[:len(text)//2], text[len(text)//2:]):
        if delta:
            events.append({'type': 'response.output_text.delta', 'item_id': 'msg',
                           'output_index': 0, 'content_index': 0, 'delta': delta, 'sequence_number': len(events)})
    events.append({'type': 'response.' + status, 'response': {'id': 'sam-offline', 'status': status},
                   'sequence_number': len(events)})
    body = ''.join('data: ' + json.dumps(e) + '\n\n' for e in events)
    return httpx.Response(200, headers={'Content-Type': 'text/event-stream'}, text=body)


def client_for(tmp_path, handler, **settings):
    return RealMetaClient(
        Settings(meta_api_key='LLM_fake', mock_mode=False, cache_model_calls=True, cache_dir=tmp_path, **settings),
        Budget(tmp_path / 'budget.json', 5), http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )


async def test_spark_classify_diagnose_and_step_help_wire(tmp_path, image_b64):
    seen = []
    plan = textile_tear()
    def handler(req):
        assert req.url.path == '/v1/chat/completions'
        assert req.headers['authorization'] == 'Bearer LLM_fake'
        data = json.loads(req.content)
        seen.append(data)
        assert data['model'] == 'muse-spark-1.3'
        assert data['response_format']['type'] == 'json_schema'
        schema = data['response_format']['json_schema']
        assert '$ref' not in json.dumps(schema['schema'])
        assert '$defs' not in json.dumps(schema['schema'])
        assert [m['role'] for m in data['messages']] == ['system', 'user']
        content = data['messages'][1]['content']
        assert content[0]['type'] == 'text'
        assert all(b['type'] == 'image_url' and b['image_url']['url'].startswith('data:image/jpeg;base64,')
                   for b in content[1:])
        result = {'classify': CLASSIFY, 'diagnose': plan.model_dump(),
                  'step_help': {'answer': 'Locker nähen', 'retry_hint': None, 'escalate': False}}[schema['name']]
        return chat_response(result)
    c = client_for(tmp_path, handler)
    req = prepare_request(make_req(image_b64, extra_images=[{'purpose': 'label', 'image_base64': image_b64}]))
    try:
        cls = await c.classify(req)
        await c.diagnose(req, cls, [])
        await c.step_help(StepHelpRequest(step={'n': 1, 'title': 'Nähen', 'text': 't'}, diagnosis_summary='Riss',
                                         risk_level='allowed', issue_text='Faden locker', image_base64=req.image_base64))
    finally:
        await c.aclose()
    payload = json.loads(seen[1]['messages'][1]['content'][0]['text'])
    assert payload['image_order'] == ['main', 'label'] and payload['risk_level'] == 'allowed'
    assert payload['followup_round_already_done'] is True
    assert 'Änderungsschneiderin' in seen[1]['messages'][0]['content']
    assert len(seen[1]['messages'][1]['content']) == 3


async def test_sam_responses_actual_sdk_and_cache(tmp_path, image_b64):
    seen = []
    def handler(req):
        assert req.url.path == '/v1/responses'
        data = json.loads(req.content)
        seen.append(data)
        assert data['model'] == 'sam-3.1'
        assert data['stream'] is True and req.headers['accept'] == 'text/event-stream'
        assert data['metadata'] == {'include_confidence': 'true', 'mask_encoding': 'one_bit'}
        assert len(data['input']) == 1
        message = data['input'][0]
        assert message['type'] == 'message' and message['role'] == 'user'
        assert len(message['content']) == 2
        assert message['content'][0] == {'type': 'input_text', 'text': 'tear'}
        assert message['content'][1]['type'] == 'input_image'
        assert message['content'][1]['image_url'].startswith('data:image/png;base64,')
        return sam_response(SAM.read_text())
    c = client_for(tmp_path, handler)
    try:
        first = await c._sam_one(image_b64, 'tear', 640, 480)
        second = await c._sam_one(image_b64, 'tear', 640, 480)
        assert first == second and len(first) == 1 and first[0].polygon
        assert len(seen) == 1
    finally:
        await c.aclose()


async def test_sam_incomplete_is_not_cached_as_zero_match(tmp_path, image_b64):
    c = client_for(tmp_path, lambda r: sam_response('', status='incomplete'))
    try:
        with pytest.raises(ModelOutputError):
            await c._sam_one(image_b64, 'tear', 640, 480)
        assert list((tmp_path / 'model_calls').glob('*.json')) == []
    finally:
        await c.aclose()


async def test_asr_actual_multipart_and_cache(tmp_path):
    seen = []
    raw = wav_bytes(rate=24000)
    def handler(req):
        seen.append(req)
        assert req.url.path == '/v1/asr/transcribe'
        assert req.headers['accept'] == 'application/json'
        assert req.headers['authorization'] == 'Bearer LLM_fake'
        msg = BytesParser(policy=policy.default).parsebytes(
            ('Content-Type: ' + req.headers['content-type'] + '\r\n\r\n').encode() + req.content)
        parts = {p.get_param('name', header='content-disposition'): p for p in msg.iter_parts()}
        assert set(parts) == {'request', 'audio'}
        assert parts['request'].get_content_type() == 'application/json'
        assert json.loads(parts['request'].get_payload(decode=True)) == {
            'model': 'muse-voice-transcribe-1.0', 'audioEncoding': 'WAV',
            'mode': 'PUSH_TO_TALK', 'languageBias': ['German']}
        assert parts['audio'].get_content_type() == 'audio/wav'
        assert parts['audio'].get_payload(decode=True) == raw
        return httpx.Response(200, json={'sessionId': 'offline', 'transcript': 'Riss in der Hose', 'audioDurationMs': 200, 'turns': []})
    c = client_for(tmp_path, handler, base_url='https://api.meta.ai/v1/')
    try:
        # The supplied duration cannot under-report the billable WAV duration.
        assert await c.transcribe(raw, 0) == 'Riss in der Hose'
        assert await c.transcribe(raw, 0) == 'Riss in der Hose'
        assert len(seen) == 1
        assert c.budget.spent_today() == pytest.approx(0.00001)
        with pytest.raises(AppError):
            await c.transcribe(b'not WAV', 1)
        assert len(seen) == 1
    finally:
        await c.aclose()


@pytest.mark.parametrize('body', [{'text': 'wrong field'}, {'transcript': None}, []])
async def test_asr_bad_envelope_is_never_silently_successful(tmp_path, body):
    c = client_for(tmp_path, lambda r: httpx.Response(200, json=body))
    try:
        with pytest.raises(ModelOutputError):
            await c.transcribe(wav_bytes(), 0.2)
    finally:
        await c.aclose()


async def test_sdk_never_retries_http_errors(tmp_path, image_b64):
    seen = []
    def handler(req):
        seen.append(req)
        return httpx.Response(429, json={'error': {'message': 'rate limited', 'type': 'rate_limit'}})
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(AppError):
            await c.classify(make_req(image_b64))
        assert len(seen) == 1
    finally:
        await c.aclose()


async def test_full_real_pipeline_raw_wire_and_cached_replay(tmp_path):
    from tests.conftest import make_image_b64
    seen = []
    plan = textile_tear().model_dump()
    # The live segment list owns IDs; fixture plan IDs must refer to that list.
    plan = json.loads(json.dumps(plan).replace('seg_2', 'seg_1'))
    def handler(req):
        data = json.loads(req.content)
        seen.append((req.url.path, data))
        if req.url.path == '/v1/responses':
            concept = data['input'][0]['content'][0]['text']
            return sam_response(SAM.read_text() if concept == 'tear' else '')
        name = data['response_format']['json_schema']['name']
        if name == 'diagnose':
            payload = json.loads(data['messages'][1]['content'][0]['text'])
            assert [s['id'] for s in payload['segments']] == ['seg_1']
        return chat_response(CLASSIFY if name == 'classify' else plan)
    c = client_for(tmp_path, handler)
    req = prepare_request(make_req(make_image_b64((640,480)), answers=[{'question_id':'q1','text':'100 % Baumwolle'}]))
    try:
        result = await analyze(req, c)
        assert result.segments[0].mask is not None and result.guide.steps
        assert result.diagnosis.evidence_segment_ids == ['seg_1']
        assert all(set(s.segment_ids) <= {'seg_1'} for s in result.guide.steps)
        assert all(s.overlay is None or s.overlay.segment_id == 'seg_1' for s in result.guide.steps)
        calls = len(seen)
        assert calls == 9  # one call per SAM concept + classify + diagnose
        await analyze(req, c)
        assert len(seen) == calls
    finally:
        await c.aclose()


async def test_sam_transport_timeout_is_a_controlled_error(tmp_path, image_b64):
    def handler(req):
        raise httpx.ReadTimeout('offline timeout', request=req)
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(AppError) as exc:
            await c._sam_one(image_b64, 'tear', 64, 48)
        assert exc.value.code == 'timeout'
    finally:
        await c.aclose()


async def test_sam_missing_completion_never_caches_partial_output(tmp_path, image_b64):
    def handler(req):
        event = {'type':'response.output_text.delta', 'delta': SAM.read_text(),
                 'item_id':'msg', 'output_index':0, 'content_index':0, 'sequence_number':0}
        return httpx.Response(200, headers={'Content-Type':'text/event-stream'},
                              text='data: '+json.dumps(event)+'\n\n')
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(ModelOutputError):
            await c._sam_one(image_b64, 'tear', 640, 480)
        assert not list((tmp_path / 'model_calls').glob('*.json'))
    finally:
        await c.aclose()


async def test_partial_sam_success_cannot_hide_budget_exceeded(tmp_path, image_b64, monkeypatch):
    from app.errors import BudgetExceeded
    c = client_for(tmp_path, lambda r: pytest.fail('no request expected'))
    async def one(image, prompt, width, height):
        if prompt == 'tear':
            raise BudgetExceeded(0.1)
        return []
    monkeypatch.setattr(c, '_sam_one', one)
    try:
        with pytest.raises(BudgetExceeded):
            await c.segment(make_req(image_b64), 'textile', ['tear','hole'])
    finally:
        await c.aclose()
