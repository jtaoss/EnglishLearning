"""P5-C.4A one-off Notion vocabulary importer.

Dry-run is the only path used by ordinary runs. A live create client is built
only after a separate write authorization. This module does not open the personal learning database, does not upload learning events, and has no update or delete request.
"""
from __future__ import annotations

import csv
import datetime
import hashlib
import json
import os
import pathlib
import re
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parents[2]
FORMAL_SHA = '9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb'
FORMAL_SOURCE = '157d89e5-71fb-4e68-9640-1b04dbb1e627'
EVENT_SANDBOX_SOURCE = '3bf5dab6-53fc-4ba8-bcf4-cec0be0addd8'
READ_ONLY_TARGET = 'EnglishLearning.Notion.ReadOnly.v1'
WRITE_TARGET = 'EnglishLearning.Notion.VocabularyWrite.v1'
KNOWN_BLANK_PAGE_ID = '414cd5b5-d6b9-80db-ac03-d94e99d65e61'
KNOWN_BLANK_CLASS = '主学习'
ISOLATED_PENDING_IDS = ('SG25-de2c2dcff9ee', 'SG25-dc2c5be187f6')
API_VERSION = '2026-03-11'
WRITE_ENV = 'ENGLISHLEARNING_P5C4_WRITE_AUTHORIZATION'
WRITE_ENV_VALUE = 'authorize-p5c4-notion-vocabulary-write'
WRITE_FULL_ENV = 'ENGLISHLEARNING_P5C4C_WRITE_AUTHORIZATION'
WRITE_FULL_ENV_VALUE = 'authorize-p5c4c-notion-vocabulary-write'
WRITE_RESUME_ENV = 'ENGLISHLEARNING_P5C4C3_WRITE_AUTHORIZATION'
WRITE_RESUME_ENV_VALUE = 'authorize-p5c4c3-notion-vocabulary-write'
RESUME_CREATE = 4277
WRITE_STATEMENT = '我授权本次 Notion 词库写入'
EXPECTED = {
    'formal': 5332,
    'unchanged': 500,
    'create': 4832,
    'update': 0,
    'pending': 194,
    'deferred': 27,
}
ID_PATTERN = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._:\-]{0,99}$')
BATCH_SIZE = 10
REMAINING_CREATE = EXPECTED['create'] - BATCH_SIZE
QUERY_GROUP = 100
SPACING_SECONDS = 0.35
MAX_RETRY_AFTER = 10
MAX_RATE_ATTEMPTS = 3
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
UNCERTAIN = {'awaiting_result', 'created_unverified', 'pending_reconciliation'}
FORBIDDEN = {
    '学习状态', '发音状态', '自然拼读状态', '自然拼读笔记', '听音学习状态', '听音学习笔记',
    '笔记', '评级', '复习日期', '学习事件',
}
PRESERVED_AUDIT = (
    'AI 筛选理由', '筛选置信度', '原记录ID', '原始词头', '清洗记录', '原书书内页码', '分类依据',
)
CREATE_AUDIT = {'原5552台账内': '是', '发音资源状态': '未配置'}
CONTENT = (
    ('entry_id', '词条ID', 'rich_text'),
    ('word', '单词', 'title'),
    ('meaning_zh', '中文词义', 'rich_text'),
    ('book_category', '原书分类', 'select'),
    ('source_file', '来源文件', 'rich_text'),
    ('source_id', '来源ID', 'rich_text'),
    ('source_pdf_pages', '原书PDF页码', 'rich_text'),
    ('source_index_pages', '索引PDF页码', 'rich_text'),
    ('book_verification', '原书核验状态', 'select'),
    ('meaning_review_status', '释义复核说明', 'rich_text'),
    ('pets2015_status', 'PETS3 2015收录状态', 'select'),
    ('pets2025_status', 'PETS3 2025收录状态', 'select'),
    ('library_class', '学习词库分类', 'select'),
    ('part_of_speech', '词性', 'rich_text'),
    ('usage_note', '用法说明', 'rich_text'),
    ('lexical_sources', '释义来源', 'rich_text'),
    ('example_en', '原创例句', 'rich_text'),
    ('example_zh', '例句译文', 'rich_text'),
    ('learning_priority', '学习优先级', 'select'),
    ('selection_reason', '筛选理由', 'rich_text'),
    ('phonics_note', '拼读提示', 'rich_text'),
    ('syllables', '音节说明', 'rich_text'),
    ('stress', '重音说明', 'rich_text'),
    ('reading_review_status', '拼读复核说明', 'rich_text'),
    ('audio_status', '音频许可状态', 'rich_text'),
    ('audio_source', '标准音频来源', 'rich_text'),
    ('audio_license', '标准音频许可', 'rich_text'),
    ('pets2015_evidence', 'PETS3 2015证据', 'rich_text'),
    ('pets2015_match_method', 'PETS3 2015匹配方法', 'rich_text'),
)
CONTENT_FIELDS = tuple(item[0] for item in CONTENT)
CONTENT_PROPERTIES = tuple(item[1] for item in CONTENT)
PROPERTY_TYPES = {item[1]: item[2] for item in CONTENT}
PROPERTY_TYPES.update({'原5552台账内': 'select', '发音资源状态': 'select'})
REQUIRED_FIELDS = CONTENT_FIELDS[:13]
READ_REQUESTS = {'schema', 'query', 'query_all'}
WRITE_REQUESTS = READ_REQUESTS | {'create'}


class PlanError(RuntimeError):
    pass


class QueryFailed(RuntimeError):
    pass


class RateLimited(RuntimeError):
    def __init__(self, retry_after):
        super().__init__('rate_limited')
        self.retry_after = retry_after


class UncertainResult(RuntimeError):
    def __init__(self, kind):
        super().__init__(kind)
        self.kind = kind


class DefinitiveReject(RuntimeError):
    def __init__(self, status):
        super().__init__(f'rejected_{status}')
        self.status = status


@dataclass
class PageView:
    page_id: str
    entry_id: str
    values: dict
    archived: bool = False


@dataclass
class Plan:
    rows: list
    states: dict
    payloads: dict
    conflicts: list
    errors: list
    casefold_collisions: list
    counts: dict
    trial_ids: list
    create_ids_sha256: str
    formal_sha256: str = ''
    official: bool = False
    max_rich_text: int = 0

    @property
    def blocked(self):
        return bool(self.errors or self.conflicts)

    @property
    def ready(self):
        return (
            self.official
            and not self.blocked
            and self.formal_sha256 == FORMAL_SHA
            and self.counts == {
                'formal': EXPECTED['formal'],
                'unchanged': EXPECTED['unchanged'],
                'create': EXPECTED['create'],
                'update': 0,
                'conflict': 0,
                'pending': EXPECTED['pending'],
                'deferred': EXPECTED['deferred'],
            }
        )


