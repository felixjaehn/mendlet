"""/detect, early `segments` event, weak-segment filter, after-preview variants and the Wonder agent. All offline."""
import base64
import io
import json

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.budget import wonder_cost
from app.config import Settings
from app.images import prepare_request
from app.main import create_app
from app.mock_client import MockClient
from app.mock_data import seg, textile_tear
from app.models import AfterPreviewRequest, DetectRequest
from app.pipeline import analyze
from app.agent import TOOLS, render_mask_overlay
from app.clients import preview_prompt
from app.sam import SamDetection, detections_to_segments, filter_weak_segments
from tests.conftest import make_image_b64, make_req
from tests.test_api import parse_sse
from tests.test_wire_contracts import CLASSIFY, SAM, chat_response, client_for, sam_response


def box_seg(sid, kind, prompt, score, box):
    x, y, w, h = box
    s = seg(sid, prompt, kind, prompt, score, [[x, y], [x + w, y], [x + w, y + h], [x, y + h]])
    return s


# ---- weak-segment filter (live pulli and sneaker cases, docs/benchmark.md) -------------------


def test_filter_pulli_drops_overlapping_weak_rips():
    holes = [box_seg(f'h{i}', 'damage', 'hole', 0.78, (0.1 + 0.3 * i, 0.4, 0.1, 0.1)) for i in range(3)]
    rips = [box_seg('r0', 'damage', 'rip', 0.52, (0.12, 0.42, 0.08, 0.06)),  # inside hole 1
            box_seg('r1', 'damage', 'rip', 0.52, (0.35, 0.38, 0.12, 0.12))]  # IoU > 0.3 with hole 2
    garment = box_seg('g', 'part', 'garment', 0.97, (0.0, 0.0, 1.0, 1.0))
    out = filter_weak_segments([garment, *holes, *rips])
    assert [(s.id, s.prompt) for s in out] == [('seg_1', 'garment'), ('seg_2', 'hole'), ('seg_3', 'hole'), ('seg_4', 'hole')]


def test_filter_keeps_weak_damage_that_overlaps_nothing_stronger():
    strong = box_seg('a', 'damage', 'hole', 0.8, (0.1, 0.1, 0.1, 0.1))
    far = box_seg('b', 'damage', 'rip', 0.52, (0.7, 0.7, 0.1, 0.1))
    equal = box_seg('c', 'damage', 'rip', 0.8, (0.1, 0.1, 0.1, 0.1))  # strong enough on its own
    assert [s.prompt for s in filter_weak_segments([strong, far, equal])] == ['hole', 'rip', 'rip']


def test_filter_sneaker_drops_weak_seams_keeps_strong_ones():
    sole = box_seg('a', 'part', 'shoe sole', 0.91, (0.05, 0.6, 0.9, 0.25))
    detached = box_seg('b', 'damage', 'detached sole', 0.84, (0.05, 0.62, 0.3, 0.2))
    seams = [box_seg(f's{i}', 'part', 'seam', sc, (0.1 + 0.2 * i, 0.5, 0.1, 0.05))
             for i, sc in enumerate([0.51, 0.55, 0.58, 0.63])]
    out = filter_weak_segments([sole, detached, *seams])
    assert [(s.prompt, s.score) for s in out] == [('shoe sole', 0.91), ('detached sole', 0.84), ('seam', 0.63)]
    assert [s.id for s in out] == ['seg_1', 'seg_2', 'seg_3']


def test_filter_caps_parts_at_three_best():
    parts = [box_seg(f'p{i}', 'part', 'seam', 0.6 + 0.05 * i, (0.1 * i, 0.1, 0.05, 0.05)) for i in range(5)]
    out = filter_weak_segments(parts)
    assert len(out) == 3 and sorted(s.score for s in out) == [0.7, 0.75, 0.8]


