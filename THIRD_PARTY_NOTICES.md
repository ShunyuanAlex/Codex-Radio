# 第三方素材与许可证

应用源码沿用 GPL-2.0；根目录 [LICENSE](LICENSE) 提供许可证全文。下列素材保持各自的原作者、许可和来源声明。

## 真人呼号与数字

- 作品：[NATO Phonetic Alphabet reading](https://commons.wikimedia.org/wiki/File:NATO_Phonetic_Alphabet_reading.ogg)
- 作者：**valeatory**，2014-02-28，自行使用 Audacity 录制。
- 许可：[Creative Commons Attribution-ShareAlike 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/)，[法律文本](https://creativecommons.org/licenses/by-sa/3.0/legalcode)。
- 对应文件：`Assets/nato-source.wav`、`Assets/Voices/*.wav`。
- 改动：转换为 24 kHz 单声道 PCM，切分字母与数字，调整峰值、检测首尾、保留 8 ms 余量、2 ms 端点淡化；Alfa 去除发音结束后分离的低频长尾。播放时相邻人声使用 12 ms 线性叠化，不做语音合成、克隆或语速变化。
- 改编片段同样按 CC BY-SA 3.0 分发。切点和文件哈希见 `HookReview/voice-catalog.json`；处理代码见 `AudioTools/slice.py`。

## 空客声音包

- 项目：[FlightGear A320-family / FGMEMBERS](https://github.com/FGMEMBERS/A320-family/tree/00038142d3443d7f4aec9410520df608e8ae7ba8)
- 贡献者信息：[原项目 README](Assets/SoundSources/airbus/README.md)，含 FL2070 声音包署名。
- 许可：[GNU GPL version 2](Assets/SoundSources/airbus/COPYING)。
- 原始文件：`Assets/SoundSources/airbus/`；改编成品：`Assets/SoundPacks/airbus/`。
- 保留的早期原始副本：`Assets/click.wav`、`Assets/cabinalert.wav`、`Assets/320apoff.wav`，与该项目来源一致。

## 波音声音包

- 项目：[Boeing-777-Flightgear / franck-vmd](https://github.com/franck-vmd/Boeing-777-Flightgear/tree/42b53cbd1abff5a2cbc868c6576c79c343405b3d)
- 作者：Franck VMD 及项目贡献者，完整名单见 [AUTHORS](Assets/SoundSources/boeing/AUTHORS)。
- 许可：[GNU GPL version 2](Assets/SoundSources/boeing/LICENSE)。
- 原始文件：`Assets/SoundSources/boeing/`；改编成品：`Assets/SoundPacks/boeing/`。

## 航空素材的改动

2026-10-07，Codex Radio 对素材进行单声道 24 kHz PCM 转换、选段、淡入淡出、节奏排列、重复及静音间隔编排、有效电平匹配和峰值限制。波音压缩提示使用原始钟声以 1.25 倍与 0.9 倍重采样形成高低音。播放阶段按呼号的有效 RMS 匹配提示电平。

原始文件、固定上游提交和 SHA-256 见 `Assets/SoundSources/manifest.json`；成品参数见 `Assets/SoundPacks/catalog.json`；处理脚本见 `AudioTools/build_packs.py`。

素材在本应用中被重新分配事件含义，**不表示真实飞机上的相应警报语义**。本项目与 OpenAI、Boeing、Airbus 无隶属或背书关系，也没有采用商业航空游戏原声。