@dataclass
class Record:
    entry_id: str
    word: str
    state: str
    content_sha256: str
    page_id: str = ''
    reason: str = ''
    batch_index: int = -1
    differing_fields: list = field(default_factory=list)


def now():
    return datetime.datetime.now().astimezone().isoformat(timespec='seconds')


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_id(value):
    return value.replace('-', '').lower()


def dashed_id(value):
    compact = normalize_id(value)
    if len(compact) != 32 or any(char not in '0123456789abcdef' for char in compact):
        raise PlanError('data source id refused')
    return f'{compact[0:8]}-{compact[8:12]}-{compact[12:16]}-{compact[16:20]}-{compact[20:32]}'


def read_csv(path):
    with open(path, encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))


def content_values(row):
    return {prop: row.get(field, '') or '' for field, prop, _kind in CONTENT}


def content_sha(values):
    payload = {name: values.get(name, '') or '' for name in CONTENT_PROPERTIES}
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(raw.encode()).hexdigest()


def create_payload(row):
    payload = content_values(row)
    if not payload['学习优先级']:
        payload.pop('学习优先级')
    payload.update(CREATE_AUDIT)
    overlap = set(payload) & FORBIDDEN
    if overlap or set(payload) & set(PRESERVED_AUDIT):
        raise PlanError('payload includes a property that must not be written')
    return payload


def differing_fields(expected, actual, names):
    return [name for name in names if (expected.get(name, '') or '') != (actual.get(name, '') or '')]


def text_runs(value):
    if not value:
        return []
    return [
        {'type': 'text', 'text': {'content': value[index:index + 2000]}}
        for index in range(0, len(value), 2000)
    ]


def encode_properties(plain):
    overlap = set(plain) & FORBIDDEN
    if overlap or set(plain) & set(PRESERVED_AUDIT):
        raise PlanError('personal or preserved audit property refused')
    encoded = {}
    for name, value in plain.items():
        kind = PROPERTY_TYPES.get(name)
        if kind is None or value is None:
            raise PlanError('unknown property refused')
        if kind == 'title':
            encoded[name] = {'title': text_runs(value)}
        elif kind == 'select':
            if not value:
                raise PlanError('empty select refused')
            encoded[name] = {'select': {'name': value}}
        elif kind == 'rich_text':
            encoded[name] = {'rich_text': text_runs(value)}
        else:
            raise PlanError('property type refused')
    return encoded


def build_create_body(data_source_id, plain):
    if normalize_id(data_source_id) != normalize_id(FORMAL_SOURCE):
        raise PlanError('data source refused')
    if normalize_id(data_source_id) == normalize_id(EVENT_SANDBOX_SOURCE):
        raise PlanError('event sandbox refused')
    return {
        'parent': {'type': 'data_source_id', 'data_source_id': dashed_id(data_source_id)},
        'properties': encode_properties(plain),
    }


def allowed_request(mode, kind):
    allowed = WRITE_REQUESTS if mode == 'write' else READ_REQUESTS
    if mode not in ('read', 'write') or kind not in allowed:
        raise PlanError('request refused')
    if mode == 'read' and kind == 'create':
        raise PlanError('read-only client cannot create pages')


def validate_schema(schema, data_source_id):
    if normalize_id(str(schema.get('id', ''))) != normalize_id(data_source_id):
        raise PlanError('schema id refused')
    if normalize_id(data_source_id) != normalize_id(FORMAL_SOURCE):
        raise PlanError('data source refused')
    properties = schema.get('properties') or {}
    missing = []
    for name, kind in PROPERTY_TYPES.items():
        if properties.get(name, {}).get('type') != kind:
            missing.append(name)
    if missing:
        raise PlanError('schema properties do not match the vocabulary mapping')
    for name, value in CREATE_AUDIT.items():
        options = ((properties.get(name) or {}).get('select') or {}).get('options') or []
        if value not in {option.get('name') for option in options}:
            raise PlanError(f'select option unavailable: {name}')
    return True


def plain_property(prop):
    if not isinstance(prop, dict):
        return None
    kind = prop.get('type')
    if kind in ('title', 'rich_text'):
        return ''.join(part.get('plain_text', '') for part in prop.get(kind) or [])
    if kind == 'select':
        selected = prop.get('select')
        return '' if not selected else selected.get('name', '')
    return None


def page_view(page):
    properties = page.get('properties') or {}
    values = {}
    for name in list(CONTENT_PROPERTIES) + list(PRESERVED_AUDIT) + list(CREATE_AUDIT) + sorted(FORBIDDEN):
        if name in properties:
            parsed = plain_property(properties[name])
            if parsed is None:
                raise QueryFailed()
            values[name] = parsed
    entry_id = values.get('词条ID', '')
    return PageView(
        str(page.get('id', '')),
        entry_id,
        values,
        archived=bool(page.get('archived') or page.get('in_trash')),
    )


def _validate_row(row, errors):
    entry_id = row.get('entry_id', '')
    if not ID_PATTERN.fullmatch(entry_id or ''):
        errors.append({'kind': 'bad_id', 'entry_id': entry_id})
        return False
    for key in REQUIRED_FIELDS:
        if not (row.get(key) or ''):
            errors.append({'kind': 'missing_field', 'entry_id': entry_id, 'field': key})
            return False
    if row.get('book_verification') != '已核验' or row.get('pets2025_status') != '待核实':
        errors.append({'kind': 'status_refused', 'entry_id': entry_id})
        return False
    if row.get('library_class') not in {'主学习', '扩展', '暂缓'}:
        errors.append({'kind': 'library_class', 'entry_id': entry_id})
        return False
    priority = row.get('learning_priority') or ''
    if priority and priority not in {'P1', 'P2', '未分配'}:
        errors.append({'kind': 'priority', 'entry_id': entry_id})
        return False
    return True


