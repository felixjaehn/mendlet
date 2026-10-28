import json
import os
from pathlib import Path

import httpx
import pytest

from app.models import ClassifyResult
from scripts.smoke_real import CAP_USD, RESERVATIONS, SmokeState, main, run
from tests.test_api import wav_bytes
from tests.test_wire_contracts import chat_response, sam_response
from tests.conftest import make_image_b64
import base64


def inputs(tmp_path):
    image = tmp_path / 'input.png'
    image.write_bytes(base64.b64decode(make_image_b64((640,480))))
    audio = tmp_path / 'speech.wav'
    audio.write_bytes(wav_bytes())
    return image, audio


def transport_handler(seen, fail=None):
    def handler(req):
        path = req.url.path
        seen.append(path)
        if path == fail:
            return httpx.Response(500, json={'error': {'message': 'offline failure'}})
        if path == '/v1/chat/completions':
            data = json.loads(req.content)
            assert data['max_completion_tokens'] == 2048
            assert data['response_format']['type'] == 'json_schema'
            assert len(data['messages'][1]['content']) == 1  # no speculative image billing
            return chat_response({'category':'unsupported', 'risk_level':'warn_only', 'reason':'Kein Foto'})
        if path == '/v1/responses':
            data = json.loads(req.content)
            assert data['model'] == 'sam-3.1'
            assert data['input'][0]['content'][1]['type'] == 'input_image'
            return sam_response((Path(__file__).parent / 'fixtures/sam/thin_tear.txt').read_text())
        assert path == '/v1/asr/transcribe'
        return httpx.Response(200, json={'transcript':'Riss in der Hose'})
    return handler


async def test_no_key_does_nothing_even_with_bad_paths(tmp_path, monkeypatch, capsys):
    monkeypatch.delenv('META_API_KEY', raising=False)
    monkeypatch.setenv('MODEL_API_KEY', 'not-the-opt-in')
    assert main(['missing.png']) == 0
    assert await run(tmp_path / 'missing.png', '', tmp_path / 'absent') == 0
    assert not (tmp_path / 'absent').exists()
    assert 'SKIP' in capsys.readouterr().out


async def test_one_call_each_then_zero_on_replay(tmp_path, capsys):
    image, audio = inputs(tmp_path)
    cache = tmp_path / 'cache'
    seen = []
    for attempt in range(2):
        http = httpx.AsyncClient(transport=httpx.MockTransport(transport_handler(seen)))
        assert await run(image, 'LLM_fake', cache, audio, http_client=http) == 0
        assert len(seen) == 3
    assert sorted(seen) == sorted(['/v1/chat/completions','/v1/responses','/v1/asr/transcribe'])
    data = json.loads((cache / 'attempts.json').read_text())
    assert len(data['models']) == 3
    assert sum(e['reserved_usd'] for e in data['models'].values()) <= CAP_USD
    assert all(e['status'] == 'pass' for e in data['models'].values())
    assert 'CACHED; no request' in capsys.readouterr().out
    # Neither uploaded image/audio nor the credential is persisted.
    assert 'LLM_fake' not in (cache / 'attempts.json').read_text()
    assert image.read_bytes() not in (cache / 'attempts.json').read_bytes()


async def test_no_sdk_or_validation_retry_even_after_failure(tmp_path):
    image, audio = inputs(tmp_path)
    seen = []
    for attempt in range(2):
        http = httpx.AsyncClient(transport=httpx.MockTransport(transport_handler(seen, '/v1/chat/completions')))
        assert await run(image, 'LLM_fake', tmp_path / 'cache', audio, http_client=http) == 1
    assert len(seen) == 3


async def test_changed_inputs_cannot_make_a_second_model_attempt(tmp_path):
    image, audio = inputs(tmp_path)
    seen = []
    cache = tmp_path / 'cache'
    http = httpx.AsyncClient(transport=httpx.MockTransport(transport_handler(seen)))
    assert await run(image, 'LLM_fake', cache, audio, http_client=http) == 0
    image.write_bytes(base64.b64decode(make_image_b64((640,480), (10,20,30))))
    http = httpx.AsyncClient(transport=httpx.MockTransport(transport_handler(seen)))
    assert await run(image, 'LLM_fake', cache, audio, http_client=http) == 1
    assert len(seen) == 3


async def test_interrupted_attempt_is_reserved_and_never_replayed(tmp_path):
    cache = tmp_path / 'cache'
    async def interrupted():
        raise KeyboardInterrupt()
    with pytest.raises(KeyboardInterrupt):
        with SmokeState(cache) as state:
            await state.probe('sam-3.1', 'same', interrupted)
    async def forbidden():
        pytest.fail('must never call after uncertain interruption')
    with SmokeState(cache) as state:
        ok, report, cached = await state.probe('sam-3.1', 'same', forbidden)
        assert not ok and cached
        assert state.reserved == RESERVATIONS['sam-3.1']


async def test_hard_reservation_cap_before_call(tmp_path):
    with SmokeState(tmp_path / 'cache') as state:
        # Simulate existing valid reservations that almost exhaust the fixed cap.
        state.data['models']['previous'] = {'reserved_usd': 0.099}
        async def forbidden():
            pytest.fail('cost guard must run before network')
        ok, report, _ = await state.probe('sam-3.1', 'same', forbidden)
        assert not ok and 'cap' in report


def test_lock_prevents_simultaneous_spending(tmp_path):
    with SmokeState(tmp_path / 'cache'):
        with pytest.raises(BlockingIOError):
            with SmokeState(tmp_path / 'cache'):
                pytest.fail('second process acquired the spend lock')


async def test_bad_audio_preflight_spends_nothing(tmp_path):
    image, audio = inputs(tmp_path)
    audio.write_bytes(wav_bytes(seconds=6))
    with pytest.raises(ValueError):
        await run(image, 'LLM_fake', tmp_path / 'cache', audio)
    assert not (tmp_path / 'cache').exists()


def test_corrupt_ledger_fails_closed(tmp_path):
    cache = tmp_path / 'cache'
    cache.mkdir()
    (cache / 'attempts.json').write_text('not json')
    with pytest.raises(ValueError):
        with SmokeState(cache):
            pytest.fail('corrupt accounting must never reset to zero')


def test_missing_ledger_with_existing_usage_never_resets_allowance(tmp_path):
    cache = tmp_path / 'cache'
    cache.mkdir()
    (cache / 'usage.json').write_text('{}')
    with pytest.raises(ValueError):
        with SmokeState(cache):
            pytest.fail('must not reset prior accounting')


async def test_bad_ledger_fields_fail_closed_before_requests(tmp_path):
    cache = tmp_path / 'cache'
    cache.mkdir()
    (cache / 'attempts.json').write_text(json.dumps({'version': 1, 'models': {
        'sam-3.1': {'reserved_usd': -1, 'status': 'pass', 'fingerprint': 'x', 'report': 'PASS'}}}))
    with pytest.raises(ValueError):
        with SmokeState(cache):
            pytest.fail('invalid reservation cannot bypass cap')
