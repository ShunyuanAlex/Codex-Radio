#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
python3 - "$1" <<'PY'
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

root = Path.cwd()
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'local.wingradio.menubar'
assert app.name == 'Codex Radio.app'
version = info['CFBundleShortVersionString']
release = root / 'build' / f'Codex Radio-{version}.zip'
output = root / 'build' / f'Codex Radio-{version}.dmg'

with tempfile.TemporaryDirectory(prefix='codex-radio-dmg-') as temporary:
    staging = Path(temporary) / 'volume'
    staging.mkdir()
    image = Path(temporary) / 'Codex Radio.dmg'
    shutil.copytree(app, staging / app.name, copy_function=shutil.copy)
    (staging / 'Applications').symlink_to('/Applications')
    with zipfile.ZipFile(release) as archive, zipfile.ZipFile(staging / 'Source.zip', 'w', zipfile.ZIP_DEFLATED) as source:
        prefix = 'Codex Radio/源码/'
        for item in archive.infolist():
            if item.filename.startswith(prefix):
                relative = item.filename[len(prefix):]
                entry = zipfile.ZipInfo('Codex Radio/' + relative, date_time=item.date_time)
                entry.external_attr = item.external_attr
                entry.compress_type = zipfile.ZIP_DEFLATED
                source.writestr(entry, archive.read(item))
    (staging / '安装说明.txt').write_text(f'''Codex Radio {version}
Apple Silicon / Intel 通用版，macOS 13 及以上。Intel 尚未完成实机验收。

1. 先安装并登录 Codex。将 Codex Radio.app 拖入 Applications，然后从应用程序文件夹启动。
已有版本请先退出，在原位置替换；旧版位于个人 ~/Applications 时请替换该处，避免两个副本。
2. 首次打开会进入“接入与权限”，确认 Codex 目录并点击“允许读取并安装接入”。内置原生接入程序，无需 Python、Homebrew 或 Xcode。
3. 在 Codex 中审查并信任12项 Radio Hooks。可用页面中的“复制 CLI 启动命令”，在终端启动后输入 /hooks 逐项审查。安装配置不会自动授予信任。
4. 重新打开一个本地对话并发送一句话，看到 Radio 已收到真实事件后，在菜单栏启用播报。默认静音启动；可在“通用”中开启启动后自动播报，使用保存的音量。
无需 API Key、辅助功能、屏幕录制、麦克风或完整磁盘访问。不会写入信任库，不会改变Codex权限。登录时自动启动可在通用设置单独开启；系统待允许状态需用户在登录项设置确认。
接入页可选择自定义 CODEX_HOME。管理员禁用 Hooks 时应联系管理员，Radio不会绕过限制。
正式审查说明：https://learn.chatgpt.com/docs/hooks

当前包使用 ad-hoc 签名，未进行 Apple 公证，另一台 Mac 可能拦截启动。
确认来源后，先尝试打开，再按Apple说明前往“系统设置 → 隐私与安全 → 仍要打开”。不要关闭 Gatekeeper。
https://support.apple.com/en-us/102445

设置按通用、声音与模式、呼号分配、接入与权限四页组织。
采用飞机控制面板风格。通用可设置登录自启动、自动播报、音量和菜单栏。
设置可选择“仅图标”或“图标 + Radio”、B777／A320／歼-11A 声音包、模式与呼号。详细模式和自定义默认包含压缩提示。旧12项Hooks、呼号、编号与模式保持。
Source.zip 含对应完整源码、音源、许可证及“说明与来源.txt”“接入边界.txt”。
源码遵循 GPL-2.0；真人呼号录音遵循 CC BY-SA 3.0；歼-11A 素材按上游声明保留 GPL 许可和作者署名。完整来源与许可见源码。
''')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(staging / app.name)], check=True)
    # DiskImages can fail to reopen a new image in a synced checkout. Verify in
    # the same local staging directory used for the signed app, then copy bytes.
    subprocess.run(['/usr/bin/hdiutil', 'create', '-volname', 'Codex Radio', '-srcfolder', str(staging), '-format', 'UDZO', '-ov', str(image)], check=True)
    # DiskImages may still hold the newly created file briefly (EAGAIN).
    # Retry that transient condition only; real verification failures still stop.
    for attempt in range(3):
        verified = subprocess.run(['/usr/bin/hdiutil', 'verify', str(image)], capture_output=True, text=True)
        if verified.returncode == 0:
            print(verified.stdout)
            break
        detail = verified.stdout + verified.stderr
        if attempt == 2 or not any(message in detail for message in ['Resource temporarily unavailable', '资源暂时不可用']):
            raise RuntimeError('Disk image verification failed: ' + detail)
        time.sleep(attempt + 1)
    shutil.copyfile(image, output)
    if hashlib.sha256(image.read_bytes()).digest() != hashlib.sha256(output.read_bytes()).digest():
        raise RuntimeError('Copied disk image checksum mismatch')
print(output)
PY