def plan_from_rows(
    formal_rows,
    existing_rows,
    *,
    pending_ids=(),
    deferred_ids=(),
    selected_ids=None,
    formal_sha256='',
    official=False,
):
    errors = []
    seen = set()
    words = set()
    casefold = {}
    max_rich = 0
    for row in formal_rows:
        if not _validate_row(row, errors):
            continue
        if row['entry_id'] in seen or row['word'].strip() in words:
            errors.append({'kind': 'duplicate_identity', 'entry_id': row['entry_id'], 'word': row['word']})
        seen.add(row['entry_id'])
        words.add(row['word'].strip())
        casefold.setdefault(row['word'].casefold(), []).append(row['entry_id'])
        for _field, prop, kind in CONTENT:
            if kind != 'select':
                max_rich = max(max_rich, len(row.get(_field, '') or ''))
    existing = {}
    for row in existing_rows:
        entry_id = row.get('entry_id', '')
        if entry_id in existing:
            errors.append({'kind': 'duplicate_existing', 'entry_id': entry_id})
        elif _validate_row(row, errors):
            existing[entry_id] = row
    pending = set(pending_ids)
    deferred = set(deferred_ids)
    if pending & seen or deferred & seen or pending & deferred:
        errors.append({'kind': 'isolated_words_mixed'})
    if selected_ids is not None:
        selected = set(selected_ids)
        retained = seen - selected
        if len(retained) != 1 or pending & selected or deferred & selected:
            errors.append({'kind': 'selected_boundary'})
        elif existing and next(iter(retained)) not in existing:
            errors.append({'kind': 'retained_word_missing'})
    states = {}
    payloads = {}
    conflicts = []
    for row in formal_rows:
        entry_id = row.get('entry_id', '')
        if entry_id not in seen:
            continue
        payload = create_payload(row)
        payloads[entry_id] = payload
        current = existing.get(entry_id)
        if current is None:
            states[entry_id] = 'planned_create'
            continue
        fields = differing_fields(content_values(row), content_values(current), CONTENT_PROPERTIES)
        if fields:
            states[entry_id] = 'conflict'
            conflicts.append({'entry_id': entry_id, 'word': row['word'], 'fields': fields})
        else:
            states[entry_id] = 'skipped_existing'
    create_ids = [row['entry_id'] for row in formal_rows if states.get(row['entry_id']) == 'planned_create']
    counts = {
        'formal': len([row for row in formal_rows if row.get('entry_id') in states]),
        'unchanged': sum(state == 'skipped_existing' for state in states.values()),
        'create': len(create_ids),
        'update': 0,
        'conflict': len(conflicts),
        'pending': len(pending),
        'deferred': len(deferred),
    }
    if official and (
        counts['formal'] != EXPECTED['formal']
        or counts['unchanged'] != EXPECTED['unchanged']
        or counts['create'] != EXPECTED['create']
        or counts['pending'] != EXPECTED['pending']
        or counts['deferred'] != EXPECTED['deferred']
        or formal_sha256 != FORMAL_SHA
    ):
        errors.append({'kind': 'official_counts', 'counts': counts, 'formal_sha256': formal_sha256})
    return Plan(
        rows=list(formal_rows),
        states=states,
        payloads=payloads,
        conflicts=conflicts,
        errors=errors,
        casefold_collisions=[ids for ids in casefold.values() if len(ids) > 1],
        counts=counts,
        trial_ids=create_ids[:BATCH_SIZE],
        create_ids_sha256=hashlib.sha256('\n'.join(create_ids).encode()).hexdigest(),
        formal_sha256=formal_sha256,
        official=official,
        max_rich_text=max_rich,
    )


def load_official_plan(root=ROOT):
    public = root / 'docs' / 'p5a' / 'public'
    formal_path = public / 'formal_learning_vocabulary.csv'
    formal_sha = sha256_file(formal_path)
    formal = read_csv(formal_path)
    if list(formal[0]) != list(CONTENT_FIELDS):
        raise PlanError('formal columns differ from the 29 content fields')
    reviewed = read_csv(root / 'assets' / 'vocabulary' / 'reviewed500.csv')
    pending = read_csv(public / 'manual_review.csv')
    deferred = read_csv(public / 'deferred_vocabulary.csv')
    selected = read_csv(public / 'selected_vocabulary.csv')
    return plan_from_rows(
        formal,
        reviewed,
        pending_ids=[row['entry_id'] for row in pending],
        deferred_ids=[row['entry_id'] for row in deferred],
        selected_ids=[row['entry_id'] for row in selected],
        formal_sha256=formal_sha,
        official=True,
    )


def classify_pages(payload, pages, *, require_audit):
    if any(page.archived for page in pages):
        return 'conflict', ['archived']
    if not pages:
        return 'absent', []
    if len(pages) != 1:
        return 'conflict', ['duplicate_pages']
    names = list(CONTENT_PROPERTIES)
    if require_audit:
        names.extend(CREATE_AUDIT)
    fields = differing_fields(payload, pages[0].values, names)
    if fields:
        return 'conflict', fields
    return 'match', []


