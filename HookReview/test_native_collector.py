"""Exercise the packaged native helper against isolated synthetic events only."""
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

helper = Path(sys.argv[1]).resolve()
passed = 0


def check(name, condition):
    global passed
    assert condition, name
    passed += 1
    print('PASS ' + name)


def run(payload, root):
    before = set(root.glob('event-*.json'))
    raw = payload if isinstance(payload, str) else json.dumps(payload)
    result = subprocess.run([str(helper), '--spool', str(root)], input=raw, text=True, capture_output=True, timeout=4, check=True)
    assert result.stdout.strip() == '{}', 'helper must never emit a hook decision'
    return [json.loads(p.read_text()) for p in set(root.glob('event-*.json')) - before]


with tempfile.TemporaryDirectory(prefix='radio-native-') as temporary:
    root = Path(temporary).resolve() / 'events'
    base = dict(session_id='test', turn_id='turn', tool_use_id='tool', agent_id='child', tool_input={'command':'PRIVATE'}, transcript_path='PRIVATE', prompt='PRIVATE', summary='PRIVATE', last_assistant_message='PRIVATE')
    expected = {'SessionStart':None, 'SessionEnd':None, 'UserPromptSubmit':None, 'PreToolUse':'testing', 'PostToolUse':'unknown', 'PermissionRequest':'waiting', 'Stop':'complete', 'Interrupt':'cancelled', 'SubagentStart':'delegating', 'SubagentStop':'unknown', 'PreCompact':'compacting', 'PostCompact':None}
    for event, status in expected.items():
        rows = run(dict(base, hook_event_name=event), root)
        check('原生事件 ' + event, len(rows)==1 and rows[0]['status']==status and rows[0]['session']=='test' and rows[0]['agent']=='child' and 'PRIVATE' not in json.dumps(rows))
    a = run(dict(base, hook_event_name='PreToolUse'), root)[0]
    b = run(dict(base, hook_event_name='PreToolUse'), root)[0]
    check('工具事件去重标识稳定', a['id']==b['id'])
    a = run(dict(base, hook_event_name='PreCompact'), root)[0]
    b = run(dict(base, hook_event_name='PreCompact'), root)[0]
    check('多次压缩使用不同标识', a['id']!=b['id'])
    for response, expected in [({'exit_code':7},'blocked'),({'exit_code':0},'success'),({'exit_code':False},'unknown'),({'isError':True},'blocked'),({'isError':1},'unknown'),({'content':'exit code 0'},'unknown')]:
        result = run(dict(base, hook_event_name='PostToolUse', tool_name='Bash', tool_response=response), root)[0]
        check('明确结果 ' + json.dumps(response), result['status']==expected)
    check('超限输入不生成文件', not run('x'*1048577, root))
    check('无效JSON不生成文件', not run('{bad', root))
    check('缺少会话标识不生成文件', not run({'hook_event_name':'Stop'}, root))
    check('非对象输入不生成文件', not run([], root))
    check('文件与目录为私有权限', stat.S_IMODE(root.stat().st_mode)==0o700 and all(stat.S_IMODE(p.stat().st_mode)==0o600 for p in root.glob('event-*.json')))
    link=root.parent/'symlink';link.symlink_to(root, target_is_directory=True)
    check('拒绝符号链接事件目录', not run(dict(base, hook_event_name='Stop'), link))

print(f'{passed} native collector checks passed; isolated inputs only, no live hooks changed.')
