"""Validate the configured generation model on known fixtures before freezing."""
from api_client import call, system_prompt
from common import *
from records import parse_response
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--effort', choices=['low', 'high'], default='high')
    parser.add_argument('--publisher', action='store_true')
    parser.add_argument('--model', choices=['deepseek-v4-pro', 'deepseek-flash'], default='deepseek-v4-pro')
    args = parser.parse_args()
    source = {r['entry_id']: r for r in formal_rows()}
    refs = read(ROOT / 'private/p6c4/wordnet_selected600.json')['headwords']
    words = ['import', 'support', 'management', 'clause', 'escape', 'indicate']
    byword = {r['word']: r for r in source.values()}
    items = [packet(byword[w], refs[w]) for w in words]
    if args.publisher:
        # Original short summaries of primary pages actually inspected again
        # this round. Not old generation answers or a fake corpus ranking.
        observations = {
            'clause': [('n', 'Grammar category includes main, subordinate and coordinate/independent clauses; it need not constitute a sentence. A separate noun is a section of a legal document.')],
            'import': [('n', 'Noun: the action of bringing goods from abroad; separately, imported goods/products; separately, importance or meaning.'),
                       ('v', 'Verb: buy or bring goods from another country; computing: bring information/data from another software/device.')],
            'management': [('n', 'Uncountable noun: controlling/organizing an organization, resources or life. Separately, collective people who control/organize a business.')],
        }
        for item in items:
            for pos, text in observations.get(item['word'], []):
                item['evidence'].append({'id': f"pub:p6c5:collins:{item['word']}:{pos}", 'pos': pos, 'definition': text})
        save(OUT / 'PREFLIGHT_PUBLISHER_EVIDENCE.json', {'observed_utc': now(),
             'method': 'parent actually opened primary publisher pages; short original summaries; no copied full definitions/IPA/examples',
             'records': [{'word': w, 'url': 'https://www.collinsdictionary.com/dictionary/english/' + w,
                          'observations': o} for w, o in observations.items()]})
    tag = 'preflight_generation_v3' if args.effort == 'high' else 'preflight_generation_v3_low'
    if args.publisher:
        tag += '_publisher'
    if args.model != 'deepseek-v4-pro':
        tag += '_flash'
    api = call(tag, system_prompt('generation'), {'records': items}, max_tokens=24000, effort=args.effort, model=args.model)
    ds = parse_response(api, items)
    save(OUT / ('PREFLIGHT_GENERATION_v3_' + args.effort + ('_publisher' if args.publisher else '') + ('_flash' if args.model != 'deepseek-v4-pro' else '') + '.json'), {'utc': now(), 'fixture_words': words,
         'decisions': ds, 'checks': {'identity_mapping_POS_and_refs': True},
         'semantic_fixture_adjudication': 'pending_parent_review_before_run_freeze',
         'api_file': 'api/' + tag + '.json'})
    print(json.dumps(ds, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