class ImportSession:
    """Create-only importer. A lost response is never treated as success."""

    def __init__(self, plan, transport, checkpoint, *, phase, batch_size=BATCH_SIZE, spacing_seconds=SPACING_SECONDS, sleeper=time.sleep, max_creates=None, allowed_create_ids=None):
        if phase not in ('trial10', 'full', 'simulation'):
            raise PlanError('phase refused')
        self.plan = plan
        self.transport = transport
        self.checkpoint = pathlib.Path(checkpoint)
        self.audit_path = self.checkpoint.with_suffix('.audit.jsonl')
        self.phase = phase
        self.batch_size = batch_size
        self.max_creates = max_creates
        self.allowed_create_ids = None if allowed_create_ids is None else tuple(allowed_create_ids)
        self.spacing_seconds = spacing_seconds
        self.sleeper = sleeper
        self.records = {}
        self.stopped = None
        self.batches = []
        self.attempted = set()
        self._lock_fd = None
        self._lock_path = None
        assert_checkpoint_path(self.checkpoint)
        self._load()

    def _load(self):
        saved = {}
        meta = {}
        if self.checkpoint.exists():
            meta = json.loads(self.checkpoint.read_text(encoding='utf-8'))
            if meta.get('formal_sha256') != self.plan.formal_sha256:
                raise PlanError('checkpoint belongs to another formal list')
            saved = meta.get('records') or {}
            self.batches = list(meta.get('batches') or [])
        for row in self.plan.rows:
            entry_id = row['entry_id']
            initial = self.plan.states.get(entry_id)
            if initial is None:
                continue
            payload = self.plan.payloads[entry_id]
            digest = content_sha(payload)
            record = Record(entry_id, row['word'], initial, digest)
            previous = saved.get(entry_id)
            if previous:
                if previous.get('content_sha256') != digest or previous.get('word') != row['word']:
                    raise PlanError('checkpoint content no longer matches the formal list')
                state = previous.get('state')
                allowed = {
                    'skipped_existing': {'skipped_existing', 'verified'},
                    'planned_create': {'planned_create', 'awaiting_result', 'created_unverified', 'pending_reconciliation', 'verified', 'conflict', 'rejected'},
                    'conflict': {'conflict'},
                }
                if state not in allowed[initial]:
                    raise PlanError('checkpoint state refused')
                record.state = state
                record.page_id = previous.get('page_id') or ''
                record.reason = previous.get('reason') or ''
                record.batch_index = previous.get('batch_index', -1)
                record.differing_fields = list(previous.get('differing_fields') or [])
            self.records[entry_id] = record
        self.trial_ids = list(meta.get('trial_ids') or self.plan.trial_ids)
        if self.plan.trial_ids and self.trial_ids != list(self.plan.trial_ids):
            raise PlanError('checkpoint trial ids do not match the formal order')
        self._flush()

    def _flush(self):
        self.checkpoint.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            'version': 1,
            'phase': self.phase,
            'formal_sha256': self.plan.formal_sha256,
            'create_ids_sha256': self.plan.create_ids_sha256,
            'trial_ids': self.trial_ids,
            'updated_at': now(),
            'stopped': self.stopped,
            'content_writes_confirmed': sum(
                1 for record in self.records.values()
                if record.state == 'verified' and self.plan.states.get(record.entry_id) == 'planned_create'
            ),
            'records': {
                record.entry_id: {
                    'word': record.word,
                    'state': record.state,
                    'content_sha256': record.content_sha256,
                    'page_id': record.page_id,
                    'reason': record.reason,
                    'batch_index': record.batch_index,
                    'differing_fields': record.differing_fields,
                }
                for record in self.records.values()
            },
            'batches': self.batches,
        }
        temporary = self.checkpoint.with_suffix('.tmp')
        text = json.dumps(payload, ensure_ascii=False, indent=2) + '\n'
        for attempt in range(6):
            try:
                with temporary.open('w', encoding='utf-8', newline='\n') as handle:
                    handle.write(text)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary, self.checkpoint)
                return
            except PermissionError:
                if attempt == 5:
                    raise
                time.sleep(0.25 * (2 ** attempt))

    def _audit(self, entry_id, previous, state, reason):
        event = {
            'ts': now(),
            'local_request_id': str(uuid.uuid4()),
            'entry_id': entry_id,
            'from': previous,
            'to': state,
            'reason': reason,
        }
        self.audit_path.parent.mkdir(parents=True, exist_ok=True)
        with self.audit_path.open('a', encoding='utf-8', newline='\n') as handle:
            handle.write(json.dumps(event, ensure_ascii=False) + '\n')
            handle.flush()
            os.fsync(handle.fileno())

    def _set(self, entry_id, state, reason, page_id=None, fields=None):
        record = self.records[entry_id]
        previous = record.state
        record.state = state
        record.reason = reason
        if page_id:
            record.page_id = page_id
        if fields is not None:
            record.differing_fields = list(fields)
        self._audit(entry_id, previous, state, reason)
        self._flush()

    def stop(self, reason):
        self.stopped = reason
        self._flush()

    def _pace(self):
        if self.spacing_seconds > 0:
            self.sleeper(self.spacing_seconds)

    def _query(self, entry_ids):
        for attempt in range(6):
            try:
                self._pace()
                return self.transport.query(entry_ids)
            except QueryFailed:
                if attempt == 5:
                    return None
                self.sleeper(min(2 ** attempt, 16))
        return None

    def _create_cap(self):
        if self.phase == 'trial10':
            return BATCH_SIZE
        if self.max_creates is not None:
            return self.max_creates
        if self.phase == 'full':
            return EXPECTED['create']
        return sum(state == 'planned_create' for state in self.plan.states.values())

    def _queue(self):
        allowed = set(self.trial_ids) if self.phase == 'trial10' else None
        return [
            row['entry_id']
            for row in self.plan.rows
            if self.records.get(row['entry_id'])
            and self.records[row['entry_id']].state == 'planned_create'
            and (self.allowed_create_ids is None or row['entry_id'] in self.allowed_create_ids)
            and (allowed is None or row['entry_id'] in allowed)
        ]

    def _trial_verified(self):
        return all(self.records[entry_id].state == 'verified' for entry_id in self.trial_ids)

    def _recover_uncertain(self):
        for entry_id, record in list(self.records.items()):
            if entry_id in ISOLATED_PENDING_IDS:
                continue
            if record.state not in UNCERTAIN:
                continue
            self._reconcile(entry_id)
            if self.stopped == 'pending_reconciliation':
                self.stopped = None
                continue
            if self.stopped:
                return
        self._flush()

    def _reconcile(self, entry_id):
        found = self._query([entry_id])
        if found is None:
            self._set(entry_id, 'pending_reconciliation', 'reconcile_query_failed')
            self.stop('pending_reconciliation')
            return False
        kind, fields = classify_pages(self.plan.payloads[entry_id], found, require_audit=True)
        if kind == 'match':
            self._set(entry_id, 'verified', 'reconciled', page_id=found[0].page_id)
            return True
        if kind == 'absent':
            for delay in (2, 4, 8, 8):
                self.sleeper(delay)
                found = self._query([entry_id])
                if found is None:
                    self._set(entry_id, 'pending_reconciliation', 'reconcile_query_failed')
                    self.stop('pending_reconciliation')
                    return False
                kind, fields = classify_pages(self.plan.payloads[entry_id], found, require_audit=True)
                if kind == 'match':
                    self._set(entry_id, 'verified', 'reconciled', page_id=found[0].page_id)
                    return True
                if kind != 'absent':
                    self._set(entry_id, 'conflict', 'content_or_duplicate', fields=fields)
                    self.stop('conflict')
                    return False
            self._set(entry_id, 'pending_reconciliation', 'not_found_after_uncertain_result', fields=[])
            self.stop('pending_reconciliation')
            return False
        self._set(entry_id, 'conflict', 'content_or_duplicate', fields=fields)
        self.stop('conflict')
        return False

    def _import_one(self, entry_id, batch_index):
        record = self.records[entry_id]
        record.batch_index = batch_index
        if record.state in UNCERTAIN:
            if entry_id in ISOLATED_PENDING_IDS:
                self.stop('isolated_pending')
                return False
            return self._reconcile(entry_id)
        if self.allowed_create_ids is not None and entry_id not in self.allowed_create_ids:
            self.stop('outside_authorization')
            return False
        found = self._query([entry_id])
        if found is None:
            self.stop('query_failed')
            return False
        kind, fields = classify_pages(self.plan.payloads[entry_id], found, require_audit=True)
        if kind == 'match':
            self._set(entry_id, 'verified', 'already_present', page_id=found[0].page_id)
            return True
        if kind == 'conflict':
            self._set(entry_id, 'conflict', 'content_or_duplicate', fields=fields)
            self.stop('conflict')
            return False
        attempts = 0
        while True:
            if entry_id not in self.attempted and len(self.attempted) >= self._create_cap():
                self.stop('create_cap')
                return False
            self.attempted.add(entry_id)
            self._set(entry_id, 'awaiting_result', 'request_not_confirmed')
            try:
                self._pace()
                page_id = self.transport.create(entry_id, self.plan.payloads[entry_id])
            except RateLimited as error:
                attempts += 1
                confirmed = self._query([entry_id])
                if confirmed is None:
                    self._set(entry_id, 'pending_reconciliation', 'rate_limit_query_failed')
                    self.stop('pending_reconciliation')
                    return False
                confirmed_kind, confirmed_fields = classify_pages(self.plan.payloads[entry_id], confirmed, require_audit=True)
                if confirmed_kind == 'match':
                    self._set(entry_id, 'verified', 'present_after_rate_limit', page_id=confirmed[0].page_id)
                    return True
                if confirmed_kind == 'conflict':
                    self._set(entry_id, 'conflict', 'content_or_duplicate', fields=confirmed_fields)
                    self.stop('conflict')
                    return False
                retry_after = error.retry_after
                if attempts < MAX_RATE_ATTEMPTS and isinstance(retry_after, int) and 0 <= retry_after <= MAX_RETRY_AFTER:
                    self._set(entry_id, 'planned_create', 'rate_limited_will_retry')
                    self.sleeper(retry_after)
                    continue
                self._set(entry_id, 'planned_create', 'rate_limited_stopped')
                self.stop('rate_limited')
                return False
            except UncertainResult as error:
                self._set(entry_id, 'pending_reconciliation', error.kind)
                return self._reconcile(entry_id)
            except DefinitiveReject as error:
                confirmed = self._query([entry_id])
                if confirmed is None:
                    self._set(entry_id, 'pending_reconciliation', 'reject_query_failed')
                    self.stop('pending_reconciliation')
                    return False
                confirmed_kind, confirmed_fields = classify_pages(self.plan.payloads[entry_id], confirmed, require_audit=True)
                if confirmed_kind == 'match':
                    self._set(entry_id, 'verified', 'present_after_reject', page_id=confirmed[0].page_id)
                    return True
                if confirmed_kind == 'conflict':
                    self._set(entry_id, 'conflict', 'content_or_duplicate', fields=confirmed_fields)
                    self.stop('conflict')
                    return False
                self._set(entry_id, 'rejected', f'http_{error.status}')
                self.stop('rejected')
                return False
            else:
                if not page_id:
                    self._set(entry_id, 'pending_reconciliation', 'lost_response')
                    return self._reconcile(entry_id)
                self._set(entry_id, 'created_unverified', 'response_received_not_verified', page_id=page_id)
                return self._reconcile(entry_id)

    def _verify_batch(self, entry_ids):
        found = self._query(entry_ids)
        if found is None:
            self.stop('batch_query_failed')
            return False
        grouped = {}
        for page in found:
            grouped.setdefault(page.entry_id, []).append(page)
        for entry_id in entry_ids:
            kind, fields = classify_pages(self.plan.payloads[entry_id], grouped.get(entry_id, []), require_audit=True)
            if kind != 'match' or self.records[entry_id].state != 'verified':
                self._set(entry_id, 'conflict' if kind == 'conflict' else 'pending_reconciliation', 'batch_verification_failed', fields=fields)
                self.stop('batch_verification_failed')
                return False
        return True

    def reconcile_all(self):
        ids = [row['entry_id'] for row in self.plan.rows if row['entry_id'] in self.records]
        grouped = {}
        for offset in range(0, len(ids), QUERY_GROUP):
            chunk = ids[offset:offset + QUERY_GROUP]
            found = self._query(chunk)
            if found is None:
                self.stop('final_query_failed')
                return False
            for page in found:
                grouped.setdefault(page.entry_id, []).append(page)
        for entry_id in ids:
            record = self.records[entry_id]
            found = grouped.get(entry_id, [])
            if record.state == 'planned_create':
                if found:
                    self._set(entry_id, 'conflict', 'final_reconciliation_failed', fields=['unexpected_page'])
                    self.stop('final_reconciliation_failed')
                    return False
                continue
            if record.state not in ('verified', 'skipped_existing'):
                self.stop('final_reconciliation_failed')
                return False
            require_audit = self.plan.states[entry_id] == 'planned_create'
            kind, fields = classify_pages(self.plan.payloads[entry_id], found, require_audit=require_audit)
            if kind != 'match':
                state = 'conflict' if kind == 'conflict' else 'pending_reconciliation'
                self._set(entry_id, state, 'final_reconciliation_failed', fields=fields)
                self.stop('final_reconciliation_failed')
                return False
        try:
            self._pace()
            everyone = self.transport.query_all()
        except QueryFailed:
            self.stop('final_query_failed')
            return False
        isolated, blank_errors = classify_blank_pages(everyone)
        if blank_errors:
            self.stop('blank_page_refused')
            return False
        isolated_ids = {id(page) for page in isolated}
        present = [entry_id for entry_id, record in self.records.items() if record.state in ('verified', 'skipped_existing')]
        actual = [page.entry_id for page in everyone if id(page) not in isolated_ids]
        archived = any(page.archived for page in everyone if id(page) not in isolated_ids)
        if archived or sorted(actual) != sorted(present):
            self.stop('final_reconciliation_failed')
            return False
        return True

    def _acquire_writer_lock(self):
        import msvcrt
        path = self.checkpoint.with_suffix('.writer.lock')
        fd = os.open(str(path), os.O_CREAT | os.O_RDWR)
        try:
            if os.path.getsize(path) < 1:
                os.write(fd, b'1')
            os.lseek(fd, 0, os.SEEK_SET)
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        except OSError:
            os.close(fd)
            return False
        self._lock_fd = fd
        self._lock_path = path
        return True

    def _release_writer_lock(self):
        if self._lock_fd is None:
            return
        import msvcrt
        try:
            os.lseek(self._lock_fd, 0, os.SEEK_SET)
            msvcrt.locking(self._lock_fd, msvcrt.LK_UNLCK, 1)
        finally:
            os.close(self._lock_fd)
            self._lock_fd = None

    def run(self, *, limit_batches=None):
        if not self._acquire_writer_lock():
            self.stop('writer_already_running')
            return self.result()
        try:
            return self._run_locked(limit_batches=limit_batches)
        finally:
            self._release_writer_lock()

    def _run_locked(self, *, limit_batches=None):
        if self.plan.blocked:
            self.stop('conflict' if self.plan.conflicts else 'plan_error')
            return self.result()
        if self.phase == 'full' and not self._trial_verified():
            self.stop('trial_not_verified')
            return self.result()
        for entry_id in ISOLATED_PENDING_IDS:
            record = self.records.get(entry_id)
            if record and record.state == 'planned_create':
                self.stop('isolated_pending')
                return self.result()
        if self.allowed_create_ids is not None:
            allowed = set(self.allowed_create_ids)
            if len(allowed) != len(self.allowed_create_ids) or allowed & set(ISOLATED_PENDING_IDS):
                self.stop('outside_authorization')
                return self.result()
            resumable = {'planned_create', 'verified', 'awaiting_result', 'created_unverified', 'pending_reconciliation'}
            planned = {entry_id for entry_id, record in self.records.items() if record.state == 'planned_create'}
            if planned - allowed or not allowed <= set(self.records):
                self.stop('resume_whitelist_mismatch')
                return self.result()
            if any(self.records[entry_id].state not in resumable for entry_id in allowed):
                self.stop('resume_whitelist_mismatch')
                return self.result()
        self._recover_uncertain()
        if self.stopped:
            return self.result()
        completed = 0
        while self._queue():
            if limit_batches is not None and completed >= limit_batches:
                self.stop('operator_stop')
                break
            chunk = self._queue()[:self.batch_size]
            for entry_id in chunk:
                if entry_id in ISOLATED_PENDING_IDS:
                    self.stop('isolated_pending')
                    return self.result()
                if not self._import_one(entry_id, len(self.batches)):
                    return self.result()
            if not self._verify_batch(chunk):
                return self.result()
            self.batches.append({'index': len(self.batches), 'ids': chunk, 'verified': True})
            self._flush()
            completed += 1
        if not self.stopped and not self._queue():
            self.reconcile_all()
        return self.result()

    def result(self):
        counts = {}
        for record in self.records.values():
            counts[record.state] = counts.get(record.state, 0) + 1
        return {
            'ok': self.stopped is None and not self._queue(),
            'stopped': self.stopped,
            'states': counts,
            'batches': [len(batch['ids']) for batch in self.batches],
            'attempted_creates': len(self.attempted),
            'phase': self.phase,
        }


