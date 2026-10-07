"""Install only the reviewed Codex Radio files. Never changes hook trust or launch services."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import stat
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
EVENTS = ['SessionStart','SessionEnd','UserPromptSubmit','PreToolUse','PostToolUse','PermissionRequest','Stop','Interrupt','SubagentStart','SubagentStop']
COMPACTION_EVENTS = ['PreCompact','PostCompact']

def candidate(home):
    support = home / 'Library/Application Support/WingRadio'
    digest = hashlib.sha256((HERE / 'collector.py').read_bytes()).hexdigest()
    collector = support / ('collector-' + digest[:16] + '.py')
    command = '/usr/bin/python3 ' + shlex.quote(str(collector)) + ' --spool ' + shlex.quote(str(support / 'events')) + ' --host local'
    return {'hooks': {name: [{'hooks': [{'type':'command','command':command,'timeout':1}]}] for name in EVENTS}}, collector

def compaction_candidate(home):
    support = home / 'Library/Application Support/WingRadio'
    digest = hashlib.sha256((HERE / 'compaction_collector.py').read_bytes()).hexdigest()
    collector = support / ('compaction-collector-' + digest[:16] + '.py')
    command = '/usr/bin/python3 ' + shlex.quote(str(collector)) + ' --spool ' + shlex.quote(str(support / 'events')) + ' --host local'
    return {'hooks': {name: [{'hooks': [{'type':'command','command':command,'timeout':1}]}] for name in COMPACTION_EVENTS}}, collector

def merge(existing, addition):
    result = json.loads(json.dumps(existing))
    hooks = result.setdefault('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError('Existing hooks is not an object; no changes made')
    for name, groups in addition['hooks'].items():
        target = hooks.setdefault(name, [])
        if not isinstance(target, list):
            raise ValueError('Existing event groups are not a list; no changes made')
        for group in groups:
            if group not in target:
                target.append(group)
    return result

def private_directory(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Expected a private owned directory: ' + str(path))

def write_atomic(path, data):
    fd, name = tempfile.mkstemp(prefix='.wing-radio-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--app-only', action='store_true', help='Update only the app; preserve installed hook definitions and trust')
    args = parser.parse_args()
    home = Path.home()
    support = home / 'Library/Application Support/WingRadio'
    hooks = home / '.codex/hooks.json'
    app = Path(args.app).resolve()
    destination = home / 'Applications/Codex Radio.app'
    legacy_destination = home / 'Applications/翼台.app'
    addition, collector = candidate(home)
    compaction_addition, compaction_collector = compaction_candidate(home)
    addition = merge(addition, compaction_addition)
    for target in [home / '.codex', hooks, support, support / 'events', collector, compaction_collector, home / 'Applications', destination, legacy_destination]:
        if target.is_symlink():
            raise ValueError('Refusing symlink target: ' + str(target))
    app_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if app_info.get('CFBundleIdentifier') != 'local.wingradio.menubar':
        raise ValueError('Unexpected app bundle')
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)], check=True)
    old = hooks.read_bytes() if hooks.exists() else None
    existing = json.loads(old) if old else {}
    merged = merge(existing, addition)
    for existing_app in [destination, legacy_destination]:
        if existing_app.exists() and plistlib.loads((existing_app / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != 'local.wingradio.menubar':
            raise ValueError('Existing destination is a different app: ' + str(existing_app))
    plan = {'app':str(destination),'hooks':str(hooks),'collector':str(collector),'compaction_collector':str(compaction_collector),'events':[] if args.app_only else EVENTS+COMPACTION_EVENTS,'app_only':args.app_only,'hooks_modified':not args.app_only,'existing_hooks_preserved':True,'trust_modified':False,'login_service':False,'playback':False}
    if not args.apply:
        print(json.dumps({'mode':'review_only','plan':plan},ensure_ascii=False,indent=2));return
    if args.app_only:
        # This path never writes hooks.json, collector files or trust records.
        private_directory(support)
        stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup = support / ('app-backup-' + stamp)
        backup.mkdir(mode=0o700)
        staged = destination.parent / ('.WingRadio-' + stamp + '.app')
        shutil.copytree(app, staged, copy_function=shutil.copy)
        subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(staged)],check=True)
        for existing_app in [destination, legacy_destination]:
            if existing_app.exists():
                existing_app.rename(backup / (existing_app.stem + '.before.app'))
        staged.rename(destination)
        receipt={'updated_at':stamp,'app_version':app_info.get('CFBundleShortVersionString'),'app':str(destination),'backup':str(backup),'hooks_modified':False,'trust_modified':False}
        write_atomic(support / 'app-update-receipt.json',(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n').encode())
        print(json.dumps(receipt,ensure_ascii=False));return
    private_directory(support)
    private_directory(support / 'events')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = support / ('backup-' + stamp)
    backup.mkdir(mode=0o700)
    if old is not None:
        (backup / 'hooks.before.json').write_bytes(old)
        (backup / 'hooks.before.json').chmod(0o600)
    for source, target in [('collector.py', collector), ('compaction_collector.py', compaction_collector)]:
        contents = (HERE / source).read_bytes()
        if target.exists():
            if target.read_bytes() != contents:
                raise ValueError('Existing collector content does not match its hashed name')
        else:
            target.write_bytes(contents)
            target.chmod(0o444)
    destination.parent.mkdir(exist_ok=True)
    staged = destination.parent / ('.WingRadio-' + stamp + '.app')
    shutil.copytree(app, staged, copy_function=shutil.copy)
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(staged)],check=True)
    for existing_app in [destination, legacy_destination]:
        if existing_app.exists():
            existing_app.rename(backup / (existing_app.stem + '.before.app'))
    staged.rename(destination)
    # Refuse concurrent edits; do not overwrite a user's changes made during install.
    current = hooks.read_bytes() if hooks.exists() else None
    if current != old:
        raise ValueError('Hooks changed during install; app copied but hooks not modified')
    write_atomic(hooks, (json.dumps(merged,ensure_ascii=False,indent=2)+'\n').encode())
    receipt = {'installed_at':stamp,'plan':plan,'backup':str(backup),'added_definition':addition,'trust':'pending_user_review','app_version':app_info.get('CFBundleShortVersionString')}
    write_atomic(support / 'install-receipt.json',(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({'installed':True,'receipt':str(support / 'install-receipt.json'),'trust':'pending_user_review'},ensure_ascii=False))

if __name__ == '__main__':
    main()