async def test_instances_follow_filtered_segments(image_b64):
    holes = [box_seg(f'h{i}', 'damage', 'hole', 0.78, (0.1 + 0.3 * i, 0.4, 0.1, 0.1)) for i in range(3)]
    rip = box_seg('r', 'damage', 'rip', 0.52, (0.12, 0.42, 0.08, 0.06))

    class Pulli(MockClient):
        async def segment(self, req, category, prompts):
            return filter_weak_segments([*holes, rip])

    result = await analyze(make_req(image_b64), Pulli(0.0))
    assert result.instances == {'hole': 3}


# ---- /detect ---------------------------------------------------------------------------------


def test_detect_mock_is_deterministic_and_matches_contract(client):
    body = {'image_base64': make_image_b64((300, 400)), 'concept': 'tear'}
    first = client.post('/detect', json=body)
    assert first.status_code == 200 and first.json() == client.post('/detect', json=body).json()
    [s] = first.json()['segments']
    assert s['id'] == 'damage_1' and s['kind'] == 'damage' and s['prompt'] == 'tear' and s['score'] >= 0.5
    assert len(s['mask']['points']) >= 3 and all(0 <= v <= 1 for p in s['mask']['points'] for v in p)
    assert len(s['box']) == 4
    for concept in ('hole', 'detached sole', 'wire'):
        assert client.post('/detect', json={**body, 'concept': concept}).json()['segments'][0]['prompt'] == concept


@pytest.mark.parametrize('body', [{'concept': 'tear'}, {'image_base64': 'AAAA', 'concept': 'tear'},
                                  {'image_base64': make_image_b64(), 'concept': ' '}])
def test_detect_invalid_requests(client, body):
    assert client.post('/detect', json=body).status_code == 422


async def test_detect_real_one_sam_call_downscaled_no_grounding_and_cached(tmp_path):
    seen = []
    def handler(req):
        data = json.loads(req.content)
        seen.append(req.url.path)
        assert req.url.path == '/v1/responses' and data['model'] == 'sam-3.1'
        assert data['input'][0]['content'][0]['text'] == 'tear'
        png = base64.b64decode(data['input'][0]['content'][1]['image_url'].split(',', 1)[1])
        seen.append(Image.open(io.BytesIO(png)).size)
        return sam_response(SAM.read_text())
    c = client_for(tmp_path, handler)
    try:
        body = DetectRequest(image_base64=make_image_b64((640, 480)), concept='tear')
        segs = await c.detect(body)
        assert [s.id for s in segs] == ['damage_1'] and segs[0].kind == 'damage' and segs[0].mask is not None
        assert await c.detect(body) == segs and seen == ['/v1/responses', (640, 480)]  # cache hit, one call
    finally:
        await c.aclose()


async def test_detect_real_downscales_to_768_and_zero_match_returns_empty_without_grounding(tmp_path):
    seen = []
    def handler(req):
        seen.append((req.url.path, Image.open(io.BytesIO(base64.b64decode(
            json.loads(req.content)['input'][0]['content'][1]['image_url'].split(',', 1)[1]))).size))
        return sam_response('')
    c = client_for(tmp_path, handler)
    try:
        assert await c.detect(DetectRequest(image_base64=make_image_b64((1600, 1200)), concept='hole')) == []
        assert seen == [('/v1/responses', (768, 576))]  # no Spark grounding call
    finally:
        await c.aclose()


# ---- /analyze segments event -----------------------------------------------------------------


def test_segments_event_is_before_diagnose_and_equals_result(client, image_b64):
    events = parse_sse(client.post('/analyze', json={'image_base64': image_b64, 'mock_scenario': 'textile_multi'}).text)
    assert [n for n, _ in events] == ['progress', 'progress', 'segments', 'progress', 'progress', 'result']
    assert events[2][1]['segments'] == events[-1][1]['segments']
    assert [s['id'] for s in events[2][1]['segments']] == ['seg_1', 'seg_2', 'seg_3']


def test_blocked_case_has_no_segments_event(client, image_b64):
    names = [n for n, _ in parse_sse(client.post(
        '/analyze', json={'image_base64': image_b64, 'mock_scenario': 'battery_jacket'}).text)]
    assert 'segments' not in names and 'agent_step' not in names and names[-1] == 'result'