def assert_checkpoint_path(path):
    resolved = pathlib.Path(path).resolve()
    if resolved.suffix.lower() in {'.sqlite', '.sqlite3', '.db'}:
        raise PlanError('checkpoint path refused')
    lowered = str(resolved).lower()
    if 'appdata' in lowered and 'english learning' in lowered:
        raise PlanError('checkpoint path refused')


def remaining_create_ids(plan):
    protected = set(plan.trial_ids)
    remaining = [
        row['entry_id'] for row in plan.rows
        if plan.states.get(row['entry_id']) == 'planned_create' and row['entry_id'] not in protected
    ]
    if len(remaining) != REMAINING_CREATE or len(set(remaining)) != len(remaining):
        raise PlanError('remaining count refused')
    if protected & set(remaining):
        raise PlanError('trial ids overlap remaining')
    return remaining


def remaining_sha(entry_ids):
    return hashlib.sha256(('\n'.join(entry_ids) + '\n').encode('utf-8')).hexdigest()


def authorize_write(*, phase, statement, formal_sha256, create_ids_sha256, entry_ids, expected_create_sha, expected_trial_ids, environ, remaining_ids=None, expected_remaining_sha=None):
    if statement != WRITE_STATEMENT or formal_sha256 != FORMAL_SHA:
        raise PlanError('write authorization file refused')
    if create_ids_sha256 != expected_create_sha:
        raise PlanError('create queue sha refused')
    if phase == 'trial10':
        if environ.get(WRITE_ENV) != WRITE_ENV_VALUE:
            raise PlanError('write authorization env refused')
        if list(entry_ids) != list(expected_trial_ids):
            raise PlanError('trial ids refused')
        return True
    if phase == 'resume4277':
        if environ.get(WRITE_RESUME_ENV) != WRITE_RESUME_ENV_VALUE:
            raise PlanError('write authorization env refused')
        if environ.get(WRITE_ENV) == WRITE_ENV_VALUE or environ.get(WRITE_FULL_ENV) == WRITE_FULL_ENV_VALUE:
            raise PlanError('another authorization cannot authorize the resume')
        if remaining_ids is None or list(entry_ids) != list(remaining_ids):
            raise PlanError('resume ids refused')
        if len(remaining_ids) != RESUME_CREATE or len(set(remaining_ids)) != RESUME_CREATE:
            raise PlanError('resume count refused')
        if remaining_sha(remaining_ids) != expected_remaining_sha:
            raise PlanError('resume sha refused')
        if set(remaining_ids) & set(ISOLATED_PENDING_IDS) or set(remaining_ids) & set(expected_trial_ids):
            raise PlanError('resume ids overlap a protected record')
        return True
    if phase != 'full':
        raise PlanError('phase refused')
    if environ.get(WRITE_FULL_ENV) != WRITE_FULL_ENV_VALUE:
        raise PlanError('write authorization env refused')
    if environ.get(WRITE_ENV) == WRITE_ENV_VALUE and environ.get(WRITE_FULL_ENV) != WRITE_FULL_ENV_VALUE:
        raise PlanError('trial authorization cannot authorize the remaining import')
    if remaining_ids is None or list(entry_ids) != list(remaining_ids):
        raise PlanError('remaining ids refused')
    if remaining_sha(remaining_ids) != expected_remaining_sha:
        raise PlanError('remaining sha refused')
    if set(expected_trial_ids) & set(remaining_ids):
        raise PlanError('trial ids overlap remaining')
    return True


