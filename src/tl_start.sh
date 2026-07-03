#!/usr/bin/env bash
# Oturum baslayinca: durum+isim yaz (tl_set) + lambayi baslat (mutex tek kopya).
payload="$(cat)"
printf '%s' "$payload" | bash "$HOME/.claude/tl_set.sh" working
win_vbs="$(cygpath -w "$HOME/.claude/launch.vbs" 2>/dev/null)"
[ -z "$win_vbs" ] && win_vbs="$USERPROFILE\\.claude\\launch.vbs"
wscript "$win_vbs" >/dev/null 2>&1 &
