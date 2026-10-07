"""Package our authored app and corresponding source with UTF-8 ZIP names."""
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parent
app = Path(sys.argv[1]).resolve()
assert app.name == "Codex Radio.app" and (app / "Contents/MacOS/CodexRadio").is_file()
output = root / "build/Codex Radio-0.11.2.zip"
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        if path.is_file():
            archive.write(path, "Codex Radio/Codex Radio.app/" + str(path.relative_to(app)))
    for name in ["App.swift", "Views.swift", "Domain.swift", "ConversationActivity.swift", "ConversationCatalog.swift", "RecordedAudio.swift", "LiveEvents.swift", "Integration.swift", "IntegrationTests.swift", "HookCollector.swift", "Startup.swift", "StartupTests.swift", "Cockpit.swift", "Tests.swift", "build.sh", "package.py", "make-dmg.sh", "说明与来源.txt", "接入边界.txt", ".gitignore", "README.md", "CHANGELOG.md", "LICENSE", "THIRD_PARTY_NOTICES.md"]:
        archive.write(root / name, "Codex Radio/源码/" + name)
    # Never include generated hook definitions or local installation review records.
    for name in ["collector.py", "compaction_collector.py", "install.py", "test_collector.py", "test_compaction.py", "test_native_collector.py", "voice-catalog.json"]:
        archive.write(root / "HookReview" / name, "Codex Radio/源码/HookReview/" + name)
    for path in sorted((root / "Assets").rglob("*")):
        if path.is_file() and path.name != ".DS_Store":
            archive.write(path, "Codex Radio/源码/Assets/" + str(path.relative_to(root / "Assets")))
    for path in sorted((root / "AudioTools").glob("*")):
        if path.is_file() and path.suffix in {".py", ".swift", ".c", ".json"}:
            archive.write(path, "Codex Radio/源码/AudioTools/" + path.name)
    for path in sorted((root / "docs").rglob("*")):
        if path.is_file() and path.name != ".DS_Store":
            archive.write(path, "Codex Radio/源码/docs/" + str(path.relative_to(root / "docs")))
    archive.write(root / "说明与来源.txt", "Codex Radio/使用说明.txt")
    archive.write(root / "接入边界.txt", "Codex Radio/接入边界.txt")
    archive.write(root / "build/verification.txt", "Codex Radio/无声验证.txt")
    archive.write(root / "LICENSE", "Codex Radio/LICENSE")
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert "Codex Radio/Codex Radio.app/Contents/MacOS/CodexRadio" in archive.namelist()
    assert archive.getinfo("Codex Radio/Codex Radio.app/Contents/MacOS/CodexRadio").external_attr >> 16 & 0o111
print(output)