def interpret_http(status, retry_after, body, *, expect):
    if status == 429:
        raise RateLimited(retry_after if isinstance(retry_after, int) else None)
    if expect == 'page':
        if status == 529:
            raise UncertainResult('overloaded')
        if status is None or status >= 500:
            raise UncertainResult('server_error' if status else 'lost_response')
        if 200 <= status < 300:
            if not isinstance(body, dict) or body.get('object') != 'page' or not body.get('id'):
                raise UncertainResult('lost_response')
            return body
        raise DefinitiveReject(status)
    if status != 200 or not isinstance(body, dict):
        raise QueryFailed()
    return body


class ReadOnlyNotion:
    """Official vocabulary read client. Create, update, and delete are refused."""

    def __init__(self, token, data_source_id, sleeper=time.sleep, timeout=20):
        if normalize_id(data_source_id) != normalize_id(FORMAL_SOURCE):
            raise PlanError('data source refused')
        self._token = token
        self.data_source_id = dashed_id(data_source_id)
        self.sleeper = sleeper
        self.timeout = timeout
        self._opener = urllib.request.build_opener(_RefuseRedirect())

    def create(self, entry_id, properties):
        raise PlanError('read-only client cannot create pages')

    def schema(self):
        return self._request('schema')

    def query(self, entry_ids):
        if len(entry_ids) > QUERY_GROUP:
            raise PlanError('query group refused')
        body = {
            'page_size': 100,
            'filter': {'or': [
                {'property': '词条ID', 'rich_text': {'equals': entry_id}}
                for entry_id in entry_ids
            ]},
        }
        payload = self._request('query', body)
        return _pages_from_query(payload, self.data_source_id)

    def query_all(self):
        pages = []
        cursor = None
        for index in range(80):
            if index:
                self.sleeper(SPACING_SECONDS)
            body = {'page_size': 100}
            if cursor:
                body['start_cursor'] = cursor
            payload = self._request('query_all', body)
            pages.extend(_pages_from_query(payload, self.data_source_id))
            if not payload.get('has_more'):
                return pages
            cursor = payload.get('next_cursor')
            if not cursor:
                raise QueryFailed()
        raise QueryFailed()

    def _request(self, kind, body=None):
        allowed_request('read', kind)
        method, path = _request_target(kind, self.data_source_id)
        for attempt in range(6):
            try:
                return _http_json(self._opener, method, path, body, self._token, self.timeout, expect='json')
            except RateLimited as error:
                if attempt + 1 >= 6 or not isinstance(error.retry_after, int) or not 0 <= error.retry_after <= 60:
                    raise QueryFailed() from None
                self.sleeper(error.retry_after)


