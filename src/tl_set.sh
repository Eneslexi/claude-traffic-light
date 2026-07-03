#!/usr/bin/env bash
# Bu oturumun durumunu + sekme ismini (aiTitle) + son araci + durum zamanini yazar.
# Kullanim: tl_set.sh working|waiting|done   (stdin: hook JSON)
# Dosya formati: 1.satir durum, 2.satir isim, 3.satir arac, 4.satir durumun basladigi epoch sn
status="$1"
dir="$HOME/.claude/traffic_lights"
mkdir -p "$dir"
payload="$(cat)"
flat="$(printf '%s' "$payload" | tr -d '\r\n')"
sid="$(printf '%s' "$flat" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -z "$sid" ] && sid="default"

# transcript yolundan sekme basligini (aiTitle) cek
name=""
tp="$(printf '%s' "$flat" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -n "$tp" ]; then
    up="$(printf '%s' "$tp" | sed 's/\\\\/\//g' | sed 's#^\([A-Za-z]\):/#/\L\1/#')"
    if [ -f "$up" ]; then
        name="$(grep '"type":"ai-title"' "$up" 2>/dev/null | tail -1 | sed -n 's/.*"aiTitle"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    fi
fi
name="${name:0:22}"   # bash substring = UTF-8 guvenli (cut -c bayt sayardi, cok-baytli harfi bolerdi)

# hangi arac calisiyor / izin istiyor (PreToolUse + PermissionRequest JSON'unda var)
tool="$(printf '%s' "$flat" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

# durum degismediyse baslangic zamanini KORU (panelde "kac dakikadir" dogru aksin)
f="$dir/$sid.txt"
now="$(date +%s)"
ts="$now"
if [ -f "$f" ]; then
    old="$(sed -n '1p' "$f" | tr -d '\r')"
    oldts="$(sed -n '4p' "$f" | tr -d '\r')"
    case "$oldts" in
        ''|*[!0-9]*) oldts="" ;;
    esac
    if [ "$old" = "$status" ] && [ -n "$oldts" ]; then ts="$oldts"; fi
fi

printf '%s\n%s\n%s\n%s' "$status" "$name" "$tool" "$ts" > "$f"
