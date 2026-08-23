#!/bin/bash
# agent-face-watch.sh — сторож фона морды: краш-детект + автосон + сброс по активности
# Вызов: agent-face-watch.sh <TTY> <ANCHOR_PID> <STATE>
# STATE: run|done|attn|work|dizzy|helpers (sleep — внутреннее переключение из done)
# v6 добавляет: TIRED (>=10 мин непрерывно в work/run) и SKULL (>=2 мин в work/run
# БЕЗ единого процесса claude на этом tty — краш-сценарий, отличный от "anchor_pid умер").
# Источник истины для обеих проверок — общий с agent-face.sh state-файл (не $state:
# тот не отражает внешние сигналы, пришедшие уже ПОСЛЕ старта этого сторожа).

tty="$1"
anchor_pid="$2"
state="$3"

[ -n "$tty" ] && [ -n "$anchor_pid" ] && [ -n "$state" ] || exit 0

state_file="$HOME/.claude/hooks/.agent-face-state-$(basename "$tty")"

start_ts=$(date +%s)
tick=0
max_ticks=240
tired_sent=0

reset_face() {
    printf '\033]111\007' > "$tty" 2>/dev/null
}

while [ "$tick" -lt "$max_ticks" ]; do
    kill -0 "$anchor_pid" 2>/dev/null || { reset_face; exit 0; }

    if [ "$state" = "done" ] || [ "$state" = "sleep" ]; then
        atime=$(stat -f %a "$tty" 2>/dev/null)
        if [ -n "$atime" ] && [ "$atime" -gt "$start_ts" ]; then
            reset_face
            exit 0
        fi
    fi

    if [ "$state" = "done" ]; then
        now=$(date +%s)
        elapsed=$((now - start_ts))
        if [ "$elapsed" -ge 1800 ]; then
            printf '\033]11;#282F37\007' > "$tty" 2>/dev/null
            state="sleep"
        fi
    fi

    file_line=$(cat "$state_file" 2>/dev/null)
    file_ts=${file_line% *}
    file_state=${file_line#* }
    if [ -n "$file_ts" ] && { [ "$file_state" = "work" ] || [ "$file_state" = "run" ]; }; then
        now=$(date +%s)
        stale=$((now - file_ts))
        if [ "$stale" -ge 600 ] && [ "$tired_sent" -eq 0 ]; then
            printf '\033]11;#283234\007' > "$tty" 2>/dev/null
            tired_sent=1
        fi
        if [ "$stale" -ge 120 ] && ! ps -t "$(basename "$tty")" -o comm= 2>/dev/null | grep -qx claude; then
            printf '\033]11;#282C3A\007' > "$tty" 2>/dev/null
            exit 0
        fi
    else
        tired_sent=0
    fi

    sleep 20
    tick=$((tick + 1))
done

exit 0
