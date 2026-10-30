"""Public JSON contracts and deterministic mock behaviour; no external transports."""
import base64
import io

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.budget import Budget
from app.images import downscale_b64
from app.main import create_app
from app.models import AnalyzeResponse, Mask, Segment
from tests.test_api import parse_sse

# Synthetic ISO BMFF header only. It tests input/wire handling, not video decoding.
VIDEO_B64 = base64.b64encode(b'\x00\x00\x00\x18ftypisom\x00\x00\x00\x00isommp42').decode()


def test_refine_mock_multiple_points_and_holes(client, image_b64):
    body = {'image_base64': image_b64, 'label': 'Riss', 'box': [0.1, 0.1, 0.8, 0.8],
            'points': [{'x': x, 'y': 0.5, 'label': 'negative'} for x in (0.3, 0.7)]}
    first = client.post('/refine', json=body)
    assert first.status_code == 200
    assert first.json() == client.post('/refine', json=body).json()
    segment = first.json()
    assert set(segment) == {'id', 'label', 'kind', 'prompt', 'box', 'mask', 'score', 'source', 'polarity'}
    assert segment['source'] == 'tap' and segment['label'] == 'Riss' and segment['kind'] == 'damage'
    assert segment['mask']['points'] == segment['mask']['rings'][0]['points']
    assert sum(r['hole'] for r in segment['mask']['rings']) == 2
    body.pop('box')
    body['points'] = [{'x': 0, 'y': 0, 'label': 'positive'}, {'x': 1, 'y': 1, 'label': 'positive'}]
    result = client.post('/refine', json=body).json()
    assert len(result['mask']['rings']) == 2 and result['box'] == [0, 0, 1, 1]


@pytest.mark.parametrize('geometry', [
    {}, {'points': [{'x': 0.5, 'y': 0.5, 'label': 'negative'}]},
    {'points': [{'x': -0.01, 'y': 0.5, 'label': 'positive'}]},
    {'points': [{'x': 0.5, 'y': 1.01, 'label': 'positive'}]},
    {'points': [{'x': 0.5, 'y': 0.5, 'label': 'wrong'}]},
    {'box': [0.5, 0.1, 0.6, 0.2]}, {'box': [0, 0, 0, 1]}, {'box': [0, 0, 1]},
])
def test_refine_invalid_geometry_is_422(client, image_b64, geometry):
    assert client.post('/refine', json={'image_base64': image_b64, 'label': 'Riss', **geometry}).status_code == 422


def test_grounding_sse_preserves_every_existing_stage(client, image_b64):
    body = {'image_base64': image_b64, 'mock_scenario': 'textile_grounding'}
    response = client.post('/analyze', json=body)
    events = parse_sse(response.text)
    assert [name for name, _ in events] == ['progress', 'progress', 'grounding', 'segments', 'progress', 'progress', 'result']
    assert [data['stage'] for name, data in events if name == 'progress'] == ['classify', 'segment', 'diagnose', 'plan']
    assert events[2][1] == {'label': 'Schadstelle genauer lokalisieren'}
    result = events[-1][1]
    assert events[3][1] == {'segments': result['segments']}
    assert [s['source'] for s in result['segments']] == ['text', 'grounding']
    assert [s['id'] for s in result['segments']] == ['seg_1', 'seg_2']
    assert result['instances'] == {'tear': 1}
    assert client.post('/analyze?stream=false', json=body).json()['segments'] == result['segments']


def test_multi_instances_and_legacy_json_roundtrip(client, image_b64):
    result = client.post('/analyze?stream=false', json={'image_base64': image_b64, 'mock_scenario': 'textile_multi'}).json()
    assert result['instances'] == {'tear': 2}
    assert len(result['segments']) == len({s['id'] for s in result['segments']}) == 3
    assert AnalyzeResponse.model_validate(result).model_dump(mode='json') == result
    result.pop('instances')
    for s in result['segments']:
        s.pop('source')
        s['mask'].pop('rings')
    old = AnalyzeResponse.model_validate(result)
    assert old.instances is None and all(s.source is None and s.mask.rings is None for s in old.segments)
    assert Mask(points=[[0, 0], [1, 0], [1, 1]]).rings is None


