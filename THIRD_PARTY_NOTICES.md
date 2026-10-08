# 第三方素材与许可证

应用源码沿用 GPL-2.0；根目录 [LICENSE](LICENSE) 提供许可证全文。下列素材保持各自的原作者、许可和来源声明。

## 真人呼号与数字

- 作品：[NATO Phonetic Alphabet reading](https://commons.wikimedia.org/wiki/File:NATO_Phonetic_Alphabet_reading.ogg)
- 作者：**valeatory**，2014-02-28，自行使用 Audacity 录制。
- 许可：[Creative Commons Attribution-ShareAlike 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/)，[法律文本](https://creativecommons.org/licenses/by-sa/3.0/legalcode)。
- 对应文件：`Assets/nato-source.wav`、`Assets/Voices/*.wav`。
- 改动：转换为 24 kHz 单声道 PCM，切分字母与数字，调整峰值、检测首尾、保留 8 ms 余量、2 ms 端点淡化；Alfa 去除发音结束后分离的低频长尾。播放时相邻人声使用 12 ms 线性叠化，不做语音合成、克隆或语速变化。
- 改编片段同样按 CC BY-SA 3.0 分发。切点和文件哈希见 `HookReview/voice-catalog.json`；处理代码见 `AudioTools/slice.py`。

## A320 声音包

- 项目：[FlightGear A320-family / FGMEMBERS](https://github.com/FGMEMBERS/A320-family/tree/00038142d3443d7f4aec9410520df608e8ae7ba8)
- 贡献者信息：[原项目 README](Assets/SoundSources/airbus/README.md)，含 FL2070 声音包署名。
- 许可：[GNU GPL version 2](Assets/SoundSources/airbus/COPYING)。
- 原始文件：`Assets/SoundSources/airbus/`；改编成品：`Assets/SoundPacks/airbus/`。
- 保留的早期原始副本：`Assets/click.wav`、`Assets/cabinalert.wav`、`Assets/320apoff.wav`，与该项目来源一致。

## B777 声音包

- 项目：[Boeing-777-Flightgear / franck-vmd](https://github.com/franck-vmd/Boeing-777-Flightgear/tree/42b53cbd1abff5a2cbc868c6576c79c343405b3d)
- 作者：Franck VMD 及项目贡献者，完整名单见 [AUTHORS](Assets/SoundSources/boeing/AUTHORS)。
- 许可：[GNU GPL version 2](Assets/SoundSources/boeing/LICENSE)。
- 原始文件：`Assets/SoundSources/boeing/`；改编成品：`Assets/SoundPacks/boeing/`。

## 航空素材的改动

2026-10-07，Codex Radio 对素材进行单声道 24 kHz PCM 转换、选段、淡入淡出、节奏排列、重复及静音间隔编排、有效电平匹配和峰值限制。B777 压缩提示使用原始钟声以 1.25 倍与 0.9 倍重采样形成高低音。播放阶段按呼号的有效 RMS 匹配提示电平。

原始文件、固定上游提交和 SHA-256 见 `Assets/SoundSources/manifest.json`；成品参数见 `Assets/SoundPacks/catalog.json`；处理脚本见 `AudioTools/build_packs.py`。

素材在本应用中被重新分配事件含义，**不表示真实飞机上的相应警报语义**。本项目与 OpenAI、Boeing、Airbus 无隶属或背书关系，也没有采用商业航空游戏原声。

## 歼-11A 声音包

- 项目：[FlightGear J-11A / Su-27SK](https://github.com/yanes19/SU-27SK/tree/925cb5317f3c66fa323a9e186e24d574e0b0881d)，固定提交 `925cb5317f3c66fa323a9e186e24d574e0b0881d`。
- 作者：Yanes Bechir、FGUK team、Sidi Liang（歼-11A 变体）及上游 README 列出的贡献者。逐条文件原作者没有在包内独立标注，保留上游完整声明。
- 机型依据：上游 `J-11A-set.xml` 明确提供 Shenyang J-11A 变体，使用项目共用 `Sounds` 音效。**这些是 J-11A / Su-27SK 共用的模拟器素材，不是经确认的中国飞机实机录音。**
- 许可：上游 README 明确声明 **GNU GPL version 3 or later**，根目录 LICENSE 和 COPYING 同时附带 GPL-2.0 文本。我们原样保留这些上游说明，并按 README 的 GPL-3.0-or-later 声明分发音频改编，提供 [GPL-3.0 全文](https://www.gnu.org/licenses/gpl-3.0.html)、所有原始输入和处理源码。未将这些音频改标为应用代码的 GPL-2.0-only。
- 原始素材：`Assets/SoundSources/j11a/click.wav`、`Cockpit-warning.wav`、`su-27cockpit-warning2.wav`；成品：`Assets/SoundPacks/j11a/`。
- 2026-10-07 改动：转为 24 kHz 单声道 PCM、截取、端点包络、重采样移调、重复与停顿编排、有效电平匹配和峰值限制。没有增加语音或合成振荡器；没有采用枪炮、爆炸或长引擎声。播放时按真人呼号匹配有效 RMS。
- 改编与事件映射：Codex Radio。八类提示是应用内重新编排，不代表原机警报含义；本应用与沈飞、原作者或 FlightGear 项目无官方隶属或背书关系。

精确来源与哈希见 [素材清单](Assets/SoundSources/j11a/manifest.json)，切点与处理说明见 [来源说明](Assets/SoundSources/j11a/README.md) 和 `AudioTools/build_packs.py`。

## 周额度预警与耗尽报警

- 沿用上述 B777 项目的 GPL-2.0 素材，固定提交相同；源文件为 `777-VMD/Sounds/GPWS/pull-up.wav`，完整原件保存在 `Assets/SoundSources/boeing/GPWS/`。
- 作者、许可证沿用 `Assets/SoundSources/boeing/AUTHORS` 和 `LICENSE`，未声称是真实飞机录音或厂商官方音效。
- 2026-10-09：转为 24 kHz 单声道 PCM、4 ms 端点淡化，完整短语重复两次，中间间隔 80 ms；播放时匹配 Alpha 呼号录音的有效电平。
- 三款声音包共用此账户级警报，不添加项目呼号；不生成或克隆语音。
- 成品 `Assets/Alerts/pull-up.wav`；来源与哈希见 `Assets/Alerts/manifest.json`，可用 `python3 AudioTools/build_quota_alarm.py` 重建。

- 耗尽警报另用同项目 `config-warning.wav` 的完整非语音警报，24 kHz 单声道 PCM、10 ms 端点淡化，单次播放；与原工具报错的三连选段节奏不同。成品 `Assets/Alerts/quota-exhausted.wav`，对应原件已包含在上述 B777 来源目录和清单中。