# ---- /after-preview ----------------------------------------------------------------------------


def test_preview_prompt_variants():
    base = dict(image_base64='x', diagnosis_summary='Sohle vorn gelöst')
    shoe = preview_prompt(AfterPreviewRequest(**base, category='shoe', repair_hint='Kleberrand sauber'))
    assert 're-glued' in shoe and 'no stitches' in shoe and 'no visible glue' in shoe
    assert 'thread' not in shoe and 'Kleberrand sauber' in shoe and 'nothing else changed' in shoe
    textile = preview_prompt(AfterPreviewRequest(**base, stitch_type='darning'))
    assert 'darning' in textile and 'matching thread' in textile and 're-glued' not in textile
    assert 'matching thread' in preview_prompt(AfterPreviewRequest(**base, category='textile'))


def test_after_preview_endpoint_optional_fields(client, image_b64):
    ok = client.post('/after-preview', json={'image_base64': image_b64, 'diagnosis_summary': 'Sohle', 'category': 'shoe'})
    assert ok.status_code == 200 and ok.json()['model'] == 'muse-image-1.0'
    old = client.post('/after-preview', json={'image_base64': image_b64, 'diagnosis_summary': 'Riss', 'stitch_type': 'darning'})
    assert old.status_code == 200
    for extra in ({'repair_hint': 'x' * 201}, {'category': 'electronics'}):
        r = client.post('/after-preview', json={'image_base64': image_b64, 'diagnosis_summary': 'Riss', **extra})
        assert r.status_code == 422


# ---- Wonder agent ------------------------------------------------------------------------------

IMAGE = make_image_b64((640, 480))


def fc(name, args, call_id):
    return {'type': 'function_call', 'id': 'fc_' + call_id, 'call_id': call_id, 'name': name,
            'arguments': args if isinstance(args, str) else json.dumps(args), 'status': 'completed'}


def wonder_response(n, *items):
    return httpx.Response(200, json={
        'id': f'resp_{n}', 'object': 'response', 'created_at': 0, 'model': 'muse-wonder-1.0', 'status': 'completed',
        'output': list(items), 'parallel_tool_calls': True, 'tool_choice': 'auto', 'tools': [],
        'usage': {'input_tokens': 1000, 'output_tokens': 200, 'total_tokens': 1200}})


def plan_args():
    return json.loads(json.dumps(textile_tear(stretch=False).model_dump()).replace('seg_2', 'seg_1'))


class Script:
    """Routes the offline transport: wonder rounds come from `rounds`, everything else is the classic wire."""

    def __init__(self, rounds, verify=None):
        self.rounds, self.verify = rounds, verify or (lambda seg_id: {'on_damage': True, 'issue': ''})
        self.wonder, self.paths, self.sam = [], [], []

    def __call__(self, req):
        data = json.loads(req.content)
        self.paths.append((req.url.path, data.get('model')))
        if req.url.path == '/v1/responses' and data['model'] == 'sam-3.1':
            self.sam.append(data['input'][0]['content'][0]['text'])
            return sam_response(SAM.read_text().replace('<0f>7', '<0f>1') if self.sam[-1] != 'empty' else '')
        if req.url.path == '/v1/responses':
            self.wonder.append(data)
            return self.rounds(len(self.wonder), data)
        schema = data['response_format']['json_schema']['name']
        if schema == 'classify':
            return chat_response(CLASSIFY)
        if schema == 'verify_mask':
            assert data['messages'][1]['content'][1]['image_url']['url'].startswith('data:image/jpeg;base64,')
            return chat_response(self.verify(json.loads(data['messages'][1]['content'][0]['text'])['label']))
        if schema == 'locate':
            return chat_response({'box': [100, 100, 500, 400]})
        if schema == 'grounding':
            return chat_response({'concept': 'tear', 'box': None})
        return chat_response(textile_tear(stretch=False).model_dump())  # diagnose


def agent_client(tmp_path, script):
    return client_for(tmp_path, script, agent_mode='wonder')


