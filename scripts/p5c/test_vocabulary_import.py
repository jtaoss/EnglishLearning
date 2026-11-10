"""Offline acceptance tests for the P5-C.4A vocabulary importer.

These tests use an in-memory Notion double. They do not create, update, or
delete real Notion pages and they do not open the personal SQLite database.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import import_vocabulary
import vocabulary_import as importer
from vocabulary_import import (
    BATCH_SIZE,
    CONTENT_FIELDS,
    CONTENT_PROPERTIES,
    CREATE_AUDIT,
    EVENT_SANDBOX_SOURCE,
    FORBIDDEN,
    FORMAL_SHA,
    FORMAL_SOURCE,
    PRESERVED_AUDIT,
    PROPERTY_TYPES,
    READ_ONLY_TARGET,
    WRITE_ENV,
    WRITE_ENV_VALUE,
    WRITE_FULL_ENV,
    WRITE_FULL_ENV_VALUE,
    WRITE_STATEMENT,
    authorize_write,
    remaining_create_ids,
    remaining_sha,
    DefinitiveReject,
    ImportSession,
    PageView,
    PlanError,
    QueryFailed,
    RateLimited,
    UncertainResult,
    build_create_body,
    compare_live,
    create_payload,
    encode_properties,
    interpret_http,
    load_official_plan,
    open_live_writer,
    plan_from_rows,
    validate_schema,
)

DB = pathlib.Path(os.environ['APPDATA']) / 'Personal' / 'English Learning' / 'english_learning_v1.sqlite3'
BEFORE = {}


def fingerprint(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    stat = path.stat()
    return {'sha256': digest.hexdigest(), 'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns}


def setUpModule():
    BEFORE.update(fingerprint(DB))


def tearDownModule():
    after = fingerprint(DB)
    if after != BEFORE:
        raise AssertionError('personal SQLite changed during importer tests')


def row(entry_id, word, **overrides):
    item = {field: '' for field in CONTENT_FIELDS}
    item.update({
        'entry_id': entry_id,
        'word': word,
        'meaning_zh': '义-' + word,
        'book_category': '高频词',
        'source_file': 'book.pdf',
        'source_id': 'src',
        'source_pdf_pages': '1',
        'source_index_pages': '2',
        'book_verification': '已核验',
        'meaning_review_status': '待个人确认',
        'pets2015_status': '已收录',
        'pets2025_status': '待核实',
        'library_class': '主学习',
        'learning_priority': 'P1',
    })
    item.update(overrides)
    return item


class MemoryNotion:
    def __init__(self):
        self.pages = {}
        self.scripts = {}
        self.create_calls = []
        self.query_error = False

    def query(self, entry_ids):
        if self.query_error:
            raise QueryFailed()
        found = []
        for entry_id in entry_ids:
            found.extend(self.pages.get(entry_id, []))
        return found

    def query_all(self):
        if self.query_error:
            raise QueryFailed()
        return [page for pages in self.pages.values() for page in pages]

    def create(self, entry_id, properties):
        self.create_calls.append(entry_id)
        script = self.scripts.get(entry_id) or []
        outcome = script.pop(0) if script else 'ok'
        if outcome in ('ok', 'lost_save'):
            page = PageView(f'mem-{len(self.create_calls)}', entry_id, dict(properties))
            self.pages.setdefault(entry_id, []).append(page)
            if outcome == 'lost_save':
                raise UncertainResult('lost_response')
            return page.page_id
        if outcome == 'lost':
            raise UncertainResult('lost_response')
        if outcome == 'overloaded':
            raise UncertainResult('overloaded')
        raise outcome


def seed(transport, item, **extra):
    values = {prop: item.get(field, '') or '' for field, prop, _kind in importer.CONTENT}
    values.update(extra)
    transport.pages[item['entry_id']] = [PageView('page-' + item['entry_id'], item['entry_id'], values)]
    return values


class ImporterTests(unittest.TestCase):
    def session(self, plan, transport, phase='simulation', batch_size=10, sleeper=None, limit_batches=None):
        folder = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        session = ImportSession(
            plan,
            transport,
            folder / 'checkpoint.json',
            phase=phase,
            batch_size=batch_size,
            spacing_seconds=0,
            sleeper=sleeper or (lambda _seconds: None),
        )
        result = session.run(limit_batches=limit_batches)
        return session, result

    def test_official_queue_keeps_existing_ids_out(self):
        plan = load_official_plan()
        self.assertTrue(plan.ready)
        self.assertEqual(plan.formal_sha256, FORMAL_SHA)
        self.assertEqual(plan.counts['create'], 4832)
        self.assertEqual(plan.counts['unchanged'], 500)
        self.assertEqual(plan.counts['update'], 0)
        self.assertEqual(plan.counts['conflict'], 0)
        self.assertEqual(plan.counts['pending'], 194)
        self.assertEqual(plan.counts['deferred'], 27)
        self.assertEqual(len(plan.trial_ids), 10)
        self.assertEqual(len(plan.casefold_collisions), 2)
        pair_states = []
        for ids in plan.casefold_collisions:
            pair_states.append(sorted((plan.payloads[entry_id]['单词'], plan.states[entry_id]) for entry_id in ids))
        self.assertEqual(pair_states, [
            [('March', 'skipped_existing'), ('march', 'skipped_existing')],
            [('May', 'skipped_existing'), ('may', 'skipped_existing')],
        ])
        created = [entry_id for entry_id, state in plan.states.items() if state == 'planned_create']
        skipped = [entry_id for entry_id, state in plan.states.items() if state == 'skipped_existing']
        self.assertEqual(len(created), 4832)
        self.assertEqual(len(set(created)), 4832)
        self.assertEqual(len(skipped), 500)
        self.assertFalse(set(created) & set(skipped))
        for entry_id in created:
            payload = plan.payloads[entry_id]
            self.assertFalse(set(payload) & FORBIDDEN)
            self.assertFalse(set(payload) & set(PRESERVED_AUDIT))
            self.assertEqual(payload['词条ID'], entry_id)
            self.assertEqual(payload['原5552台账内'], '是')
            self.assertEqual(payload['发音资源状态'], '未配置')

    def test_case_differences_do_not_merge_ids(self):
        plan = plan_from_rows(
            [row('id-1', 'Apple'), row('id-2', 'apple'), row('id-3', 'cat')],
            [row('id-3', 'cat')],
        )
        self.assertEqual(plan.states['id-1'], 'planned_create')
        self.assertEqual(plan.states['id-2'], 'planned_create')
        self.assertEqual(plan.states['id-3'], 'skipped_existing')
        self.assertEqual(len(plan.casefold_collisions), 1)
        self.assertFalse(plan.blocked)

    def test_content_conflict_stops_without_create_or_update(self):
        existing = row('id-1', 'cat', meaning_zh='旧义')
        plan = plan_from_rows([existing, row('id-2', 'dog')], [row('id-1', 'cat', meaning_zh='新义')])
        self.assertEqual(plan.states['id-1'], 'conflict')
        self.assertEqual(plan.conflicts[0]['fields'], ['中文词义'])
        transport = MemoryNotion()
        _session, result = self.session(plan, transport)
        self.assertEqual(result['stopped'], 'conflict')
        self.assertEqual(transport.create_calls, [])

    def test_rerun_resume_partial_batch_and_trial_gate(self):
        items = [row(f'id-{index}', f'word{index}') for index in range(23)]
        plan = plan_from_rows(items, [])
        transport = MemoryNotion()
        stopped, first = self.session(plan, transport, limit_batches=1)
        self.assertEqual(first['stopped'], 'operator_stop')
        self.assertEqual(first['batches'], [10])
        self.assertEqual(transport.create_calls, [item['entry_id'] for item in items[:10]])
        resumed = ImportSession(plan, transport, stopped.checkpoint, phase='simulation', batch_size=10, spacing_seconds=0, sleeper=lambda _seconds: None)
        second = resumed.run()
        self.assertTrue(second['ok'])
        self.assertEqual(second['batches'], [10, 10, 3])
        self.assertEqual(transport.create_calls, [item['entry_id'] for item in items])
        third = ImportSession(plan, transport, stopped.checkpoint, phase='simulation', batch_size=10, spacing_seconds=0, sleeper=lambda _seconds: None)
        third.run()
        self.assertEqual(transport.create_calls, [item['entry_id'] for item in items])
        audit = stopped.audit_path.read_text(encoding='utf-8')
        self.assertIn('awaiting_result', audit)
        self.assertIn('verified', audit)
        self.assertNotIn('Bearer', audit)
        self.assertNotIn('token', audit.lower())

    def test_trial_then_full_creates_each_id_once(self):
        items = [row(f'id-{index}', f'word{index}') for index in range(15)]
        plan = plan_from_rows(items, [])
        transport = MemoryNotion()
        trial, trial_result = self.session(plan, transport, phase='trial10', batch_size=4)
        self.assertTrue(trial_result['ok'])
        self.assertEqual(transport.create_calls, [item['entry_id'] for item in items[:10]])
        self.assertEqual(trial.records['id-10'].state, 'planned_create')
        full = ImportSession(plan, transport, trial.checkpoint, phase='full', batch_size=4, spacing_seconds=0, sleeper=lambda _seconds: None)
        full_result = full.run()
        self.assertTrue(full_result['ok'])
        self.assertEqual(transport.create_calls, [item['entry_id'] for item in items])
        blocked = ImportSession(plan_from_rows(items, []), MemoryNotion(), pathlib.Path(self.enterContext(tempfile.TemporaryDirectory())) / 'checkpoint.json', phase='full', batch_size=4, spacing_seconds=0, sleeper=lambda _seconds: None)
        self.assertEqual(blocked.run()['stopped'], 'trial_not_verified')
        self.assertEqual(blocked.transport.create_calls, [])

    def test_rate_limit_retries_then_stops(self):
        item = row('id-1', 'cat')
        plan = plan_from_rows([item], [])
        waits = []
        transport = MemoryNotion()
        transport.scripts['id-1'] = [RateLimited(1), 'ok']
        _session, result = self.session(plan, transport, sleeper=waits.append)
        self.assertTrue(result['ok'])
        self.assertEqual(waits, [1])
        self.assertEqual(transport.create_calls, ['id-1', 'id-1'])
        stopped_transport = MemoryNotion()
        stopped_transport.scripts['id-1'] = [RateLimited(11)]
        _stopped, stopped = self.session(plan, stopped_transport, sleeper=waits.append)
        self.assertEqual(stopped['stopped'], 'rate_limited')
        self.assertEqual(stopped_transport.create_calls, ['id-1'])
        self.assertEqual(_stopped.records['id-1'].state, 'planned_create')
        continued = ImportSession(plan, stopped_transport, _stopped.checkpoint, phase='simulation', spacing_seconds=0, sleeper=lambda _seconds: None)
        self.assertTrue(continued.run()['ok'])
        self.assertEqual(stopped_transport.create_calls, ['id-1', 'id-1'])

    def test_lost_response_reconciles_and_does_not_create_again(self):
        item = row('id-1', 'cat')
        plan = plan_from_rows([item], [])
        saved = MemoryNotion()
        saved.scripts['id-1'] = ['lost_save']
        session, result = self.session(plan, saved)
        self.assertTrue(result['ok'])
        self.assertEqual(saved.create_calls, ['id-1'])
        self.assertEqual(session.records['id-1'].state, 'verified')
        again = ImportSession(plan, saved, session.checkpoint, phase='simulation', spacing_seconds=0, sleeper=lambda _seconds: None)
        again.run()
        self.assertEqual(saved.create_calls, ['id-1'])
        missing = MemoryNotion()
        missing.scripts['id-1'] = ['lost']
        first, lost = self.session(plan, missing)
        self.assertEqual(lost['stopped'], 'pending_reconciliation')
        self.assertEqual(first.records['id-1'].state, 'pending_reconciliation')
        second = ImportSession(plan, missing, first.checkpoint, phase='simulation', spacing_seconds=0, sleeper=lambda _seconds: None)
        second_result = second.run()
        self.assertIn(second_result['stopped'], ('pending_reconciliation', 'final_reconciliation_failed'))
        self.assertEqual(second.records['id-1'].state, 'pending_reconciliation')
        self.assertEqual(missing.create_calls, ['id-1'])

    def test_existing_personal_and_audit_values_stay_untouched(self):
        kept = row('id-1', 'cat')
        added = row('id-2', 'Cat')
        plan = plan_from_rows([kept, added], [kept])
        transport = MemoryNotion()
        original = seed(transport, kept, **{'学习状态': '未测试', 'AI 筛选理由': '保留'})
        snapshot = json.dumps(original, ensure_ascii=False, sort_keys=True)
        _session, result = self.session(plan, transport)
        self.assertTrue(result['ok'])
        self.assertEqual(transport.create_calls, ['id-2'])
        self.assertEqual(json.dumps(transport.pages['id-1'][0].values, ensure_ascii=False, sort_keys=True), snapshot)
        self.assertNotIn('学习状态', transport.pages['id-2'][0].values)
        self.assertNotIn('AI 筛选理由', transport.pages['id-2'][0].values)

    def test_uncertain_checkpoint_is_not_created_again(self):
        item = row('id-1', 'cat')
        plan = plan_from_rows([item], [])
        transport = MemoryNotion()
        session, _result = self.session(plan, transport, limit_batches=0)
        session._set('id-1', 'awaiting_result', 'request_not_confirmed')
        resumed = ImportSession(plan, transport, session.checkpoint, phase='simulation', spacing_seconds=0, sleeper=lambda _seconds: None)
        result = resumed.run()
        self.assertEqual(transport.create_calls, [])
        self.assertEqual(resumed.records['id-1'].state, 'pending_reconciliation')
        self.assertIn(result['stopped'], ('pending_reconciliation', 'final_reconciliation_failed'))

    def test_query_failure_does_not_create(self):
        plan = plan_from_rows([row('id-1', 'cat')], [])
        transport = MemoryNotion()
        transport.query_error = True
        session, result = self.session(plan, transport)
        self.assertEqual(result['stopped'], 'query_failed')
        self.assertEqual(transport.create_calls, [])
        self.assertEqual(session.records['id-1'].state, 'planned_create')

    def test_request_encoding_and_authorization_gates(self):
        payload = create_payload(row('id-1', 'cat', usage_note='长' * 2001))
        encoded = encode_properties(payload)
        self.assertEqual(len(encoded['用法说明']['rich_text']), 2)
        self.assertEqual(encoded['单词']['title'][0]['text']['content'], 'cat')
        self.assertEqual(encoded['原书分类']['select']['name'], '高频词')
        with self.assertRaises(PlanError):
            encode_properties({'学习状态': '未测试'})
        body = build_create_body(FORMAL_SOURCE, payload)
        self.assertEqual(body['parent']['data_source_id'], FORMAL_SOURCE)
        self.assertNotIn('学习状态', body['properties'])
        with self.assertRaises(PlanError):
            build_create_body(EVENT_SANDBOX_SOURCE, payload)
        with self.assertRaises(PlanError):
            importer.allowed_request('read', 'create')
        with self.assertRaises(RateLimited) as limited:
            interpret_http(429, 2, {}, expect='page')
        self.assertEqual(limited.exception.retry_after, 2)
        with self.assertRaises(UncertainResult):
            interpret_http(529, 1, {}, expect='page')
        with self.assertRaises(UncertainResult):
            interpret_http(200, None, {'object': 'list'}, expect='page')
        with self.assertRaises(DefinitiveReject):
            interpret_http(400, None, {}, expect='page')
        schema = {'id': FORMAL_SOURCE, 'properties': {}}
        for name, kind in PROPERTY_TYPES.items():
            schema['properties'][name] = {'type': kind}
            if kind == 'select':
                schema['properties'][name]['select'] = {'options': [{'name': '是'}, {'name': '未配置'}, {'name': '高频词'}]}
        self.assertTrue(validate_schema(schema, FORMAL_SOURCE))
        broken = json.loads(json.dumps(schema))
        broken['properties']['发音资源状态']['select']['options'] = [{'name': '其他'}]
        with self.assertRaises(PlanError):
            validate_schema(broken, FORMAL_SOURCE)
        calls = []
        with self.assertRaises(PlanError):
            open_live_writer(
                phase='trial10',
                statement=WRITE_STATEMENT,
                formal_sha256=FORMAL_SHA,
                create_ids_sha256='sha',
                entry_ids=['id-1'],
                expected_create_sha='sha',
                expected_trial_ids=['id-1'],
                credential_target=READ_ONLY_TARGET,
                environ={WRITE_ENV: WRITE_ENV_VALUE},
                credential_reader=lambda target: calls.append(target),
            )
        self.assertEqual(calls, [])
        with self.assertRaises(PlanError):
            importer.assert_checkpoint_path(DB)

    def test_sources_do_not_reference_sqlite_and_dry_run_stays_closed(self):
        for name in ('vocabulary_import.py', 'import_vocabulary.py'):
            text = (pathlib.Path(__file__).with_name(name)).read_text(encoding='utf-8').lower()
            self.assertNotIn('import sqlite3', text)
            self.assertNotIn('sqlite3.connect', text)
            self.assertNotIn('english_learning_v1', text)
        folder = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        output = folder / 'dry-run.json'
        code = import_vocabulary.main(['--mode', 'dry-run', '--output', str(output)])
        summary = json.loads(output.read_text(encoding='utf-8'))
        self.assertEqual(code, 0)
        self.assertEqual(summary['content_writes'], 0)
        self.assertEqual(summary['event_uploads'], 0)
        self.assertFalse(summary['sqlite_opened'])
        self.assertTrue(summary['ready'])
        self.assertEqual(len(summary['trial10']), BATCH_SIZE)
        self.assertEqual(len(CONTENT_PROPERTIES), 29)
        self.assertEqual(len(PRESERVED_AUDIT) + len(CREATE_AUDIT), 9)

    def test_cli_write_without_authorization_reads_no_credential(self):
        calls = []
        folder = pathlib.Path(self.enterContext(tempfile.TemporaryDirectory()))
        (folder / 'auth.json').write_text('{}', encoding='utf-8')
        original = import_vocabulary.open_live_writer

        def wrapped(**kwargs):
            kwargs['credential_reader'] = lambda target: calls.append(target)
            return original(**kwargs)

        import_vocabulary.open_live_writer = wrapped
        try:
            code = import_vocabulary.main([
                '--mode', 'write',
                '--phase', 'trial10',
                '--authorization-file', str(folder / 'auth.json'),
                '--checkpoint', str(folder / 'checkpoint.json'),
            ])
            self.assertEqual(code, 2)
            full_code = import_vocabulary.main([
                '--mode', 'write',
                '--phase', 'full',
                '--authorization-file', str(folder / 'auth.json'),
                '--checkpoint', str(folder / 'checkpoint.json'),
            ])
        finally:
            import_vocabulary.open_live_writer = original
        self.assertEqual(full_code, 2)
        self.assertEqual(calls, [])

    def test_remaining_authorization_rejects_the_trial_env(self):
        plan = load_official_plan()
        remaining = remaining_create_ids(plan)
        digest = remaining_sha(remaining)
        self.assertEqual(len(remaining), 4822)
        self.assertEqual(len(set(plan.trial_ids) & set(remaining)), 0)
        with self.assertRaises(PlanError):
            authorize_write(
                phase='full',
                statement=WRITE_STATEMENT,
                formal_sha256=FORMAL_SHA,
                create_ids_sha256=plan.create_ids_sha256,
                entry_ids=remaining,
                expected_create_sha=plan.create_ids_sha256,
                expected_trial_ids=plan.trial_ids,
                environ={WRITE_ENV: WRITE_ENV_VALUE},
                remaining_ids=remaining,
                expected_remaining_sha=digest,
            )
        self.assertTrue(authorize_write(
            phase='full',
            statement=WRITE_STATEMENT,
            formal_sha256=FORMAL_SHA,
            create_ids_sha256=plan.create_ids_sha256,
            entry_ids=remaining,
            expected_create_sha=plan.create_ids_sha256,
            expected_trial_ids=plan.trial_ids,
            environ={WRITE_FULL_ENV: WRITE_FULL_ENV_VALUE},
            remaining_ids=remaining,
            expected_remaining_sha=digest,
        ))

    def test_live_comparison_reports_count_mismatch_without_writing(self):
        items = [row('id-1', 'cat'), row('id-2', 'dog')]
        plan = plan_from_rows(items, [items[0]])
        pages = []
        report = compare_live(plan, pages)
        self.assertFalse(report['ok'])
        self.assertEqual(report['content_writes'], 0)
        self.assertEqual(report['pages'], 0)


if __name__ == '__main__':
    unittest.main()
