"""Actual SDK/httpx serialization against notes; MockTransport never leaves process."""
import base64
import io
import json
from email import policy
from email.parser import BytesParser
from pathlib import Path

import httpx
import pytest
from PIL import Image

from app.budget import Budget
from app.clients import REPAIR_KEYWORDS, RealMetaClient
from app.config import Settings
from app.errors import AppError, ModelOutputError
from app.images import prepare_request
from app.mock_data import textile_tear
from app.models import AfterPreviewRequest, ClassifyResult, RefineRequest, StepHelpRequest, TrackRequest
from app.pipeline import analyze
from tests.conftest import make_req
from tests.test_api import wav_bytes
from tests.test_new_endpoints import VIDEO_B64

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
            'mode': 'PUSH_TO_TALK', 'languageBias': ['German'], 'keywords': REPAIR_KEYWORDS}
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
            return sam_response(SAM.read_text() if concept == 'rip' else '')
        name = data['response_format']['json_schema']['name']
        if name == 'diagnose':
            payload = json.loads(data['messages'][1]['content'][0]['text'])
            assert [s['id'] for s in payload['segments']] == ['seg_1']
        if name == 'grounding':
            return chat_response({'concept': 'tear', 'box': [100, 100, 400, 400]})
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
        assert calls == 10  # 6 SAM concepts + classify + diagnose + parallel grounding (Spark box, SAM box)
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


@pytest.mark.parametrize('size,expected', [((480, 640), (640, 480)), ((2400, 3200), (1536, 1152))])
async def test_refine_geometric_wire_after_exif_orientation_and_downscale(tmp_path, size, expected):
    seen = []
    photo = Image.new('RGB', size, (80, 90, 100))
    exif = Image.Exif()
    exif[274] = 6
    raw = io.BytesIO()
    photo.save(raw, format='JPEG', exif=exif)
    width, height = expected
    def handler(req):
        data = json.loads(req.content)
        seen.append(data)
        assert req.url.path == '/v1/responses' and data['stream'] is True
        assert data['metadata'] == {'mask_encoding': 'one_bit', 'include_confidence': 'true'}
        content = data['input'][0]['content']
        expected_prompt = (f'<0f>1<|box;x1={width//4};y1={height//4};x2={3*width//4-1};y2={3*height//4-1};w={width};h={height}|>'
                           f'<|point;x={width//2};y={height//2};w={width};h={height}|>'
                           f'<|point;x={width-1};y={height-1};w={width};h={height}|>'
                           f'-<|point;x=0;y=0;w={width};h={height}|>')
        assert content[0] == {'type': 'input_text', 'text': expected_prompt}
        image = Image.open(io.BytesIO(base64.b64decode(content[1]['image_url'].split(',')[1])))
        assert image.format == 'PNG' and image.size == expected and not image.getexif()
        from meta_sam_parser._mask_codec import _encode_raster
        mask = _encode_raster([1] * 16, 4, 4)
        return sam_response(f'<0f>1<|box;x1=10;y1=10;x2=13;y2=13;w={width};h={height};c=0.9|>'
                            f'<|mask;x=0;y=0;data=4,4,{mask}|>')
    c = client_for(tmp_path, handler)
    body = RefineRequest(image_base64=base64.b64encode(raw.getvalue()).decode(), label='Riss',
                         box=[0.25, 0.25, 0.5, 0.5], points=[
                             {'x': 0.5, 'y': 0.5, 'label': 'positive'}, {'x': 1, 'y': 1, 'label': 'positive'},
                             {'x': 0, 'y': 0, 'label': 'negative'}])
    try:
        first = await c.refine(body)
        assert first.source == 'tap' and first.label == 'Riss' and first.mask.points
        assert first == await c.refine(body) and len(seen) == 1
        assert c.budget.spent_today() == pytest.approx(0.0025)
    finally:
        await c.aclose()


async def test_refine_empty_result_is_controlled_error(tmp_path, image_b64):
    c = client_for(tmp_path, lambda r: sam_response(''))
    try:
        with pytest.raises(AppError) as exc:
            await c.refine(RefineRequest(image_base64=image_b64, box=[0, 0, 1, 1], label='Riss'))
        assert exc.value.code == 'no_segment'
    finally:
        await c.aclose()