async def run_agent(c, **kw):
    steps, progress = [], []
    async def emit(step):
        steps.append(step)
    async def prog(stage):
        progress.append(stage)
    seen = []
    async def ready(segs):
        seen.append([s.id for s in segs])
    result = await analyze(prepare_request(make_req(IMAGE, **kw)), c, prog, segments_ready=ready, agent_step=emit)
    return result, steps, progress, seen


async def test_agent_full_loop_wire_steps_budget_and_contract(tmp_path):
    def rounds(n, data):
        if n == 1:
            assert data['model'] == 'muse-wonder-1.0' and data['tool_choice'] == 'auto'
            assert [t['name'] for t in data['tools']] == ['segment', 'segment_at', 'locate', 'verify_mask', 'finish']
            assert all(t['type'] == 'function' and 'function' not in t for t in data['tools'])  # flat format
            assert 'previous_response_id' not in data and 'nur die Wahrnehmung' in data['instructions']
            assert data['reasoning'] == {'effort': 'low'}  # docs/reasoning: nested on the Responses API
            assert next(t for t in data['tools'] if t['name'] == 'finish')['parameters']['properties'] == {}
            content = data['input'][0]['content']
            assert content[0]['type'] == 'input_text' and content[1]['image_url'].startswith('data:image/jpeg;base64,')
            return wonder_response(n, fc('segment', {'concept': 'rip'}, 'call_a'))
        if n == 2:
            assert data['previous_response_id'] == 'resp_1'
            [out] = data['input']
            assert out['type'] == 'function_call_output' and out['call_id'] == 'call_a'
            found = json.loads(out['output'])['segments']
            assert [f['segment_id'] for f in found] == ['seg_1'] and len(found[0]['box_0_1000']) == 4
            return wonder_response(n, fc('verify_mask', {'segment_id': 'seg_1'}, 'call_b'),
                                   fc('verify_mask', {'segment_id': 'seg_nope'}, 'call_c'))
        if n == 3:
            assert data['previous_response_id'] == 'resp_2'
            outs = {o['call_id']: json.loads(o['output']) for o in data['input']}
            assert outs['call_b']['on_damage'] is True and 'error' in outs['call_c']
            return wonder_response(n, fc('finish', {}, 'call_d'))
        raise AssertionError('unexpected round')
    script = Script(rounds)
    c = agent_client(tmp_path, script)
    try:
        result, steps, progress, seen = await run_agent(c)
        assert sorted((s['n'], s['tool'], s['status'], s['model']) for s in steps) == [
            (1, 'segment', 'done', 'sam-3.1'), (2, 'verify_mask', 'done', 'muse-spark-1.3'),
            (3, 'verify_mask', 'failed', 'muse-spark-1.3'), (4, 'finish', 'done', 'muse-wonder-1.0')]
        assert steps[0]['label'] == 'SAM sucht „rip“' and all(isinstance(s['ms'], int) for s in steps)
        assert [s.id for s in result.segments] == ['seg_1'] and result.segments[0].source == 'text'
        assert seen == [['seg_1']] and progress == ['classify', 'segment', 'diagnose', 'plan']
        assert result.instances == {'rip': 1} and result.guide.steps
        assert set(result.diagnosis.evidence_segment_ids) <= {'seg_1'}  # plan from prompt B, only kept segments
        assert ('/v1/chat/completions', 'muse-spark-1.3') in script.paths
        # three Wonder rounds at $4/$20 per 1M tokens (UNBESTÄTIGT only for live billing, price from the docs)
        assert len(script.wonder) == 3 and c.budget.spent_today() >= 3 * wonder_cost(1000, 200)
        assert wonder_cost(1_000_000, 1_000_000) == pytest.approx(24.0)
        assert wonder_cost(1_000_000, 0, cached_tokens=1_000_000) == pytest.approx(0.2)
    finally:
        await c.aclose()


