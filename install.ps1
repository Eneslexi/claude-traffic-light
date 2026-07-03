# Claude Traffic Light - installer
# Copies files into ~/.claude, merges hooks into settings.json (non-destructive),
# creates a desktop shortcut, and launches the light. Safe to re-run.

$ErrorActionPreference = 'Stop'
Write-Host ""
Write-Host "  Claude Traffic Light - installing..." -ForegroundColor Cyan
Write-Host ""

$claude = Join-Path $env:USERPROFILE '.claude'
$src    = Join-Path $PSScriptRoot 'src'
New-Item -ItemType Directory -Force -Path $claude | Out-Null

# --- 1. copy runtime files -------------------------------------------------
$files = 'traffic_light.ps1','launch.vbs','tl_start.sh','tl_set.sh','tl_del.sh','notify.wav','done.wav','traffic_light.ico'
foreach ($f in $files) {
    $s = Join-Path $src $f
    if (Test-Path $s) { Copy-Item $s (Join-Path $claude $f) -Force; Write-Host "    copied  $f" }
}

# --- 2. merge hooks into settings.json (keeps your existing hooks) ---------
function ConvertTo-Hashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
        $arr = @(); foreach ($i in $obj) { $arr += ,(ConvertTo-Hashtable $i) }; return ,$arr
    }
    if ($obj -is [PSCustomObject]) {
        $h = @{}; foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }; return $h
    }
    return $obj
}

$settingsPath = Join-Path $claude 'settings.json'
$settings = @{}
if (Test-Path $settingsPath) {
    try { $settings = ConvertTo-Hashtable (Get-Content $settingsPath -Raw | ConvertFrom-Json) } catch { $settings = @{} }
}
if ($null -eq $settings) { $settings = @{} }
if (-not $settings.ContainsKey('hooks')) { $settings['hooks'] = @{} }

$def = [ordered]@{
    SessionStart      = @{ cmd = 'bash "$HOME/.claude/tl_start.sh"'; async = $true }
    UserPromptSubmit  = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" working' }
    PreToolUse        = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" working' }
    Elicitation       = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" waiting' }
    ElicitationResult = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" working' }
    PermissionRequest = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" waiting' }
    PermissionDenied  = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" working' }
    Stop              = @{ cmd = 'bash "$HOME/.claude/tl_set.sh" done' }
    SessionEnd        = @{ cmd = 'bash "$HOME/.claude/tl_del.sh"' }
}

foreach ($event in $def.Keys) {
    $hookObj = @{ type = 'command'; command = $def[$event].cmd }
    if ($def[$event].async) { $hookObj['async'] = $true }
    $entry = @{ hooks = @($hookObj) }

    $kept = @()
    if ($settings['hooks'].ContainsKey($event) -and $settings['hooks'][$event]) {
        foreach ($grp in @($settings['hooks'][$event])) {
            $ours = $false
            if ($grp.hooks) { foreach ($h in @($grp.hooks)) { if ($h.command -match 'tl_set\.sh|tl_start\.sh|tl_del\.sh') { $ours = $true } } }
            if (-not $ours) { $kept += ,$grp }
        }
    }
    $kept += ,$entry
    $settings['hooks'][$event] = $kept
}

$json = $settings | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "    hooks merged into settings.json"

# --- 3. desktop shortcut ---------------------------------------------------
try {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude Traffic Light.lnk'
    $ws  = New-Object -ComObject WScript.Shell
    $sc  = $ws.CreateShortcut($lnk)
    $sc.TargetPath = 'wscript.exe'
    $sc.Arguments  = '"' + (Join-Path $claude 'launch.vbs') + '"'
    $ico = Join-Path $claude 'traffic_light.ico'
    if (Test-Path $ico) { $sc.IconLocation = $ico }
    $sc.Save()
    Write-Host "    desktop shortcut created"
} catch { Write-Host "    (desktop shortcut skipped)" }

# --- 4. launch now ---------------------------------------------------------
Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $claude 'launch.vbs') + '"')

Write-Host ""
Write-Host "  Done. The light is running now and will auto-start with every Claude Code session." -ForegroundColor Green
Write-Host "  Drag to move | scroll or Ctrl+drag to resize | right-click for Vertical/Close | double-click to close." -ForegroundColor DarkGray
Write-Host ""
