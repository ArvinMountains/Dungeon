# 失落的深渊 · The Lost Abyss

2.5D 像素风暗黑地牢动作肉鸽，Godot 4.7.2 制作。

## 下载

最新版本见 **[Releases](https://github.com/ArvinMountains/Dungeon/releases)**。

- **[v0.2.0](https://github.com/ArvinMountains/Dungeon/releases/tag/v0.2.0)** — 当前版本
  - Windows（x86_64）：[LostAbyss-v0.2.0-win64.zip](https://github.com/ArvinMountains/Dungeon/releases/download/v0.2.0/LostAbyss-v0.2.0-win64.zip) — 解压后运行 `LostAbyss.exe`（需支持 Vulkan 的显卡）
  - 源码：Release 页的 `Source code (zip)`，用 Godot 4.7.2 打开 `project.godot` 运行

## 玩法

- 五个职业：游侠 / 战士 / 盾卫 / 刺客 / 法师
- 主城接委托 → 野外探索与捕宠 → 地下城五连房推进，清场三选一祝福，Boss 收尾
- 战斗：普攻、格挡招架、四个主动技能与大招、蓝条
- 同伴组队：阵型、集火、组合技（同伴先手挂标记，玩家补刀引爆）
- 敌人小队：横列/楔形/钳形/环形阵推进，并打出齐射/合击冲锋/散开合围/召唤突袭组合拳，前摇有预警
- 昼夜交替、宠物、NPC 任务、双货币经济、小地图

## 操作

| 操作 | 按键 |
|---|---|
| 移动 | `W A S D` / 方向键 |
| 奔跑 / 交互 | `Shift` / `E` |
| 攻击 | 鼠标左键 / `空格` |
| 格挡（招架） | `R` |
| 技能 / 大招 | `1 2 3 4` |
| 药剂 / 持火把 / 放火把 | `F` / `T` / `G` |
| 视角锁定 | `V` |
| 背包 / 地图 | `B` / `M` |
| 加点 / 任务 / 队伍 | `K` / `J` / `P` |
| 关闭窗口 | `Esc` |

## 从源码运行

1. 安装 [Godot 4.7.2](https://godotengine.org/download)
2. 用编辑器打开本目录的 `project.godot`
3. 按 `F5`

## 构建 Windows 版

需要先安装 Godot 4.7.2 导出模板，然后：

```powershell
godot --headless --path . --export-release "Windows Desktop" build/LostAbyss.exe
```

导出预设见 `export_presets.cfg`。