def test_rings_mock_scenario(client, image_b64):
    result = client.post('/analyze?stream=false', json={'image_base64': image_b64, 'mock_scenario': 'textile_rings'}).json()
    mask = next(s['mask'] for s in result['segments'] if s['kind'] == 'damage')
    assert [r['hole'] for r in mask['rings']] == [False, True, True, False]
    assert mask['points'] == mask['rings'][0]['points']


def test_track_mock_wire_contract(client):
    body = {'video_base64': VIDEO_B64, 'concept': 'tear'}
    response = client.post('/track', json=body)
    assert response.status_code == 200 and response.json() == client.post('/track', json=body).json()
    data = response.json()
    assert set(data) == {'frames', 'fps'} and data['fps'] == 10
    assert [f['index'] for f in data['frames']] == list(range(10))
    for frame in data['frames']:
        assert set(frame) == {'index', 'segments'}
        segment = frame['segments'][0]
        assert segment['object_id'] == '7' and segment['id'] == 'seg_7'
        assert Segment.model_validate(segment).source == 'text'
    assert data['frames'][0]['segments'][0]['box'] != data['frames'][-1]['segments'][0]['box']


@pytest.mark.parametrize('value', ['', 'not base64', 'AAAA', base64.b64encode(b'not an mp4 file!!').decode()])
def test_invalid_video_is_rejected(client, value):
    response = client.post('/track', json={'video_base64': value, 'concept': 'tear'})
    assert response.status_code == 422 and response.json()['error']['code'] == 'invalid_video'


def test_preview_mock_changes_only_small_region(client, image_b64):
    body = {'image_base64': image_b64, 'diagnosis_summary': 'Riss entlang der Naht', 'stitch_type': 'ladder_stitch'}
    response = client.post('/after-preview', json=body)
    assert response.status_code == 200 and response.json() == client.post('/after-preview', json=body).json()
    data = response.json()
    assert set(data) == {'image_base64', 'model'} and data['model'] == 'muse-image-1.0'
    before = np.array(Image.open(io.BytesIO(base64.b64decode(downscale_b64(image_b64))))).astype(int)
    after = np.array(Image.open(io.BytesIO(base64.b64decode(data['image_base64'])))).astype(int)
    changed = np.any(before != after, axis=2)
    assert before.shape == after.shape and 0 < changed.sum() < changed.size * 0.02
    assert np.abs(before - after).max() == 3
    assert client.get('/health').json()['spent_today_usd'] == 0


@pytest.mark.parametrize('path,fields', [
    ('/refine', {'label': 'Riss', 'box': [0, 0, 1, 1]}),
    ('/after-preview', {'diagnosis_summary': 'Riss', 'stitch_type': 'darning'}),
])
def test_new_image_endpoints_validate_images(client, path, fields):
    result = client.post(path, json={'image_base64': 'AAAA', **fields})
    assert result.status_code == 422 and result.json()['error']['code'] == 'invalid_image'


@pytest.mark.parametrize('path,body', [
    ('/refine', {'image_base64': 'AAAA', 'label': 'Riss', 'box': [0, 0, 1, 1]}),
    ('/track', {'video_base64': VIDEO_B64, 'concept': 'tear'}),
    ('/after-preview', {'image_base64': 'AAAA', 'diagnosis_summary': 'Riss', 'stitch_type': 'darning'}),
])
def test_new_endpoints_respect_budget_before_model_calls(settings, path, body):
    budget = Budget(settings.cache_dir / 'b.json', 0.01)
    budget.add(0.01)
    with TestClient(create_app(settings, budget=budget)) as client:
        result = client.post(path, json=body)
    assert result.status_code == 429 and result.json()['error']['code'] == 'budget_exceeded'


def test_step_image_needs_a_step_and_returns_an_image(client, image_b64):
    body = {'image_base64': image_b64, 'diagnosis_summary': 'Small hole in grey knit', 'step_title': 'Weave lengthwise threads',
            'step_text': 'Lay parallel threads across the hole.'}
    response = client.post('/step-image', json=body)
    assert response.status_code == 200 and set(response.json()) == {'image_base64', 'model'}
    missing = client.post('/step-image', json={k: v for k, v in body.items() if k != 'step_title'})
    assert missing.status_code == 422 and missing.json()['error']['code'] == 'bad_request'