async def test_grounding_full_pipeline_structured_wire_clipping_mask_and_cache(tmp_path):
    from tests.conftest import make_image_b64
    seen = []
    events = []
    def handler(req):
        data = json.loads(req.content)
        seen.append(data)
        if req.url.path == '/v1/responses':
            prompt = data['input'][0]['content'][0]['text']
            if prompt.startswith('<0f>'):
                assert prompt == '<0f>1<|box;x1=0;y1=120;x2=639;y2=359;w=640;h=480|>'
                assert data['metadata']['mask_encoding'] == 'one_bit'
                return sam_response(SAM.read_text().replace('<0f>7', '<0f>1'))
            # Even a part match does not suppress damage grounding.
            return sam_response(SAM.read_text() if prompt == 'garment' else '')
        schema = data['response_format']['json_schema']
        if schema['name'] == 'grounding':
            assert data['response_format']['type'] == 'json_schema'
            assert '$ref' not in json.dumps(schema['schema'])
            assert '0-1000' in data['messages'][0]['content']
            assert data['messages'][1]['content'][1]['image_url']['url'].startswith('data:image/jpeg;base64,')
            return chat_response({'concept': 'tear', 'box': [-1, 250, 1001, 750]})
        if schema['name'] == 'diagnose':
            payload = json.loads(data['messages'][1]['content'][0]['text'])
            assert [(s['id'], s['kind']) for s in payload['segments']] == [('seg_1', 'part'), ('seg_2', 'damage')]
        return chat_response(CLASSIFY if schema['name'] == 'classify' else textile_tear().model_dump())
    async def progress(stage):
        events.append(stage)
    async def grounding():
        events.append('grounding')
    c = client_for(tmp_path, handler)
    try:
        req = prepare_request(make_req(make_image_b64((640, 480))))
        result = await analyze(req, c, progress, grounding)
        assert events == ['classify', 'segment', 'grounding', 'diagnose', 'plan']
        assert [s.source for s in result.segments] == ['text', 'grounding']
        assert result.segments[1].mask.points and result.instances == {'tear': 1}
        cost = c.budget.spent_today()
        assert len(seen) == 10  # 6 SAM concepts + classify + grounding (Spark, SAM box) + diagnose
        await analyze(req, c)
        assert len(seen) == 10 and c.budget.spent_today() == cost
    finally:
        await c.aclose()


@pytest.mark.parametrize('box', [None, [600, 500, 200, 300], [1001, 1001, 1002, 1002]])
async def test_grounding_no_damage_or_invalid_box_never_calls_sam(tmp_path, image_b64, box):
    def handler(req):
        assert req.url.path == '/v1/chat/completions'
        return chat_response({'concept': 'tear', 'box': box})
    c = client_for(tmp_path, handler)
    try:
        if box is None:
            assert await c.ground(make_req(image_b64), 'textile') == []
        else:
            with pytest.raises(ModelOutputError):
                await c.ground(make_req(image_b64), 'textile')
            assert not list((tmp_path / 'model_calls').glob('*.json'))
    finally:
        await c.aclose()


async def test_grounding_requires_sam_mask_not_just_spark_box(tmp_path, image_b64):
    def handler(req):
        if req.url.path == '/v1/chat/completions':
            return chat_response({'concept': 'tear', 'box': [100, 100, 500, 500]})
        return sam_response('<0f>1<|box;x1=10;y1=10;x2=15;y2=15;w=64;h=48;c=0.9|>')
    c = client_for(tmp_path, handler)
    try:
        assert await c.ground(make_req(image_b64), 'textile') == []
    finally:
        await c.aclose()


async def test_tracking_input_video_stream_official_parser_cache_and_cost(tmp_path):
    seen = []
    def handler(req):
        assert req.url.path == '/v1/responses'
        data = json.loads(req.content)
        seen.append(data)
        assert data['input'][0]['content'] == [
            {'type': 'input_text', 'text': 'tear'},
            {'type': 'input_video', 'video_url': 'data:video/mp4;base64,' + VIDEO_B64}]
        assert data['metadata'] == {'mask_encoding': 'one_bit', 'include_confidence': 'true'}
        assert data['stream'] is True and req.headers['accept'] == 'text/event-stream'
        return sam_response((SAM.parent / 'tracking.txt').read_text())
    c = client_for(tmp_path, handler)
    try:
        body = TrackRequest(video_base64=VIDEO_B64, concept='tear')
        result = await c.track(body)
        assert len(result.frames) == 10 and result.fps is None
        assert result.frames[5].segments == []
        assert result.frames[9].segments[0].object_id == '7'
        assert result.frames[9].segments[0].mask.rings
        assert result == await c.track(body) and len(seen) == 1
        assert c.budget.spent_today() == pytest.approx(0.01)  # minimum 50 frames
    finally:
        await c.aclose()


@pytest.mark.parametrize('text,status', [('', 'incomplete'), ('<3f>bad record', 'completed')])
async def test_invalid_tracking_is_not_cached(tmp_path, text, status):
    c = client_for(tmp_path, lambda r: sam_response(text, status))
    try:
        with pytest.raises(ModelOutputError):
            await c.track(TrackRequest(video_base64=VIDEO_B64, concept='tear'))
        assert not list((tmp_path / 'model_calls').glob('*.json'))
    finally:
        await c.aclose()