async def test_agent_refines_after_failed_verify_and_drops_rejected_mask(tmp_path):
    def rounds(n, data):
        return {
            1: lambda: wonder_response(n, fc('segment', {'concept': 'rip'}, 'c1')),
            2: lambda: wonder_response(n, fc('verify_mask', {'segment_id': 'seg_1'}, 'c2')),
            3: lambda: wonder_response(n, fc('locate', {'description': 'Riss am Bein'}, 'c3')),
            4: lambda: wonder_response(n, fc('segment_at', {'box_0_1000': [100, 100, 500, 400], 'concept': 'rip',
                                                            'points': [{'x': 300, 'y': 250, 'label': 'positive'}]}, 'c4')),
            5: lambda: wonder_response(n, fc('finish', json.loads(
                json.dumps(plan_args()).replace('seg_1', 'seg_2')), 'c5')),
        }[n]()
    script = Script(rounds, verify=lambda label: {'on_damage': False, 'issue': 'mask covers intact fabric'})
    c = agent_client(tmp_path, script)
    try:
        result, steps, _, seen = await run_agent(c)
        assert [s['tool'] for s in steps] == ['segment', 'verify_mask', 'locate', 'segment_at', 'finish']
        locate_out = json.loads(script.wonder[3]['input'][0]['output'])
        assert locate_out['box_0_1000'] == [100, 100, 500, 400]
        assert json.loads(script.wonder[2]['input'][0]['output'])['on_damage'] is False
        assert [s.id for s in result.segments] == ['seg_2'] and result.segments[0].source == 'grounding'
        assert seen == [['seg_2']] and result.diagnosis.evidence_segment_ids == ['seg_2']
        assert script.sam[1].startswith('<0f>1<|box;')  # geometric prompt, one object
    finally:
        await c.aclose()


async def test_agent_finish_hands_off_to_prompt_b_diagnose(tmp_path):
    # Live 2026-10-29: plans written inside the loop ignored prompt B v3; Wonder now only perceives.
    def rounds(n, data):
        if n == 1:
            return wonder_response(n, fc('finish', {'diagnosis': 'ignored'}, 'c1'))
        raise AssertionError('no second round expected')
    script = Script(rounds)
    c = agent_client(tmp_path, script)
    try:
        result, steps, _, _ = await run_agent(c)
        assert [(s['tool'], s['status']) for s in steps] == [('finish', 'done')]
        assert ('/v1/chat/completions', 'muse-spark-1.3') in script.paths and result.guide.steps
    finally:
        await c.aclose()


async def test_agent_round_cap_is_eight_then_fallback(tmp_path):
    script = Script(lambda n, data: wonder_response(n, fc('locate', {'description': 'Riss'}, f'c{n}')))
    c = agent_client(tmp_path, script)
    try:
        result, steps, _, _ = await run_agent(c)
        assert len(script.wonder) == 8 and len(steps) == 8 and result.guide.steps
        assert [s['n'] for s in steps] == list(range(1, 9))
    finally:
        await c.aclose()


async def test_agent_text_only_answer_and_unknown_tool_are_survivable(tmp_path):
    def rounds(n, data):
        if n == 1:
            return wonder_response(n, fc('delete_everything', {}, 'c1'), fc('segment', '{kaputt', 'c2'))
        return wonder_response(n, {'type': 'message', 'id': 'm', 'role': 'assistant', 'status': 'completed',
                                   'content': [{'type': 'output_text', 'text': 'Fertig.', 'annotations': []}]})
    script = Script(rounds)
    c = agent_client(tmp_path, script)
    try:
        result, steps, _, _ = await run_agent(c)
        assert [s['status'] for s in steps] == ['failed', 'failed'] and result.guide.steps
    finally:
        await c.aclose()


async def test_agent_upstream_error_falls_back_to_classic_pipeline(tmp_path):
    def rounds(n, data):
        return httpx.Response(500, json={'error': {'message': 'boom'}})
    script = Script(rounds)
    c = agent_client(tmp_path, script)
    try:
        result, steps, progress, seen = await run_agent(c)
        assert steps == [] and result.guide.steps and progress == ['classify', 'segment', 'diagnose', 'plan']
        assert len(script.sam) == 6  # classic SAM concepts ran instead
    finally:
        await c.aclose()


