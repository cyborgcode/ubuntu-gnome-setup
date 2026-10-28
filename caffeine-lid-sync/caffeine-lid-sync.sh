#!/usr/bin/env bash
# Mirrors the GNOME Caffeine extension's on/off state into a systemd-logind inhibitor
# covering the lid switch, idle detection, and suspend/hibernate itself — so the
# machine stays fully awake (lid closed or open, on AC or battery) while Caffeine
# is on, not just protected from the lid-close action specifically.
set -u

KEY="/org/gnome/shell/extensions/caffeine/user-enabled"
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/caffeine-lid-sync.pid"
POLL_INTERVAL=2

start_inhibit() {
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        return
    fi
    systemd-inhibit \
        --what=handle-lid-switch:sleep:idle \
        --who="caffeine-lid-sync" \
        --why="Caffeine extension is active" \
        sleep infinity &
    disown
    echo $! > "$PIDFILE"
    logger -t caffeine-lid-sync "Caffeine ON -> lid-switch/sleep/idle inhibited (pid $!)"
}

stop_inhibit() {
    if [[ -f "$PIDFILE" ]]; then
        pid="$(cat "$PIDFILE" 2>/dev/null)"
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
        rm -f "$PIDFILE"
        logger -t caffeine-lid-sync "Caffeine OFF -> inhibitor released"
    fi
}

cleanup() {
    stop_inhibit
    exit 0
}
trap cleanup TERM INT

last=""
while true; do
    value="$(dconf read "$KEY" 2>/dev/null)"
    if [[ "$value" != "$last" ]]; then
        if [[ "$value" == "true" ]]; then
            start_inhibit
        else
            stop_inhibit
        fi
        last="$value"
    fi
    sleep "$POLL_INTERVAL"
done