async def test_preview_actual_images_edit_multipart_cache_and_cost(tmp_path, image_b64):
    seen = []
    def handler(req):
        seen.append(req)
        assert req.url.path == '/v1/images/edits'
        assert req.headers['authorization'] == 'Bearer LLM_fake'
        msg = BytesParser(policy=policy.default).parsebytes(
            ('Content-Type: ' + req.headers['content-type'] + '\r\n\r\n').encode() + req.content)
        parts = {p.get_param('name', header='content-disposition'): p for p in msg.iter_parts()}
        assert set(parts) == {'image', 'model', 'prompt', 'n', 'response_format', 'reasoning_strength'}
        assert parts['reasoning_strength'].get_payload(decode=True) == b'low'
        assert parts['model'].get_payload(decode=True) == b'muse-image-1.0'
        assert parts['response_format'].get_payload(decode=True) == b'b64_json'
        assert parts['n'].get_payload(decode=True) == b'1'
        prompt = parts['prompt'].get_payload(decode=True).decode()
        assert 'Riss entlang der Naht' in prompt and 'ladder stitch' in prompt and 'nothing else changed' in prompt
        assert parts['image'].get_content_type() == 'image/png'
        photo = Image.open(io.BytesIO(parts['image'].get_payload(decode=True)))
        assert photo.format == 'PNG' and photo.size == (64, 48)
        return httpx.Response(200, json={'created': 0, 'data': [{'b64_json': image_b64}]})
    c = client_for(tmp_path, handler)
    try:
        body = AfterPreviewRequest(image_base64=image_b64, diagnosis_summary='Riss entlang der Naht', stitch_type='ladder_stitch')
        first = await c.after_preview(body)
        assert first.model_dump() == {'image_base64': image_b64, 'model': 'muse-image-1.0'}
        assert first == await c.after_preview(body) and len(seen) == 1
        assert c.budget.spent_today() == pytest.approx(0.01)
        await c.after_preview(body.model_copy(update={'diagnosis_summary': 'Riss entlang der Naht, 5 cm'}))
        assert len(seen) == 2 and c.budget.spent_today() == pytest.approx(0.02)
    finally:
        await c.aclose()


@pytest.mark.parametrize('data', [[], [{'url': 'https://example.com/do-not-fetch.png'}], [{'b64_json': 'AAAA'}],
                                  ['bad item'], {'bad': 'envelope'}, [{'b64_json': 123}]])
async def test_preview_invalid_output_never_caches_or_fetches_url(tmp_path, image_b64, data):
    seen = []
    def handler(req):
        seen.append(req)
        assert req.url.path == '/v1/images/edits'
        return httpx.Response(200, json={'created': 0, 'data': data})
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(ModelOutputError):
            await c.after_preview(AfterPreviewRequest(image_base64=image_b64, diagnosis_summary='Riss', stitch_type='darning'))
        assert len(seen) == 1 and c.budget.spent_today() == pytest.approx(0.01)
        assert not list((tmp_path / 'model_calls').glob('*.json'))
    finally:
        await c.aclose()


@pytest.mark.parametrize('status', [400, 429, 500])
async def test_preview_http_errors_have_no_sdk_retries(tmp_path, image_b64, status):
    seen = []
    def handler(req):
        seen.append(req)
        return httpx.Response(status, json={'error': {'message': 'offline failure'}})
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(AppError) as exc:
            await c.after_preview(AfterPreviewRequest(image_base64=image_b64, diagnosis_summary='Riss', stitch_type='darning'))
        assert exc.value.code == 'upstream_error' and len(seen) == 1
    finally:
        await c.aclose()


async def test_preview_timeout_is_controlled(tmp_path, image_b64):
    def handler(req):
        raise httpx.ReadTimeout('offline timeout', request=req)
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(AppError) as exc:
            await c.after_preview(AfterPreviewRequest(image_base64=image_b64, diagnosis_summary='Riss', stitch_type='darning'))
        assert exc.value.code == 'timeout'
    finally:
        await c.aclose()


@pytest.mark.parametrize('text', ['', '<0f>\n<1f>\n'])
async def test_tracking_zero_matches_and_empty_frames_are_cached(tmp_path, text):
    seen = []
    def handler(req):
        seen.append(req)
        return sam_response(text)
    c = client_for(tmp_path, handler)
    try:
        req = TrackRequest(video_base64=VIDEO_B64, concept='tear')
        first = await c.track(req)
        assert all(not f.segments for f in first.frames)
        assert first == await c.track(req) and len(seen) == 1
    finally:
        await c.aclose()


async def test_tracking_missing_completion_is_not_cached(tmp_path):
    def handler(req):
        event = {'type': 'response.output_text.delta', 'delta': (SAM.parent / 'tracking.txt').read_text(),
                 'item_id': 'msg', 'output_index': 0, 'content_index': 0, 'sequence_number': 0}
        return httpx.Response(200, headers={'Content-Type': 'text/event-stream'}, text='data: ' + json.dumps(event) + '\n\n')
    c = client_for(tmp_path, handler)
    try:
        with pytest.raises(ModelOutputError):
            await c.track(TrackRequest(video_base64=VIDEO_B64, concept='tear'))
        assert not list((tmp_path / 'model_calls').glob('*.json'))
    finally:
        await c.aclose()