class LiveWriter:
    """Create-only client. It is constructed only by open_live_writer."""

    def __init__(self, token, data_source_id, sleeper=time.sleep, timeout=20):
        if normalize_id(data_source_id) != normalize_id(FORMAL_SOURCE):
            raise PlanError('data source refused')
        self._token = token
        self.data_source_id = dashed_id(data_source_id)
        self.sleeper = sleeper
        self.timeout = timeout
        self._opener = urllib.request.build_opener(_RefuseRedirect())

    def query(self, entry_ids):
        reader = ReadOnlyNotion(self._token, self.data_source_id, self.sleeper, self.timeout)
        return reader.query(entry_ids)

    def query_all(self):
        reader = ReadOnlyNotion(self._token, self.data_source_id, self.sleeper, self.timeout)
        return reader.query_all()

    def create(self, entry_id, properties):
        allowed_request('write', 'create')
        if properties.get('词条ID') != entry_id:
            raise PlanError('stable id payload refused')
        body = build_create_body(self.data_source_id, properties)
        method, path = _request_target('create', self.data_source_id)
        payload = _http_json(self._opener, method, path, body, self._token, self.timeout, expect='page')
        page = page_view(payload)
        if page.entry_id != entry_id:
            raise UncertainResult('lost_response')
        return page.page_id


class _RefuseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise UncertainResult('redirect')


def _request_target(kind, data_source_id):
    source = dashed_id(data_source_id)
    if kind == 'schema':
        return 'GET', f'/v1/data_sources/{source}'
    if kind in ('query', 'query_all'):
        return 'POST', f'/v1/data_sources/{source}/query'
    if kind == 'create':
        return 'POST', '/v1/pages'
    raise PlanError('request refused')


def _pages_from_query(payload, data_source_id):
    if payload.get('object') != 'list' or not isinstance(payload.get('results'), list):
        raise QueryFailed()
    pages = []
    for raw in payload['results']:
        parent = (raw.get('parent') or {}).get('data_source_id', '')
        if normalize_id(parent) != normalize_id(data_source_id):
            raise QueryFailed()
        pages.append(page_view(raw))
    return pages


def _http_json(opener, method, path, body, token, timeout, *, expect):
    request = urllib.request.Request(
        'https://api.notion.com' + path,
        data=None if body is None else json.dumps(body, ensure_ascii=False).encode(),
        headers={
            'Authorization': 'Bearer ' + token,
            'Notion-Version': API_VERSION,
            'Content-Type': 'application/json',
        },
        method=method,
    )
    try:
        with opener.open(request, timeout=timeout) as response:
            raw = _bounded(response)
            status = response.status
            retry_after = _retry_after(response.headers)
    except UncertainResult as error:
        if expect == 'page':
            raise
        raise QueryFailed() from error
    except urllib.error.HTTPError as error:
        try:
            raw = _bounded(error)
        except UncertainResult as uncertain:
            if expect == 'page':
                raise
            raise QueryFailed() from uncertain
        status = error.code
        retry_after = _retry_after(error.headers)
    except (TimeoutError, urllib.error.URLError, OSError):
        if expect == 'page':
            raise UncertainResult('connection') from None
        raise QueryFailed() from None
    try:
        parsed = json.loads(raw.decode('utf-8')) if raw else None
    except (UnicodeError, json.JSONDecodeError):
        if expect == 'page':
            raise UncertainResult('lost_response') from None
        raise QueryFailed() from None
    return interpret_http(status, retry_after, parsed, expect=expect)


def _bounded(response):
    chunks = []
    total = 0
    while True:
        chunk = response.read(64 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_RESPONSE_BYTES:
            raise UncertainResult('lost_response')
        chunks.append(chunk)
    return b''.join(chunks)


def _retry_after(headers):
    value = headers.get('Retry-After') if headers else None
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def read_windows_credential(target):
    if target not in (READ_ONLY_TARGET, WRITE_TARGET):
        raise PlanError('credential target refused')
    import ctypes as C
    from ctypes import wintypes as W

    class Credential(C.Structure):
        _fields_ = [
            ('Flags', W.DWORD), ('Type', W.DWORD), ('TargetName', W.LPWSTR),
            ('Comment', W.LPWSTR), ('LastWritten', W.FILETIME),
            ('CredentialBlobSize', W.DWORD), ('CredentialBlob', C.POINTER(C.c_ubyte)),
            ('Persist', W.DWORD), ('AttributeCount', W.DWORD), ('Attributes', C.c_void_p),
            ('TargetAlias', W.LPWSTR), ('UserName', W.LPWSTR),
        ]

    api = C.WinDLL('Advapi32.dll', use_last_error=True)
    pointer = C.POINTER(Credential)()
    api.CredReadW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, C.POINTER(C.POINTER(Credential))]
    api.CredReadW.restype = W.BOOL
    api.CredFree.argtypes = [C.c_void_p]
    if not api.CredReadW(target, 1, 0, C.byref(pointer)):
        raise PlanError('credential unavailable')
    try:
        blob = C.string_at(pointer.contents.CredentialBlob, pointer.contents.CredentialBlobSize)
        account = json.loads(blob.decode('utf-8'))
    finally:
        C.memset(pointer.contents.CredentialBlob, 0, pointer.contents.CredentialBlobSize)
        api.CredFree(pointer)
    token = account.get('token') or ''
    source = account.get('data_source_id') or ''
    if not token or normalize_id(source) != normalize_id(FORMAL_SOURCE):
        raise PlanError('credential data source refused')
    return token, source


def open_live_writer(*, phase, statement, formal_sha256, create_ids_sha256, entry_ids, expected_create_sha, expected_trial_ids, credential_target, environ=None, credential_reader=read_windows_credential, remaining_ids=None, expected_remaining_sha=None):
    if credential_target != WRITE_TARGET:
        raise PlanError('writer credential target refused')
    authorize_write(
        phase=phase,
        statement=statement,
        formal_sha256=formal_sha256,
        create_ids_sha256=create_ids_sha256,
        entry_ids=entry_ids,
        expected_create_sha=expected_create_sha,
        expected_trial_ids=expected_trial_ids,
        environ=os.environ if environ is None else environ,
        remaining_ids=remaining_ids,
        expected_remaining_sha=expected_remaining_sha,
    )
    token, source = credential_reader(credential_target)
    return LiveWriter(token, source)


def open_read_only(credential_reader=read_windows_credential):
    token, source = credential_reader(READ_ONLY_TARGET)
    return ReadOnlyNotion(token, source)


