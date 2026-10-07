"""Isolated compaction payload and hook upgrade checks; never installs live hooks."""
import importlib.util
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent
def load(name):
    spec = importlib.util.spec_from_file_location(name, root / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

collector = load('compaction_collector')
installer = load('install')
passed = 0
def check(description, condition):
    global passed
    assert condition, description
    passed += 1
    print('PASS ' + description)

payload = {'hook_event_name':'PreCompact','session_id':'parent','turn_id':'turn','agent_id':'child','trigger':'auto','transcript_path':'PRIVATE','summary':'PRIVATE','prompt':'PRIVATE'}
event = collector.normalize(payload, now=1)
check('自动压缩开始保留父子关联并映射提示', event['status']=='compacting' and event['session']=='parent' and event['agent']=='child')
check('手动压缩开始同样映射提示', collector.normalize(dict(payload, trigger='manual'))['status']=='compacting')
check('压缩结束只更新状态，没有第二个提示', collector.normalize(dict(payload, hook_event_name='PostCompact'))['status'] is None)
check('不保留正文、摘要或历史路径', 'PRIVATE' not in json.dumps(event) and set(event)=={'id','host','session','turn','agent','toolUse','event','status','receivedAt'})
check('同一轮多次压缩不会被错误去重', event['id'] != collector.normalize(payload, now=2)['id'])
check('拒绝无会话、其他事件及非对象输入', collector.normalize({}) is None and collector.normalize([]) is None and collector.normalize(dict(payload, hook_event_name='PreToolUse')) is None)
check('限定标识长度', len(collector.normalize(dict(payload, session_id='s'*400), host='h'*400)['session'])==256 and len(collector.normalize(payload, host='h'*400)['host'])==128)

with tempfile.TemporaryDirectory(prefix='radio-compact-test-') as temporary:
    home = Path(temporary)
    old, _ = installer.candidate(home)
    new, _ = installer.compaction_candidate(home)
    existing = json.loads(json.dumps(old))
    existing['hooks']['PreCompact'] = [{'hooks':[{'type':'command','command':'unrelated-hook','timeout':3}]}]
    merged = installer.merge(existing, installer.merge(old, new))
    check('升级保持原10项定义逐项不变', all(merged['hooks'][key]==existing['hooks'][key] for key in installer.EVENTS))
    check('只追加两个压缩事件且保留其他用户条目', set(merged['hooks'])==set(installer.EVENTS+installer.COMPACTION_EVENTS) and merged['hooks']['PreCompact'][0]==existing['hooks']['PreCompact'][0])
    check('重复安装不重复增加Hook', installer.merge(merged, installer.merge(old,new))==merged)
    spool = home / 'events'
    command = [sys.executable,str(root/'compaction_collector.py'),'--spool',str(spool)]
    result = subprocess.run(command,input=json.dumps(payload),text=True,capture_output=True,check=True)
    files = list(spool.glob('event-*.json'))
    stored = json.loads(files[0].read_text())
    check('命令输入到私有原子事件文件且不干预压缩', result.stdout.strip()=='{}' and len(files)==1 and stored['event']=='PreCompact' and stat.S_IMODE(files[0].stat().st_mode)==0o600 and stat.S_IMODE(spool.stat().st_mode)==0o700)
    subprocess.run(command,input='x'*1048577,text=True,capture_output=True,check=True)
    check('超限输入不生成事件', len(list(spool.glob('event-*.json')))==1)

print(f'{passed} compaction checks passed; synthetic inputs only, no live hooks installed.')
