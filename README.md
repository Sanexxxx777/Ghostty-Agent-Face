# ghostty-agent-face

A living ASCII face on your [Ghostty](https://ghostty.org) terminal background that shows your AI agent's status at a glance — no tokens, no daemons, no polling.

**[▶ Watch the 30-second demo with sound](https://github.com/Sanexxxx777/ghostty-agent-face/releases/download/v1.0/demo.mp4)**

| State | Trigger | Face |
|---|---|---|
| 😐 **Idle** | no signal | dim blue half-closed eyes, occasional blink, slow look-around |
| 🤔 **Thinking** | you submit a prompt | amber round eyes, pupils on the move, bobbing **?** |
| ⚙️ **Working** | agent runs a tool | gold narrowed eyes looking down at the "keyboard", typing jitter, running **…** |
| 🐣 **Helpers** | agent spawns subagents | working face plus two pairs of small satellite eyes swaying in antiphase |
| 😊 **Done** | agent finishes the turn | green happy arc-eyes `^ ^`, wide smile, drifting fireflies |
| 😮 **Needs you** | agent waits for approval | orange wide eyes, mouth **o**, pulsing **!** |
| 😵 **Dizzy** | context compaction | purple spinner eyes `@ @` (counter-rotating), wavy mouth |
| 😴 **Sleep** | 30 min of unread "done" | closed dash-eyes, slow breathing, three **Z** — and the **aquarium wakes up**: 4 hued fish, seaweed, a crab patrolling the bottom, a sleeping turtle |

And it is genuinely alive:

- **pupils follow your terminal cursor** (Ghostty cursor uniforms) — the face watches you type;
- the **fish** swim on stateless Lissajous paths, turn with their motion, wag their tails and lazily avoid your cursor; bubbles rise behind them;
- a **watchdog** (one sleeping process, no daemon) auto-resets the face if the agent dies, catches "you came back and pressed a key" to dismiss the green smile, and escalates a long-unread "done" into Sleep;
- after **23:00 local** everything politely dims.

The face is drawn as an ASCII-style cell grid (mini-glyphs `0` / block / dot), gently breathes and floats, and **never gets in the way of your text**: any cell that contains terminal glyphs automatically goes dark.

## How it works

Two decoupled layers; the terminal background color itself is the IPC channel:

1. **Signal layer** — agent lifecycle hooks call `hooks/agent-face.sh`, which writes an OSC 11 "signal color" to the session's tty (found by walking the hook process's parent chain — hook processes have no controlling tty). Pure shell.
2. **Render layer** — `shaders/agent-face.glsl`, a Ghostty custom shader, samples the background from the window corners, classifies the signal by **exact color distance** to the known offsets, repaints background pixels back to your normal theme color, and draws the matching face on top.

So the visible background never changes — the signal color is an invisible carrier. Without the shader you'd just get a slightly tinted background; without the hooks the face sits calmly in idle.

## Install

Requirements: Ghostty ≥ 1.2 (macOS), an agent with lifecycle hooks (Claude Code shown below), `lsof` (preinstalled on macOS).

1. Copy the shader and hook script:

```sh
mkdir -p ~/.config/ghostty/shaders ~/.claude/hooks
cp shaders/agent-face.glsl ~/.config/ghostty/shaders/
cp hooks/agent-face.sh hooks/agent-face-watch.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/agent-face.sh ~/.claude/hooks/agent-face-watch.sh
```

2. Add to your Ghostty config (`~/Library/Application Support/com.mitchellh.ghostty/config` or `~/.config/ghostty/config`):

```ini
custom-shader = ~/.config/ghostty/shaders/agent-face.glsl
# animate in unfocused windows too — status is for the windows you are NOT looking at
custom-shader-animation = always
```

3. Wire the hooks — for Claude Code, merge into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh run" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh pre" }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh run" }] }],
    "PostToolUseFailure": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh fail" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh done" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh attn" }] }],
    "PreCompact":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh dizzy" }] }],
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh reset" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh reset" }] }]
  }
}
```

Any other agent works the same way — call `agent-face.sh run|done|attn|work|helpers|dizzy|sleep|reset` on its lifecycle events. The `pre` state reads the hook's stdin JSON and picks `helpers` for subagent tools (`Agent`/`Task`/`Workflow`), `work` otherwise.

4. Reload Ghostty config (`Cmd+Shift+,`). No restart needed — `custom-shader` applies at runtime to all open terminals.

## Try it without an agent

```sh
printf '\033]11;#2A2C34\033\\'   # thinking (amber, "?")
printf '\033]11;#282E34\033\\'   # working (gold, "...")
printf '\033]11;#2A2E36\033\\'   # helpers (satellite eyes)
printf '\033]11;#282C36\033\\'   # done (green, smile)
printf '\033]11;#2A2E34\033\\'   # needs you (orange, "!")
printf '\033]11;#2A2C36\033\\'   # dizzy (purple spinners)
printf '\033]11;#282E36\033\\'   # sleep (z z z + fish)
printf '\033]111\033\\'          # reset -> idle
```

The signal colors are deliberately near-identical to the theme background (`+2/255` on one or two channels): the background **never visibly changes**, with or without the shader — the signal is a color delta the eye cannot see.

## What's new in v1.1

Three new states, all on `+6/255` signal offsets (the seven `+3` combinations were taken):

| State | Trigger | Look |
|---|---|---|
| `fail` | a tool call errors (`PostToolUseFailure`) | "><" eyes for ~2s, then back to work |
| `tired` | `work`/`run` held for 10+ minutes (watcher) | half-closed eyes, dim progress dots |
| `skull` | state says working but no agent process on the tty for 2+ minutes (watcher) | a skull |

Two fixes worth having even if you skip the new states:

- **`setsid` does not exist on macOS.** Every `(setsid ... &)` spawn in earlier versions failed silently under the output redirect, so the watcher (crash detect, auto-sleep) never actually ran. Replaced with `nohup ... </dev/null >/dev/null 2>&1 & disown`.
- **`PostToolUse` only fires on success.** Tool errors arrive on a separate `PostToolUseFailure` event (its stdin JSON carries `error` and `is_interrupt` — Ctrl-C is skipped, it is not a failure).

The watcher reads a per-tty state file (`.agent-face-state-<tty>`), so several parallel agent sessions don't mask each other's staleness.

## Tuning

Everything is a constant in `agent-face.glsl`:

| What | Where |
|---|---|
| Your theme background (**must match**, default `#282c34`) | `BASE_BG` |
| Face position / size | `anchor` (screen fraction), `faceScale` |
| Overall brightness | `bright` |
| ASCII grid density | `R.y / 72.0` divisor |
| Text-protection strength | `smoothstep(0.05, 0.16, bgd)` and the `textIn` dimmer |

