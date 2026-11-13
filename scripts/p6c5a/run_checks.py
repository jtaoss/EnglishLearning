"""Execute relevant Python and Dart checks and retain actual exit codes."""
from common import *
import sys
import concurrent.futures
import re

def check(item):
    name,args=item
    completed=subprocess.run(args,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace')
    output=completed.stdout+'\n'+completed.stderr
    log=OUT/'verification'/f'{name}.txt';log.parent.mkdir(exist_ok=True)
    log.write_text(output,encoding='utf-8')
    result={'name':name,'command':args,'exit_code':completed.returncode,'output_file':log.relative_to(ROOT).as_posix()}
    match=re.search(r'Ran (\d+) tests?',output)
    if match:result['test_count']=int(match[1])
    elif name=='flutter_contracts':
        passed=re.findall(r'\+(\d+):',output)
        result['test_count']=max(map(int,passed)) if passed else None
    print(name,'exit',completed.returncode,'tests',result.get('test_count'),flush=True)
    return result

def main():
    verify_frozen()
    items=[('python_scope_guard',[sys.executable,'-X','utf8','-m','unittest','discover','-s','test/p6c5a','-p','test_*.py','-v']),
      ('python_old_C5',[sys.executable,'-X','utf8','-m','unittest','discover','-s','test/p6c5','-p','test_*.py','-v']),
      ('flutter_contracts',['cmd','/c',r'E:\dev\flutter\bin\flutter.bat','test','--no-pub','--reporter','expanded',
           'test/p6c5a/scope_guard_contract_test.dart','test/p6c5/full_candidates_contract_test.dart'])]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(check,items))
    results.append(check(('dart_analyze',['cmd','/c',r'E:\dev\flutter\bin\dart.bat','analyze','test/p6c5a/scope_guard_contract_test.dart'])))
    require(verify_protection()['unchanged'],'Protected baseline changed during tests')
    save(OUT/'TEST_EXECUTION.json',{'all_passed':all(r['exit_code']==0 for r in results),
      'python_tests':sum(r.get('test_count',0) for r in results if r['name'].startswith('python')),
      'Dart_contract_tests':next(r.get('test_count') for r in results if r['name']=='flutter_contracts'),
      'commands':results,'semantic_gate_not_implied':True,'production_build_not_needed_for_isolated_data_review':True})
    require(all(r['exit_code']==0 for r in results),'A required test failed; see execution record')

if __name__=='__main__':main()
