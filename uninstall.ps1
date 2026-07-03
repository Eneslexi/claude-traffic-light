# Claude Traffic Light - uninstaller
# Removes our hooks from settings.json (leaves your other hooks intact),
# deletes the runtime files and the desktop shortcut.

$ErrorActionPreference = 'Stop'
Write-Host ""
Write-Host "  Claude Traffic Light - uninstalling..." -ForegroundColor Cyan

$claude = Join-Path $env:USERPROFILE '.claude'

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
if (Test-Path $settingsPath) {
    try {
        $settings = ConvertTo-Hashtable (Get-Content $settingsPath -Raw | ConvertFrom-Json)
        if ($settings.ContainsKey('hooks')) {
            foreach ($event in @($settings['hooks'].Keys)) {
                $kept = @()
                foreach ($grp in @($settings['hooks'][$event])) {
                    $ours = $false
                    if ($grp.hooks) { foreach ($h in @($grp.hooks)) { if ($h.command -match 'tl_set\.sh|tl_start\.sh|tl_del\.sh') { $ours = $true } } }
                    if (-not $ours) { $kept += ,$grp }
                }
                if ($kept.Count -gt 0) { $settings['hooks'][$event] = $kept } else { $settings['hooks'].Remove($event) }
            }
            $json = $settings | ConvertTo-Json -Depth 100
            [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "    hooks removed from settings.json"
        }
    } catch { Write-Host "    (could not edit settings.json)" }
}

# stop the running light (mutex will free), then delete files
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq '' } | Out-Null
foreach ($f in 'traffic_light.ps1','launch.vbs','tl_start.sh','tl_set.sh','tl_del.sh','notify.wav','done.wav','traffic_light.ico','traffic_light_pos.txt') {
    $p = Join-Path $claude $f
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
}
$tl = Join-Path $claude 'traffic_lights'
if (Test-Path $tl) { Remove-Item $tl -Recurse -Force -ErrorAction SilentlyContinue }

$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude Traffic Light.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }

Write-Host "  Done. (Close the light window if it is still open.)" -ForegroundColor Green
Write-Host ""