def known_blank_status(page):
    """Classify one page against the single known blank page.

    isolated: the exact page still has an empty word and empty stable ID.
    changed: that same page ID no longer matches the recorded blank signature.
    other: a different page has no stable ID.
    unrelated: a normal vocabulary page.
    """
    if normalize_id(page.page_id) != normalize_id(KNOWN_BLANK_PAGE_ID):
        if not (page.entry_id or ''):
            return 'other'
        return 'unrelated'
    if page.archived or (page.entry_id or '') or (page.values.get('单词', '') or ''):
        return 'changed'
    for name in list(CONTENT_PROPERTIES) + list(PRESERVED_AUDIT) + list(CREATE_AUDIT) + sorted(FORBIDDEN):
        expected = KNOWN_BLANK_CLASS if name == '学习词库分类' else ''
        if (page.values.get(name, '') or '') != expected:
            return 'changed'
    return 'isolated'


def classify_blank_pages(pages):
    """Allow only the one recorded blank page. Any other blank or change fails."""
    errors = []
    isolated = []
    for page in pages:
        status = known_blank_status(page)
        if status == 'unrelated':
            continue
        if status == 'isolated':
            isolated.append(page)
        elif status == 'changed':
            errors.append({'kind': 'blank_page_changed', 'page_id': page.page_id})
        else:
            errors.append({'kind': 'unexpected_blank_page', 'page_id': page.page_id})
    if len(isolated) > 1:
        errors.append({'kind': 'unexpected_blank_page', 'count': len(isolated)})
    if errors:
        return [], errors
    return isolated, []


def compare_live(plan, pages, schema=None):
    if schema is not None:
        validate_schema(schema, FORMAL_SOURCE)
    errors = []
    grouped = {}
    for page in pages:
        grouped.setdefault(page.entry_id, []).append(page)
    if len(pages) != plan.counts['unchanged']:
        errors.append({'kind': 'page_count', 'pages': len(pages), 'expected': plan.counts['unchanged']})
    for entry_id, state in plan.states.items():
        found = grouped.get(entry_id, [])
        if state == 'planned_create':
            if found:
                errors.append({'kind': 'unexpected_page', 'entry_id': entry_id})
            continue
        if state != 'skipped_existing':
            errors.append({'kind': 'unresolved_plan', 'entry_id': entry_id, 'state': state})
            continue
        kind, fields = classify_pages(plan.payloads[entry_id], found, require_audit=False)
        if kind != 'match':
            errors.append({'kind': kind, 'entry_id': entry_id, 'fields': fields})
    extras = [entry_id for entry_id in grouped if entry_id not in plan.states]
    if extras:
        errors.append({'kind': 'extra_ids', 'count': len(extras)})
    preserved = {
        name: sum(1 for page in pages if page.values.get(name))
        for name in list(PRESERVED_AUDIT) + list(CREATE_AUDIT)
    }
    return {
        'ok': not errors,
        'pages': len(pages),
        'unique_ids': len(grouped),
        'errors': errors,
        'preserved_nonempty': preserved,
        'content_writes': 0,
    }


def compare_protected_library(plan, pages, schema=None):
    """Confirm the accepted 510 pages and the absence of the remaining whitelist."""
    if schema is not None:
        validate_schema(schema, FORMAL_SOURCE)
    grouped = {}
    for page in pages:
        grouped.setdefault(page.entry_id, []).append(page)
    protected = set(plan.trial_ids)
    errors = []
    matched = 0
    for entry_id, state in plan.states.items():
        found = grouped.get(entry_id, [])
        if state == 'skipped_existing' or entry_id in protected:
            kind, fields = classify_pages(
                plan.payloads[entry_id], found, require_audit=entry_id in protected,
            )
            if kind != 'match':
                errors.append({'kind': kind, 'entry_id': entry_id, 'fields': fields})
            else:
                matched += 1
            continue
        if state != 'planned_create':
            errors.append({'kind': 'unresolved_plan', 'entry_id': entry_id, 'state': state})
            continue
        if not found:
            continue
        kind, fields = classify_pages(plan.payloads[entry_id], found, require_audit=True)
        if kind != 'match':
            errors.append({'kind': kind, 'entry_id': entry_id, 'fields': fields})
        else:
            matched += 1
    isolated, blank_errors = classify_blank_pages(pages)
    errors.extend(blank_errors)
    isolated_ids = {id(page) for page in isolated}
    extras = []
    vocabulary_groups = 0
    for entry_id, found in grouped.items():
        remaining_pages = [page for page in found if id(page) not in isolated_ids]
        if not remaining_pages:
            continue
        vocabulary_groups += 1
        if entry_id not in plan.states:
            extras.append(entry_id)
    if extras:
        errors.append({'kind': 'extra_ids', 'count': len(extras)})
    protected_count = plan.counts['unchanged'] + len(plan.trial_ids)
    vocabulary_pages = len(pages) - len(isolated)
    if matched < protected_count or vocabulary_pages != matched or vocabulary_groups != matched:
        errors.append({
            'kind': 'page_count',
            'pages': len(pages),
            'vocabulary_pages': vocabulary_pages,
            'unique': vocabulary_groups,
            'matched': matched,
        })
    preserved = {
        name: sum(1 for page in pages if page.values.get(name))
        for name in list(PRESERVED_AUDIT) + list(CREATE_AUDIT)
    }
    return {
        'ok': not errors,
        'pages': len(pages),
        'unique_ids': vocabulary_groups,
        'vocabulary_pages': vocabulary_pages,
        'isolated_blank_pages': len(isolated),
        'protected': plan.counts['unchanged'] + len(plan.trial_ids),
        'remaining_present': matched - (plan.counts['unchanged'] + len(plan.trial_ids)),
        'errors': errors,
        'preserved_nonempty': preserved,
        'content_writes': 0,
    }


def dry_run_summary(plan, *, live=None):
    return {
        'phase': 'P5-C.4A',
        'version': '0.7.0+10',
        'mode': 'dry-run',
        'content_writes': 0,
        'event_uploads': 0,
        'sqlite_opened': False,
        'ready': plan.ready,
        'formal_sha256': plan.formal_sha256,
        'counts': plan.counts,
        'conflicts': plan.conflicts,
        'errors': plan.errors,
        'casefold_collision_groups': len(plan.casefold_collisions),
        'max_rich_text_length': plan.max_rich_text,
        'trial10': [
            {'entry_id': entry_id, 'word': plan.payloads[entry_id]['单词']}
            for entry_id in plan.trial_ids
        ],
        'create_ids_sha256': plan.create_ids_sha256,
        'create_property_count': 29 + len(CREATE_AUDIT),
        'create_only_audit': CREATE_AUDIT,
        'preserved_audit_not_sent': list(PRESERVED_AUDIT),
        'personal_fields_excluded': sorted(FORBIDDEN),
        'batch_size': BATCH_SIZE,
        'spacing_seconds': SPACING_SECONDS,
        'live': live,
    }
