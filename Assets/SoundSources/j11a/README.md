# 歼-11A 模拟器声音来源

来源：[yanes19/SU-27SK](https://github.com/yanes19/SU-27SK/tree/925cb5317f3c66fa323a9e186e24d574e0b0881d)，固定提交 `925cb5317f3c66fa323a9e186e24d574e0b0881d`。作者：Yanes Bechir、FGUK team、Sidi Liang（J-11A 变体）及上游 README 列出的贡献者。

该项目的 `J-11A-set.xml` 提供中国沈飞歼-11A 变体。音源是 J-11A / Su-27SK 共用的飞行模拟器素材；不声称是中国机型实机录音、原机语音或官方警报。这里只取按键和电子音，未使用俄语语音、引擎、枪炮或爆炸音效。

## 许可与原始记录

上游 `UPSTREAM-README.md` 明确声明 GPL-3.0-or-later，但上游 LICENSE / COPYING 附带的是 GPL-2.0 文本。上述文件保留为 `UPSTREAM-LICENSE-GPL-2.0.txt` 和 `UPSTREAM-COPYING.txt`，没有改写其条款。此声音改编按上游 README 的 GPL-3.0-or-later 声明分发，并随附 `GPL-3.0.txt`。设备名称只描述模拟器机型，不表示作者、沈飞或 FlightGear 对本应用背书。

2026-10-07 下载的三段原始 WAV 保持字节不变；文件地址及 SHA-256 见 `manifest.json`。原始输入、完整处理源码、成品与许可均随发行源码提供。机型和素材关系保留在 `J-11A-set.xml`、`sounds.xml`、`Su-27-sound.xml`。

## Codex Radio 改动

转为 24 kHz 单声道 PCM、选段、端点淡化、重采样移调、重复与停顿编排、有效电平匹配、峰值限制。没有增加合成振荡器或语音。播放阶段再匹配当前呼号有效 RMS。改编者：Codex Radio，2026-10-07。

| 事件 | 来源和处理 |
| --- | --- |
| 发送 | click.wav 的 0–0.090 秒，端点淡化 |
| 处理中 | warning2 的 0.560–0.980 秒，2 倍重采样，取 0.200 秒并衰减为单声短铃 |
| 工具返回 | 同段 3 倍重采样，各取 0.070 秒，两声间隔 85 ms |
| 压缩 | 同段分别以 2.8 / 1.8 倍重采样，取 0.130 / 0.230 秒，间隔 40 ms |
| 本轮收尾 | 同段分别以 1.5 / 2 倍重采样，取 0.230 / 0.210 秒，间隔 85 ms |
| 等待确认 | Cockpit-warning.wav 的 0.055–0.225 秒，两声间隔 380 ms |
| 停止 | warning2 同段 0.85 倍重采样，取 0.270 秒并衰减 |
| 报错 | Cockpit-warning.wav 的 0.055–0.275 秒，等速三声，间隔 75 ms |

表中 warning2 指 `su-27cockpit-warning2.wav`。精确包络见 `AudioTools/build_packs.py` 的 `j11a_cues()`，输出哈希与时长见 `Assets/SoundPacks/catalog.json`。
