"""Official DeepSeek API; credentials are environment-only and never serialized."""
import time
import urllib.error
import urllib.request
from common import *

MODEL = 'deepseek-v4-pro'
ENDPOINT = 'https://api.deepseek.com/chat/completions'

def call(tag, system, payload, max_tokens=60000, thinking='enabled', effort=None, model=None):
    manifest = read(OUT / 'RUN_MANIFEST.json') if (OUT / 'RUN_MANIFEST.json').exists() else {}
    effort = effort or manifest.get('reasoning_effort', 'high')
    model = model or manifest.get('requested_model', MODEL)
    cache = OUT / 'api' / (tag + '.json')
    request_hash = canonical({'model': model, 'system': system, 'payload': payload,
                              'temperature': 0.2, 'thinking': thinking, 'reasoning_effort': effort, 'max_tokens': max_tokens})
    if cache.exists():
        data = read(cache)
        require(data['request_hash'] == request_hash, 'Cached API request version mismatch ' + tag)
        require(data['response_model'] == model and data['finish_reason'] == 'stop', 'Cached model/output incomplete or changed')
        return data
    key = os.environ.get('DEEPSEEK_API_KEY')
    require(bool(key), 'DEEPSEEK_API_KEY unavailable; no fallback permitted')
    body = {'model': model, 'messages': [{'role': 'system', 'content': system},
            {'role': 'user', 'content': json.dumps(payload, ensure_ascii=False, separators=(',', ':'))}],
            'temperature': 0.2, 'thinking': {'type': thinking}, 'reasoning_effort': effort,
            'max_tokens': max_tokens, 'response_format': {'type': 'json_object'}, 'stream': False}
    request = urllib.request.Request(ENDPOINT, data=json.dumps(body, ensure_ascii=False).encode(),
        headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    started = now()
    t = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=1200) as response:
            raw = json.load(response)
        choice = raw['choices'][0]
        result = {'tag': tag, 'request_hash': request_hash, 'started_utc': started,
                  'completed_utc': now(), 'elapsed_seconds': round(time.monotonic()-t, 3),
                  'requested_model': model, 'response_model': raw.get('model'),
                  'response_id': raw.get('id'), 'system_fingerprint': raw.get('system_fingerprint'),
                  'finish_reason': choice.get('finish_reason'), 'usage': raw.get('usage'),
                  'content': choice['message'].get('content'), 'endpoint': ENDPOINT,
                  'credentials_in_file': False, 'reasoning_content_persisted': False}
        save(cache, result)
        require(result['response_model'] == model, 'Provider returned different model; stop, no fallback')
        require(result['finish_reason'] == 'stop', 'Incomplete model output; checkpoint kept: ' + tag)
        return result
    except Exception as exc:
        # Never persist request headers, exception repr, HTTP response body or environment.
        failure = {'tag': tag, 'request_hash': request_hash, 'started_utc': started,
                   'completed_utc': now(), 'error_type': type(exc).__name__,
                   'http_status': exc.code if isinstance(exc, urllib.error.HTTPError) else None,
                   'model': model, 'no_fallback': True, 'usage_unknown_for_failed_request': True}
        save(OUT / 'failures' / (tag + '.json'), failure)
        raise RuntimeError('Model call failed/checkpointed: ' + tag + ' (' + type(exc).__name__ + ')') from None

def system_prompt(kind):
    name = 'PROMPT.md' if kind == 'generation' else 'REVIEW_PROMPT.md'
    return (ROOT / 'scripts/p6c5' / name).read_text(encoding='utf-8') + '\n\n--- FROZEN V4.1 RULES ---\n' + RULES.read_text(encoding='utf-8')