async def test_agent_never_starts_for_blocked_cases(tmp_path):
    def blocked(n, data):
        raise AssertionError('agent must not start')
    script = Script(blocked)
    blocked_cls = {'category': 'textile', 'risk_level': 'warn_only', 'reason': 'Lithium-Akku'}
    c = agent_client(tmp_path, script)
    original = script.__call__
    def handler(req):
        data = json.loads(req.content)
        if req.url.path == '/v1/chat/completions' and data['response_format']['json_schema']['name'] == 'classify':
            return chat_response(blocked_cls)
        return original(req)
    c2 = client_for(tmp_path / 'b', handler, agent_mode='wonder')
    try:
        result, steps, _, seen = await run_agent(c2, user_note='Mein Akku raucht')
        assert result.safety.blocked and steps == [] and seen == []
        assert not any(path == '/v1/responses' for path, _ in script.paths)
        # the keyword gate also blocks without trusting the model
        result, steps, _, _ = await run_agent(c2, user_note='beheizbare Jacke mit Lithium Akku')
        assert result.safety.blocked and steps == []
    finally:
        await c.aclose()
        await c2.aclose()


def test_overlay_renders_mask_and_cuts_holes():
    from app.models import Mask, MaskRing
    outer = [[0.2, 0.2], [0.8, 0.2], [0.8, 0.8], [0.2, 0.8]]
    s = box_seg('s', 'damage', 'hole', 0.9, (0.2, 0.2, 0.6, 0.6)).model_copy(update={"mask": Mask(
        points=outer, rings=[MaskRing(points=outer, hole=False),
                             MaskRing(points=[[0.4, 0.4], [0.6, 0.4], [0.6, 0.6], [0.4, 0.6]], hole=True)])})
    img = Image.open(io.BytesIO(base64.b64decode(render_mask_overlay(IMAGE, s)))).convert('RGB')
    base = Image.open(io.BytesIO(base64.b64decode(IMAGE))).convert('RGB')
    assert img.getpixel((200, 150))[0] > base.getpixel((200, 150))[0] + 40  # red mask area
    assert abs(img.getpixel((320, 240))[0] - base.getpixel((320, 240))[0]) < 8  # hole stays untouched
    assert len({t['name'] for t in TOOLS}) == 5


# ---- mock agent mode (iOS demo) ----------------------------------------------------------------


def test_mock_agent_mode_streams_six_steps_in_order(tmp_path, image_b64):
    s = Settings(mock_mode=True, mock_delay_scale=0.0, cache_dir=tmp_path / '.cache', agent_mode='wonder')
    c = TestClient(create_app(s))
    assert c.get('/health').json()['agent_mode'] == 'wonder'
    events = parse_sse(c.post('/analyze', json={'image_base64': image_b64, 'mock_scenario': 'textile_tear'}).text)
    assert [n for n, _ in events] == ['progress', 'progress'] + ['agent_step'] * 6 + ['segments', 'progress', 'progress', 'result']
    steps = [d for n, d in events if n == 'agent_step']
    assert [d['n'] for d in steps] == [1, 2, 3, 4, 5, 6] and steps[-1]['tool'] == 'finish'
    assert all(set(d) == {'n', 'tool', 'label', 'model', 'status', 'ms'} and d['status'] == 'done' for d in steps)
    assert {d['model'] for d in steps} == {'sam-3.1', 'muse-spark-1.3', 'muse-wonder-1.0'}
    assert events[8][1]['segments'] == events[-1][1]['segments']
    blocked = parse_sse(c.post('/analyze', json={'image_base64': image_b64, 'mock_scenario': 'helmet'}).text)
    assert 'agent_step' not in [n for n, _ in blocked]


def test_agent_mode_default_off(client, image_b64):
    assert client.get('/health').json()['agent_mode'] == 'off'
    assert Settings.from_env({'AGENT_MODE': 'Wonder'}).agent_mode == 'wonder'
    assert Settings.from_env({'AGENT_MODE': 'bogus'}).agent_mode == 'off' and Settings.from_env({}).agent_mode == 'off'
