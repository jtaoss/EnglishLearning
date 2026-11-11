"""Command line for the one-off vocabulary importer.

The default mode is dry-run. Write mode has to be requested explicitly and
still returns before any network write unless the separate authorization
gates pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

from vocabulary_import import (
    FORMAL_SOURCE,
    ISOLATED_PENDING_IDS,
    ImportSession,
    PlanError,
    QueryFailed,
    REMAINING_CREATE,
    RESUME_CREATE,
    SPACING_SECONDS,
    UncertainResult,
    WRITE_TARGET,
    assert_checkpoint_path,
    compare_live,
    compare_protected_library,
    dry_run_summary,
    load_official_plan,
    normalize_id,
    open_live_writer,
    open_read_only,
    remaining_create_ids,
    remaining_sha,
)

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / 'docs' / 'p5c' / 'import_dry_run.json'


def main(argv=None):
    parser = argparse.ArgumentParser(description='P5-C.4 Notion vocabulary importer')
    parser.add_argument('--mode', choices=('dry-run', 'write'), default='dry-run')
    parser.add_argument('--phase', choices=('trial10', 'full'))
    parser.add_argument('--authorization-file')
    parser.add_argument('--checkpoint')
    parser.add_argument('--output', default=str(DEFAULT_OUTPUT))
    parser.add_argument('--live-read', action='store_true')
    args = parser.parse_args(argv)
    try:
        plan = load_official_plan(ROOT)
        if args.mode == 'dry-run':
            live = _live_read(plan) if args.live_read else None
            summary = dry_run_summary(plan, live=live)
            _write_json(pathlib.Path(args.output), summary)
            print(json.dumps({
                'mode': 'dry-run',
                'ready': summary['ready'] and (live is None or live['ok']),
                'counts': summary['counts'],
                'conflicts': len(summary['conflicts']),
                'live_pages': None if live is None else live.get('pages'),
                'content_writes': 0,
            }, ensure_ascii=False))
            return 0 if summary['ready'] and (live is None or live['ok']) else 2
        return _write(args, plan)
    except PlanError as error:
        print(json.dumps({'mode': args.mode, 'ready': False, 'error': str(error), 'content_writes': 0}, ensure_ascii=False))
        return 2


def _live_read(plan):
    try:
        reader = open_read_only()
        schema = reader.schema()
        pages = reader.query_all()
        report = compare_live(plan, pages, schema)
    except (PlanError, QueryFailed, UncertainResult) as error:
        return {'ok': False, 'read_only': True, 'error': str(error) or error.__class__.__name__, 'content_writes': 0}
    report['read_only'] = True
    return report


def _write(args, plan):
    if not plan.ready or args.phase not in ('trial10', 'full') or not args.authorization_file or not args.checkpoint:
        raise PlanError('write mode refused')
    assert_checkpoint_path(args.checkpoint)
    authorization = json.loads(pathlib.Path(args.authorization_file).read_text(encoding='utf-8'))
    max_creates = None
    allowed_create_ids = None
    if args.phase == 'trial10':
        _check_trial_authorization(authorization, plan)
        writer = open_live_writer(
            phase=args.phase,
            statement=authorization.get('statement', ''),
            formal_sha256=authorization.get('formal_sha256', ''),
            create_ids_sha256=authorization.get('create_ids_sha256', ''),
            entry_ids=authorization.get('entry_ids') or [],
            expected_create_sha=plan.create_ids_sha256,
            expected_trial_ids=plan.trial_ids,
            credential_target=WRITE_TARGET,
        )
    else:
        remaining = remaining_create_ids(plan)
        if authorization.get('phase') == 'P5-C.4C.3':
            whitelist = _load_resume_whitelist(authorization, plan, remaining, args.checkpoint)
            report = _confirm_protected(plan)
            _confirm_resume_baseline(report, whitelist, args.checkpoint)
            writer = open_live_writer(
                phase='resume4277',
                statement=authorization.get('statement', ''),
                formal_sha256=authorization.get('formal_sha256', ''),
                create_ids_sha256=authorization.get('create_ids_sha256', ''),
                entry_ids=whitelist,
                expected_create_sha=plan.create_ids_sha256,
                expected_trial_ids=plan.trial_ids,
                credential_target=WRITE_TARGET,
                remaining_ids=whitelist,
                expected_remaining_sha=authorization.get('whitelist_sha256', ''),
            )
            max_creates = RESUME_CREATE
            allowed_create_ids = whitelist
        else:
            whitelist = _load_whitelist(authorization, remaining)
            _check_full_authorization(authorization, plan, whitelist)
            _confirm_protected(plan)
            writer = open_live_writer(
                phase='full',
                statement=authorization.get('statement', ''),
                formal_sha256=authorization.get('formal_sha256', ''),
                create_ids_sha256=authorization.get('create_ids_sha256', ''),
                entry_ids=whitelist,
                expected_create_sha=plan.create_ids_sha256,
                expected_trial_ids=plan.trial_ids,
                credential_target=WRITE_TARGET,
                remaining_ids=remaining,
                expected_remaining_sha=authorization.get('whitelist_sha256', ''),
            )
            max_creates = REMAINING_CREATE
            allowed_create_ids = None
    session = ImportSession(
        plan, writer, args.checkpoint, phase=args.phase,
        spacing_seconds=SPACING_SECONDS, max_creates=max_creates,
        allowed_create_ids=allowed_create_ids,
    )
    result = session.run()
    print(json.dumps({
        'mode': 'write',
        'phase': args.phase,
        'ok': result['ok'],
        'stopped': result['stopped'],
        'batches': result['batches'],
        'attempted_creates': result['attempted_creates'],
        'states': result['states'],
        'content_writes': 0 if not result['ok'] else result['attempted_creates'],
    }, ensure_ascii=False))
    return 0 if result['ok'] else 2


def _load_whitelist(authorization, remaining):
    relative = str(authorization.get('whitelist_file', ''))
    path = (ROOT / relative).resolve()
    allowed_root = (ROOT / 'private' / 'p5c').resolve()
    if allowed_root not in path.parents or path.suffix.lower() != '.txt':
        raise PlanError('whitelist path refused')
    text = path.read_text(encoding='utf-8')
    if hashlib.sha256(text.encode('utf-8')).hexdigest() != authorization.get('whitelist_sha256'):
        raise PlanError('whitelist hash refused')
    whitelist = [line for line in text.splitlines() if line]
    if whitelist != list(remaining) or remaining_sha(whitelist) != authorization.get('whitelist_sha256'):
        raise PlanError('whitelist ids refused')
    return whitelist


def _check_full_authorization(authorization, plan, whitelist):
    if authorization.get('phase') != 'P5-C.4C' or authorization.get('max_creates') != REMAINING_CREATE:
        raise PlanError('authorization phase refused')
    if any(authorization.get(name) for name in ('allow_update', 'allow_delete', 'allow_events', 'allow_sqlite', 'allow_full_import')):
        raise PlanError('authorization permission refused')
    if normalize_id(str(authorization.get('data_source_id', ''))) != normalize_id(FORMAL_SOURCE):
        raise PlanError('authorization data source refused')
    if authorization.get('formal_sha256') != plan.formal_sha256 or authorization.get('create_ids_sha256') != plan.create_ids_sha256:
        raise PlanError('authorization manifest refused')
    if len(whitelist) != REMAINING_CREATE or set(plan.trial_ids) & set(whitelist):
        raise PlanError('remaining whitelist refused')


def _confirm_protected(plan):
    try:
        reader = open_read_only()
        schema = reader.schema()
        pages = reader.query_all()
        report = compare_protected_library(plan, pages, schema)
    except (QueryFailed, UncertainResult, PlanError):
        raise PlanError('protected library check failed') from None
    if not report['ok']:
        raise PlanError('protected library drifted')
    report['present_ids'] = {page.entry_id for page in pages if page.entry_id}
    return report


def _load_resume_whitelist(authorization, plan, parent_ids, checkpoint):
    if authorization.get('max_creates') != RESUME_CREATE:
        raise PlanError('authorization phase refused')
    if any(authorization.get(name) for name in ('allow_update', 'allow_delete', 'allow_events', 'allow_sqlite', 'allow_full_import')):
        raise PlanError('authorization permission refused')
    if normalize_id(str(authorization.get('data_source_id', ''))) != normalize_id(FORMAL_SOURCE):
        raise PlanError('authorization data source refused')
    if authorization.get('formal_sha256') != plan.formal_sha256 or authorization.get('create_ids_sha256') != plan.create_ids_sha256:
        raise PlanError('authorization manifest refused')
    whitelist = _load_whitelist(authorization, _ids_from_whitelist_file(authorization))
    if len(whitelist) != RESUME_CREATE or set(whitelist) - set(parent_ids):
        raise PlanError('resume whitelist refused')
    if set(whitelist) & set(plan.trial_ids):
        raise PlanError('resume whitelist refused')
    saved = json.loads(pathlib.Path(checkpoint).read_text(encoding='utf-8'))
    if saved.get('formal_sha256') != plan.formal_sha256:
        raise PlanError('checkpoint belongs to another formal list')
    records = saved.get('records', {})
    resumable = {'planned_create', 'verified', 'awaiting_result', 'created_unverified', 'pending_reconciliation'}
    allowed = set(whitelist)
    if any(records.get(entry_id, {}).get('state') not in resumable for entry_id in whitelist):
        raise PlanError('resume whitelist state refused')
    planned_order = [
        row['entry_id'] for row in plan.rows
        if records.get(row['entry_id'], {}).get('state') == 'planned_create' and row['entry_id'] in allowed
    ]
    if len(planned_order) != len(set(planned_order)) or not set(planned_order) <= allowed:
        raise PlanError('resume whitelist does not match the unsent checkpoint ids')
    audit_path = pathlib.Path(checkpoint).with_suffix('.audit.jsonl')
    if audit_path.exists():
        sent_while_unsent = set()
        for line in audit_path.read_text(encoding='utf-8').splitlines():
            if not line.strip():
                continue
            event = json.loads(line)
            entry_id = event.get('entry_id')
            if entry_id in allowed and records.get(entry_id, {}).get('state') == 'planned_create':
                sent_while_unsent.add(entry_id)
        if sent_while_unsent:
            raise PlanError('resume whitelist includes an id that was already sent')
    return whitelist


def _ids_from_whitelist_file(authorization):
    relative = str(authorization.get('whitelist_file', ''))
    path = (ROOT / relative).resolve()
    allowed_root = (ROOT / 'private' / 'p5c').resolve()
    if allowed_root not in path.parents or path.suffix.lower() != '.txt':
        raise PlanError('whitelist path refused')
    text = path.read_text(encoding='utf-8')
    return [line for line in text.splitlines() if line]


def _confirm_resume_baseline(report, whitelist, checkpoint):
    saved = json.loads(pathlib.Path(checkpoint).read_text(encoding='utf-8'))
    records = saved.get('records', {})
    present = set(report.get('present_ids') or ())
    verified = {entry_id for entry_id in whitelist if records.get(entry_id, {}).get('state') == 'verified'}
    planned = {entry_id for entry_id in whitelist if records.get(entry_id, {}).get('state') == 'planned_create'}
    uncertain = {
        entry_id for entry_id in whitelist
        if records.get(entry_id, {}).get('state') in {'awaiting_result', 'created_unverified', 'pending_reconciliation'}
    }
    if report.get('isolated_blank_pages') != 1 or report.get('protected') != 510:
        raise PlanError('resume baseline refused')
    if report.get('pages') != report.get('unique_ids', 0) + 1:
        raise PlanError('resume baseline refused')
    if planned & present or set(ISOLATED_PENDING_IDS) & present:
        raise PlanError('resume ids already present')
    if not verified <= present:
        raise PlanError('resume baseline refused')
    present_whitelist = set(whitelist) & present
    if present_whitelist - verified - uncertain:
        raise PlanError('resume baseline refused')
    if report.get('unique_ids') != 1053 + len(present_whitelist) or report.get('remaining_present') != 543 + len(present_whitelist):
        raise PlanError('resume baseline refused')


def _check_trial_authorization(authorization, plan):
    words = [plan.payloads[entry_id]['单词'] for entry_id in plan.trial_ids]
    if authorization.get('phase') != 'P5-C.4B' or authorization.get('max_creates') != 10:
        raise PlanError('authorization phase refused')
    if any(authorization.get(name) for name in ('allow_update', 'allow_delete', 'allow_events', 'allow_full_import')):
        raise PlanError('authorization permission refused')
    if normalize_id(str(authorization.get('data_source_id', ''))) != normalize_id(FORMAL_SOURCE):
        raise PlanError('authorization data source refused')
    if list(authorization.get('entry_ids') or []) != list(plan.trial_ids) or list(authorization.get('words') or []) != words:
        raise PlanError('trial whitelist refused')


def _write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    sys.exit(main())
