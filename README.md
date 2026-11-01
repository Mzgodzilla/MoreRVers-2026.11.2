# MoreRVers v1.0.2

Host-side multiplayer expansion for **RV There Yet?** — raises the session player cap from the vanilla 4 to a configurable value (1–24).

> Only the **host** needs this mod. Friends join with an unmodified game.

---

## Why 1.0.2 exists

Game builds 1.3.20488 and later rewrite `GameSession.MaxPlayers` back to `4` shortly after the session object is created. The previous release applied the value once at construction time, so the game silently restored the vanilla cap: the lobby advertised `4/4`, was flagged not joinable, and a fifth player was rejected with a generic *“could not join session / unknown error”*.

1.0.2 keeps the value applied for the whole lobby lifetime instead of trusting a single hook point:

| Trigger | Purpose |
| --- | --- |
| `RegisterInitGameStatePostHook` | re-apply whenever a game mode / session is initialised |
| `RegisterLoadMapPostHook` | survive map travel and BeginPlay resets |
| `RegisterCustomEvent("K2_PostLogin")` | re-apply after every accepted player login |
| `/Script/Ride.RGGameSession:UpdateSessionSettings` pre-hook | set the cap immediately before the game advertises the lobby |
| 1.5 s safety timer | catch any remaining late writes |

Every write is read back and only reported as applied when the value actually stuck (`MaxPlayers 4 -> 8 [...]`). If a trigger is unavailable on your UE4SS build it is logged as `hook failed` and the other triggers keep working.

## Requirements

- **RV There Yet?** (Steam, Windows) — tested on `1.4.1.21945` (UE 5.6, `rel-1.4`)
- **UE4SS 3.0.1 or newer** (experimental branch) — the `WithUE4SS` package already contains a working build
- Mod is needed on the **host only**

## Installation

### Package A — With UE4SS (easiest)

1. Close the game.
2. Extract the archive into:
   ```
   <Steam>\steamapps\common\Ride\Ride\Binaries\Win64\
   ```
   The result must look like this (next to `Ride-Win64-Shipping.exe`):
   ```
   Win64\
   ├── dwmapi.dll
   └── ue4ss\
       ├── UE4SS.dll
       ├── UE4SS-settings.ini
       └── Mods\
           ├── mods.txt          (already contains "MoreRVers : 1")
           └── MoreRVers\
   ```
3. Launch the game and host a **new** lobby.

### Package B — Mod only (you already run UE4SS)

1. Close the game.
2. Copy the `Mods\MoreRVers` folder into `<...>\Win64\ue4ss\Mods\`.
3. Edit `ue4ss\Mods\mods.txt` and add the line **above** `Keybinds : 1`:
   ```
   MoreRVers : 1
   ```
4. Launch the game and host a **new** lobby.

## Configuration

`ue4ss\Mods\MoreRVers\config.ini`

```ini
MaxPlayers = 8
```

- Range: **1–24** (whole numbers). Default: `8`.
- Restart the game after changing it (the value is read at script load).

## Verifying it works

`ue4ss\UE4SS.log` should contain:

```
[MoreRVers] hook ok: InitGameState
[MoreRVers] hook ok: LoadMap
[MoreRVers] hook ok: K2_PostLogin
[MoreRVers] hook ok: UpdateSessionSettings
[MoreRVers] v1.0.2 loaded; target MaxPlayers=8
[MoreRVers] MaxPlayers 4 -> 8 [game initialized] GameSession ...
```

The game log (`%LOCALAPPDATA%\Ride\Saved\Logs\Ride.log`) should then advertise the raised cap:

```
LogRide: Warning: UpdateSessionSettings: RegisteredPlayers=5 PlayerArray=5 Advertising=5/8
LogNet: Join succeeded: <name>
```

`Advertising=x/8` (instead of `x/4`) and `joinability` staying `true` are the two things to look at.

## Troubleshooting

- **Still capped at 4 / fifth player rejected.** A Steam lobby keeps the member limit it was created with. After installing, fully restart the game and host a **brand-new lobby** — an existing lobby cannot be repaired.
- **`hook failed: ...` lines.** Your UE4SS is too old or a lifecycle API is missing. Update UE4SS to 3.0.1+.
- **Nothing from MoreRVers in the log.** The folder must be `ue4ss\Mods\MoreRVers\` (not `Win64\MoreRVers\`), and `mods.txt` must contain `MoreRVers : 1`.
- **`write did not stick` errors.** The game build changed how the session object is exposed; open an issue and include `UE4SS.log` plus the game log from that session.
- **Unknown-error joins that are not capacity related.** A version mismatch between host and client, Steam/EOS outages or NAT problems produce the same in-game message. The `Advertising=x/N` lines above tell you whether the cap is involved at all.

## Notes and limitations

- Only `GameSession.MaxPlayers` (live instance **and** the class default object) is modified. No game files, archives, widgets or other limits (e.g. party size) are touched.
- The cap is enforced by the game's own session code, so clients do not need the mod — but they must be on the **same game version** as the host.
- Game updates may change engine internals again. After a patch, re-check `UE4SS.log` for the `hook ok` / `MaxPlayers 4 -> 8` lines.
- 1.0.2 was verified with 5 players in a live Steam lobby. Higher values are supported by the config (up to 24) but were not load-tested.

## Credits and license

- Original mod: **Zzi** — [alex-nardozzi/MoreRVers](https://github.com/alex-nardozzi/MoreRVers)
- 1.0.2 compatibility work builds on the analysis in community PRs #15 and #17 (post-1.3.20488 cap resets)
- UE4SS by the [UE4SS team](https://github.com/UE4SS-RE/RE-UE4SS)
- Licensed under the MIT License — see `LICENSE`

---

## 中文速览

- **只有主机需要装**，队友用原版游戏即可加入。
- 装法：把压缩包解压到 `...\Ride\Binaries\Win64\`（`dwmapi.dll` 和 `ue4ss` 文件夹与 `Ride-Win64-Shipping.exe` 同级）。
- 人数：改 `ue4ss\Mods\MoreRVers\config.ini` 里的 `MaxPlayers`（1–24，默认 8），改完重启游戏。
- **装完必须重开游戏并新建大厅**：旧大厅的 4 人上限是 Steam 大厅创建时写死的，改不回来。
- 验证：`ue4ss\UE4SS.log` 里应有 `hook ok` 和 `MaxPlayers 4 -> 8`；游戏日志里应出现 `Advertising=5/8` 这类以 8 为分母的记录。
- 如果第 5 人还是报“无法加入会话，未知错误”，先看游戏日志里的 `Advertising` 分母：还是 `/4` 说明模组没生效；是 `/8` 但仍失败，则多半是版本不一致、Steam/EOS 网络或 NAT 问题。
