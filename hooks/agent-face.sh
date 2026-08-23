#!/bin/bash
# agent-face.sh — сигнал статуса агента терминалу Ghostty через фон (OSC 11)
# Состояния: run|done|attn|work|dizzy|helpers|fail|tired|skull|reset
# Хук-процесс без controlling tty — tty ищем подъёмом по цепочке родителей.
# После каждой отправки цвета перезапускается сторож agent-face-watch.sh
# (краш-детект + автосон + сброс по нажатию клавиши).

# Пауза до установки шейдера-перекрасчика (иначе фон видимо мигает).
# Включить обратно: удалить файл ~/.claude/hooks/agent-face.disabled
[ -e "$HOME/.claude/hooks/agent-face.disabled" ] && exit 0

# Сигналы = НЕВИДИМЫЕ сдвиги +3/255 от фона темы #282c34 (40,44,52).
# Ниже порога восприятия даже на ярких wide-gamut дисплеях; шейдер матчит точно.
COLOR_RUN="#2B2C34"
COLOR_DONE="#282C37"
COLOR_ATTN="#2B2F34"
COLOR_WORK="#282F34"
COLOR_DIZZY="#2B2C37"
COLOR_SLEEP="#282F37"
COLOR_HELPERS="#2B2F37"
# v6: новые состояния на +6/255 (вдвое дальше от соседей -> запас на профильный сдвиг).
COLOR_FAIL="#2E2C34"
COLOR_TIRED="#283234"
COLOR_SKULL="#282C3A"

# Файл-таймер сторожа: "<unix ts> <state>", отдельно на КАЖДЫЙ tty (иначе параллельные
# сессии Саши затирали бы друг другу таймер простоя/усталости одним общим файлом).
STATE_FILE_DIR="$HOME/.claude/hooks"

# Возвращает пару "tty pid" — pid предка, на котором tty был найден
# (нужен сторожу как ANCHOR_PID для краш-детекта).
find_tty() {
    local pid="$1"
    local i=0
    local tty
    while [ "$i" -lt 15 ]; do
        if [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; then
            return 1
        fi
        tty=$(lsof -p "$pid" -a -d 0,1,2 2>/dev/null | grep -Eo '/dev/ttys[0-9]+' | head -1)
        if [ -n "$tty" ]; then
            printf '%s %s' "$tty" "$pid"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        i=$((i + 1))
    done
    return 1
}

state="$1"
# pre = PreToolUse: по tool_name из stdin-JSON различаем субагентов (helpers) и остальные тулы (work)
if [ "$state" = "pre" ]; then
    state="work"
    if [ ! -t 0 ]; then
        hook_json=$(cat 2>/dev/null)
        case "$hook_json" in
            *'"tool_name":"Agent"'*|*'"tool_name":"Task"'*|*'"tool_name":"Workflow"'*) state="helpers" ;;
        esac
    fi
fi

# fail = PostToolUseFailure(Bash): пропускаем, если это была отмена (Ctrl-C), не реальная ошибка.
if [ "$state" = "fail" ] && [ ! -t 0 ]; then
    hook_json=$(cat 2>/dev/null)
    case "$hook_json" in
        *'"is_interrupt":true'*) exit 0 ;;
    esac
fi

case "$state" in
    run)     color="$COLOR_RUN" ;;
    done)    color="$COLOR_DONE" ;;
    attn)    color="$COLOR_ATTN" ;;
    work)    color="$COLOR_WORK" ;;
    dizzy)   color="$COLOR_DIZZY" ;;
    sleep)   color="$COLOR_SLEEP" ;;
    helpers) color="$COLOR_HELPERS" ;;
    fail)    color="$COLOR_FAIL" ;;
    tired)   color="$COLOR_TIRED" ;;
    skull)   color="$COLOR_SKULL" ;;
    reset)   color="" ;;
    *) exit 0 ;;
esac

tty_info=$(find_tty "$$")
[ -n "$tty_info" ] || exit 0
tty_path=${tty_info% *}
anchor_pid=${tty_info#* }
state_file="$STATE_FILE_DIR/.agent-face-state-$(basename "$tty_path")"

if [ "$state" = "reset" ]; then
    printf '%s idle\n' "$(date +%s)" > "$state_file" 2>/dev/null
    pkill -f "agent-face-watch.sh $tty_path" 2>/dev/null
    printf '\033]111\007' > "$tty_path" 2>/dev/null
else
    printf '%s %s\n' "$(date +%s)" "$state" > "$state_file" 2>/dev/null
    if printf '\033]11;%s\007' "$color" > "$tty_path" 2>/dev/null; then
        pkill -f "agent-face-watch.sh $tty_path" 2>/dev/null
        if [ "$state" = "fail" ]; then
            # FAIL — гримаса на 1.5-2с, дальше сама возвращается в work (без ожидания следующего хука).
            revert_cmd="sleep 2; printf '\033]11;%s\007' '$COLOR_WORK' > '$tty_path' 2>/dev/null; printf '%s work\n' \"\$(date +%s)\" > '$state_file' 2>/dev/null; nohup bash $HOME/.claude/hooks/agent-face-watch.sh '$tty_path' '$anchor_pid' work >/dev/null 2>&1 </dev/null & disown 2>/dev/null"
            (nohup bash -c "$revert_cmd" >/dev/null 2>&1 </dev/null & disown 2>/dev/null)
        else
            (nohup bash $HOME/.claude/hooks/agent-face-watch.sh "$tty_path" "$anchor_pid" "$state" >/dev/null 2>&1 </dev/null & disown 2>/dev/null)
        fi
    fi
fi

exit 0
