# AutoRainieLove — 最后一人自动播雨爱

多人游戏只剩最后一名船员时，全服一起响起音乐，包括已死亡的玩家和旁观者。单人游戏仍在自己成为最后一名幸存者时播放。

当前音乐来自[《雨爱 DJ》一小时循环版](https://www.bilibili.com/video/BV18QqmBCEom)

## 使用

1. 安装并启用 **Lua for Barotrauma / Luatrauma**。多人游戏需要服务器运行 Lua，所有想听到音乐的人也需要安装客户端 Lua。
2. 服务器和所有客户端都启用同一版本的 `AutoRainieLove - 最后一人自动播雨爱`。修改后重新加载 Lua 或重启游戏，再开启新回合。
3. 所有客户端使用包含同一份 `Sounds/last_survivor.ogg` 的完整模组目录。模组只发送播放指令，不通过 Lua 消息传输音频。缺文件的客户端只提示一次，不打断其现有音乐。
4. 开启新回合，至少有两名存活船员。当人数降为一名时，服务器统一广播播放通知。

如需换歌，可以用 ffmpeg 转换本地音乐，再替换当前音频（Linux 区分大小写）：

```sh
ffmpeg -i "/你的音乐路径/歌曲.mp3" -c:a libvorbis -q:a 5 "/mnt/data/SteamLibrary/steamapps/common/Barotrauma/LocalMods/AutoRainieLove/Sounds/last_survivor.ogg"
```

音量跟随游戏的音乐音量，每回合触发一次，触发后持续循环片段。起播前立即停止原版背景音乐（含噪声音乐层）及其他模组使用 `music` 分类的音乐通道；整个循环播放期间阻止原版背景音乐更新，并持续清理新出现的其他 `music` 通道。环境音、警报、武器音效及语音保留。

人数不再为一人或回合结束后，停止循环并解除背景音乐限制，由游戏恢复正常选曲。播放通道意外停止时也解除限制。不会从原位置恢复已经停止的第三方音乐。把音乐当普通音效播放的模组无法仅凭音频通道辨认，需要单独适配。

## 判定范围

### 多人游戏

- 服务器每 0.25 秒统计 `Team1` 和 `Team2` 中尚未移除、尚未死亡的人类角色，包括机器人和归入玩家阵营的任务 NPC。PvP 两队合计，只剩一名时全服播放；其他阵营 NPC、怪物、宠物不计。
- 昏迷仍算存活。先观察到至少两名存活船员，之后降至一名才触发；独自开局和直接全灭不播放。
- 通过可靠网络消息向所有已连接客户端广播。死者、旁观者、房主客户端均可播放，不依赖本机控制的角色。不是逐帧同步，起播时间可能相差网络传输和本地加载所需的时间。
- 复活、补员导致人数超过一名，或最后一名也死亡时，服务器广播停止。每回合只广播一次开始，下回合重置。
- 中途加入不会补播已经发出的通知。角色被移除后不计入存活人数，仍留在场上的断线角色继续计数。

### 单人游戏

- 仍按当前控制的人类角色及相同 `TeamID` 的人类队友判断；必须先观察到活队友，再确认他们全部死亡。
- 自己死亡、旁观、切换角色、队友复活/补员时停止，每回合一次。
- 未确认死亡就消失的队友不会被当成死亡，因此特殊模组移除角色时可能不触发。

## 验证

在模组根目录运行 `lua tests/last_survivor_test.lua`。测试使用模拟游戏接口验证触发和清理逻辑，不替代游戏内音频及联机验证。

模拟测试覆盖单人规则、服务器人数判定与广播、存活/死亡/旁观客户端、重复通知、回合重置、音频错误和音乐互斥。不替代游戏内验证；背景音乐拦截依赖当前版本的 `SoundPlayer.UpdateMusic` 和 `musicChannel` 接口。

接口依据：[Luatrauma 网络文档](https://luatrauma.github.io/Luatrauma.Docs/api/lua/code/networking/)、[Hook 文档](https://luatrauma.github.io/Luatrauma.Docs/api/lua/code/hook/)、[游戏背景音乐源码](https://github.com/FakeFishGames/Barotrauma/blob/master/Barotrauma/BarotraumaClient/ClientSource/Sounds/SoundPlayer.cs)。
