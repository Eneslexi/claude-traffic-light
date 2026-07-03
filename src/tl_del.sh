#!/usr/bin/env bash
# Oturum kapaninca bu oturumun durum dosyasini siler.
dir="$HOME/.claude/traffic_lights"
sid="$(cat | tr -d '\r\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -z "$sid" ] && exit 0
rm -f "$dir/$sid.txt"
