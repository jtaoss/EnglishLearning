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
    ImportSession,
    PlanError,
    QueryFailed,
    REMAINING_CREATE,
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
    session = ImportSession(
        plan, writer, args.checkpoint, phase=args.phase,
        spacing_seconds=SPACING_SECONDS, max_creates=max_creates,
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
        report = compare_protected_library(plan, reader.query_all(), schema)
    except (QueryFailed, UncertainResult, PlanError):
        raise PlanError('protected library check failed') from None
    if not report['ok']:
        raise PlanError('protected library drifted')


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