Signal colors live at the top of `agent-face.sh` and in the classifier thresholds of the shader — change both together.

## Notes & gotchas

- Ghostty's GLSL→Metal chain **silently drops** shaders that fail to compile. If you edit the shader and the face disappears, simplify your change — there is no error message.
- If your theme background differs from `#282c34`: update `BASE_BG` in the shader **and** recompute the hook colors as `background + 3` on the corresponding channels (R=thinking, G=working, B=done, RG=needs-you, RB=dizzy, GB=sleep, RGB=helpers) and `+ 6` for the v1.1 states (R=fail, G=tired, B=skull).
- On terminals other than Ghostty the shader does nothing and the signals are invisible by design — nothing to clean up. Kill switch: `touch ~/.claude/hooks/agent-face.disabled`.

## Credits

Mechanism (OSC 11 as a hook→shader IPC channel) popularized by [astra-glow](https://github.com/Astralune-ai/astra-glow); this project is an independent implementation with its own renderer.

MIT license.

## Contact

[@Aleksandr_NFA](https://github.com/Sanexxxx777) — issues and PRs welcome.

---

## На русском (кратко)

Живая ASCII-мордочка на фоне терминала [Ghostty](https://ghostty.org), показывающая статус
ИИ-агента (думает / работает / готово / нужна помощь и т.д.) — без токенов, без демонов, без
поллинга. Сигнальный слой пишет невидимый OSC 11 цвет фона через хуки жизненного цикла агента
(`hooks/agent-face.sh`), рендер-слой — кастомный GLSL-шейдер Ghostty (`shaders/agent-face.glsl`),
который считывает этот цвет и рисует мордочку поверх фона, не меняя видимый цвет темы. Требует
Ghostty ≥ 1.2 (macOS). Установка — см. раздел Install выше.
