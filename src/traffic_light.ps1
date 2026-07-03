# Claude Trafik Lambasi v2 - odak-calmayan, hover canli panel, tikla-zipla, event-driven
# Her oturum ~/.claude/traffic_lights/<session>.txt:
#   1.satir durum (working|waiting|done), 2.satir sekme ismi, 3.satir arac, 4.satir durum baslangic epoch sn
# Sol tik isiga = o durumdaki oturuma zipla (birden coksa liste). Sag tik = menu. Tekerlek = boyut.

$createdNew = $false
$script:mutex = New-Object System.Threading.Mutex($true, "Global\ClaudeTrafficLightSingleton", [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Odak calmayan, hep ustte form sinifi (WS_EX_NOACTIVATE + TOOLWINDOW)
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Windows.Forms;
public class NoActForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            return cp;
        }
    }
}
"@

# Win32: topmost itme + pencere listeleme/aktiflestirme (tikla-zipla icin)
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class TLWin {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public static void Top(IntPtr h){ SetWindowPos(h, HWND_TOPMOST, 0,0,0,0, 0x0013); }
    public static void Fg(IntPtr h){ SetForegroundWindow(h); }
    // gorunur ust-duzey pencereler: "hwnd|baslik" listesi
    public static List<string> Titles(){
        var list = new List<string>();
        EnumWindows(delegate(IntPtr h, IntPtr lp){
            if(!IsWindowVisible(h)) return true;
            int len = GetWindowTextLength(h);
            if(len == 0) return true;
            var sb = new StringBuilder(len + 2);
            GetWindowText(h, sb, sb.Capacity);
            list.Add(h.ToInt64().ToString() + "|" + sb.ToString());
            return true;
        }, IntPtr.Zero);
        return list;
    }
    // pencereyi geri yukle + one getir (AttachThreadInput = foreground kilidini asar)
    public static void Activate(long hl){
        IntPtr h = new IntPtr(hl);
        if(IsIconic(h)) ShowWindow(h, 9); // SW_RESTORE
        uint pid; uint tid = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint cur = GetCurrentThreadId();
        AttachThreadInput(cur, tid, true);
        SetForegroundWindow(h);
        AttachThreadInput(cur, tid, false);
    }
}
"@

# Dosya izleyici: polling yerine event-driven (PS scriptblock baska thread'de calisamaz -> C# bayrak)
Add-Type @"
using System.IO;
public class TLWatch {
    public static volatile bool Dirty = true;
    static FileSystemWatcher w;
    public static void Start(string dir){
        w = new FileSystemWatcher(dir, "*.txt");
        w.Changed += delegate { Dirty = true; };
        w.Created += delegate { Dirty = true; };
        w.Deleted += delegate { Dirty = true; };
        w.Renamed += delegate { Dirty = true; };
        w.EnableRaisingEvents = true;
    }
}
"@

$script:dir = Join-Path $env:USERPROFILE ".claude\traffic_lights"
if (-not (Test-Path $script:dir)) { New-Item -ItemType Directory -Path $script:dir -Force | Out-Null }
$script:posFile = Join-Path $env:USERPROFILE ".claude\traffic_light_pos.txt"
[TLWatch]::Start($script:dir)

$script:cnt = @(0, 0, 0)       # done, waiting, working (kirmizi/sari/yesil)
$script:sessAll = @()           # tum oturumlar: Status, Name, Tool, Ts
$script:prevWait = 0
$script:prevDone = 0
$script:firstTick = $true
$script:scale = 1.0
$script:hovering = $false
$script:topTick = 0
$script:vertical = $false
$script:stuck = $false          # 3dk+ sarida bekleyen var mi (beyaz halka)
$script:moved = 0               # tik ile surukleme ayrimi

# ozel ses
$script:player = $null
$wavPath = Join-Path $env:USERPROFILE ".claude\notify.wav"
if (Test-Path $wavPath) { try { $script:player = New-Object System.Media.SoundPlayer($wavPath); $script:player.Load() } catch { $script:player = $null } }
$script:playerDone = $null
$wavDonePath = Join-Path $env:USERPROFILE ".claude\done.wav"
if (Test-Path $wavDonePath) { try { $script:playerDone = New-Object System.Media.SoundPlayer($wavDonePath); $script:playerDone.Load() } catch { $script:playerDone = $null } }

$script:form = New-Object NoActForm
$script:form.FormBorderStyle = 'None'
$script:form.StartPosition = 'Manual'
$script:form.TopMost = $true
$script:form.ShowInTaskbar = $false
$script:form.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 32)
$script:form.Opacity = 0.93

function Fmt-Ago([long]$s) {
    if ($s -lt 0) { $s = 0 }
    if ($s -lt 60) { return "${s}s" }
    $m = [Math]::Floor($s / 60)
    if ($m -lt 60) { return "${m}m" }
    $h = [Math]::Floor($m / 60); $m = $m % 60
    return "${h}h${m}m"
}

# panel satirlari: sarilar ustte, sonra yesil, sonra kirmizi; canli sure ile
function Get-Rows {
    $nowE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($st in @("waiting", "working", "done")) {
        foreach ($s in @($script:sessAll | Where-Object { $_.Status -eq $st })) {
            $ago = Fmt-Ago ($nowE - $s.Ts)
            if ($st -eq "working") {
                $t = if ($s.Tool) { $s.Tool } else { "thinking" }
                $txt = "$($s.Name) - $t ($ago)"
                $ci = 2
            } elseif ($st -eq "waiting") {
                $t = if ($s.Tool) { "$($s.Tool) approval" } else { "question" }
                $txt = "$($s.Name) - $t ($ago)"
                $ci = 1
            } else {
                $txt = "$($s.Name) ($ago ago)"
                $ci = 0
            }
            $rows.Add(@{ Ci = $ci; Text = $txt })
        }
    }
    if ($rows.Count -eq 0) { $rows.Add(@{ Ci = -1; Text = "no sessions" }) }
    if ($rows.Count -gt 12) {
        $extra = $rows.Count - 11
        $rows = $rows.GetRange(0, 11)
        $rows.Add(@{ Ci = -1; Text = "+$extra more" })
    }
    return , $rows
}

# --- Bilgi paneli (odak calmayan ayri pencere, owner-drawn) ---
$script:info = New-Object NoActForm
$script:info.FormBorderStyle = 'None'
$script:info.StartPosition = 'Manual'
$script:info.TopMost = $true
$script:info.ShowInTaskbar = $false
$script:info.BackColor = [System.Drawing.Color]::FromArgb(26, 28, 38)
$script:info.Add_Paint({ param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $W = $script:info.ClientSize.Width; $H = $script:info.ClientSize.Height
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(62, 68, 90), 1)
    $g.DrawRectangle($pen, 0, 0, ($W - 1), ($H - 1)); $pen.Dispose()
    $tf = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
    $tbr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(135, 142, 162))
    $g.DrawString("CLAUDE TRAFFIC", $tf, $tbr, 16, 9); $tf.Dispose(); $tbr.Dispose()
    $rf = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $wbr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(234, 236, 242))
    $gbr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 146, 165))
    $pal = @(@(255, 66, 66), @(255, 200, 45), @(74, 224, 105))
    $y = 30
    foreach ($row in (Get-Rows)) {
        if ($row.Ci -ge 0) {
            $c = [System.Drawing.Color]::FromArgb($pal[$row.Ci][0], $pal[$row.Ci][1], $pal[$row.Ci][2])
            $db = New-Object System.Drawing.SolidBrush($c)
            $g.FillEllipse($db, 17, ($y + 5), 10, 10); $db.Dispose()
            $g.DrawString($row.Text, $rf, $wbr, 35, $y)
        } else {
            $g.DrawString($row.Text, $rf, $gbr, 35, $y)
        }
        $y += 24
    }
    $rf.Dispose(); $wbr.Dispose(); $gbr.Dispose()
})

function Show-Info {
    $rows = Get-Rows
    $rf = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $tmp = New-Object System.Drawing.Bitmap(1, 1)
    $mg = [System.Drawing.Graphics]::FromImage($tmp)
    $maxw = $mg.MeasureString("CLAUDE TRAFFIC", $rf).Width
    foreach ($row in $rows) {
        $sz = $mg.MeasureString($row.Text, $rf)
        if ($sz.Width -gt $maxw) { $maxw = $sz.Width }
    }
    $mg.Dispose(); $tmp.Dispose(); $rf.Dispose()
    $cw = [int]($maxw + 52); if ($cw -lt 170) { $cw = 170 }
    $rowsH = $rows.Count * 24
    $ch = 30 + $rowsH + 10
    $script:info.ClientSize = New-Object System.Drawing.Size($cw, $ch)
    $rad = 10; $dd = $rad * 2
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc(0, 0, $dd, $dd, 180, 90)
    $p.AddArc($cw - $dd, 0, $dd, $dd, 270, 90)
    $p.AddArc($cw - $dd, $ch - $dd, $dd, $dd, 0, 90)
    $p.AddArc(0, $ch - $dd, $dd, $dd, 90, 90)
    $p.CloseFigure()
    $script:info.Region = New-Object System.Drawing.Region($p)
    $x = $script:form.Left
    $y = $script:form.Bottom + 6
    $sa = [System.Windows.Forms.Screen]::FromControl($script:form).WorkingArea
    if (($y + $ch) -gt $sa.Bottom) { $y = $script:form.Top - $ch - 6 }
    if (($x + $cw) -gt $sa.Right) { $x = $sa.Right - $cw }
    if ($x -lt $sa.Left) { $x = $sa.Left }
    $script:info.Location = New-Object System.Drawing.Point($x, $y)
    $script:info.Invalidate()
    $script:info.Show()
    try { [TLWin]::Top($script:info.Handle) } catch { }
}

function Resize-Form {
    if ($script:vertical) { $W = [int](54 * $script:scale); $H = [int](156 * $script:scale) }
    else { $W = [int](156 * $script:scale); $H = [int](54 * $script:scale) }
    $script:form.ClientSize = New-Object System.Drawing.Size($W, $H)
    $rad = [int](16 * $script:scale); $d = $rad * 2
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($W - $d, 0, $d, $d, 270, 90)
    $p.AddArc($W - $d, $H - $d, $d, $d, 0, 90)
    $p.AddArc(0, $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $script:form.Region = New-Object System.Drawing.Region($p)
    $script:form.Invalidate()
}
function Save-Pos {
    try { "$($script:form.Left),$($script:form.Top),$([Math]::Round($script:scale,2)),$([int]$script:vertical)" | Set-Content -Path $script:posFile -Encoding ascii } catch { }
}

# konum + olcek yukle
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$placed = $false
if (Test-Path $script:posFile) {
    try {
        $p = (Get-Content $script:posFile -Raw).Trim() -split ','
        if ($p.Count -ge 3) { $script:scale = [double]$p[2] }
        if ($p.Count -ge 4) { $script:vertical = ($p[3] -eq "1") }
        Resize-Form
        if ($p.Count -ge 2) { $script:form.Left = [int]$p[0]; $script:form.Top = [int]$p[1]; $placed = $true }
    } catch { }
}
if (-not $placed) { Resize-Form; $script:form.Left = $wa.Right - $script:form.Width - 20; $script:form.Top = $wa.Top + 50 }

# --- tikla-zipla: sekme ismini pencere basliginda ara, bul, one getir ---
function Jump-Session($s) {
    $nm = ""
    if ($s -and $s.Name) { $nm = ([string]$s.Name).Trim() }
    $nm = $nm -replace ([string][char]0xFFFD), ''   # bozuk UTF-8 kalintisi
    $nm = $nm.Trim()
    if ($nm.Length -lt 2) { return }
    $keys = New-Object System.Collections.Generic.List[string]
    $keys.Add($nm.ToLowerInvariant())
    if ($nm.Length -gt 12) { $keys.Add($nm.Substring(0, 12).ToLowerInvariant()) }  # baslik kisalmis olabilir
    $myForm = [long]$script:form.Handle
    $myInfo = [long]$script:info.Handle
    foreach ($k in $keys) {
        foreach ($t in [TLWin]::Titles()) {
            $i = $t.IndexOf('|'); if ($i -lt 1) { continue }
            $title = $t.Substring($i + 1).ToLowerInvariant()
            if ($title.Contains($k)) {
                $h = [long]$t.Substring(0, $i)
                if ($h -ne $myForm -and $h -ne $myInfo) {
                    try { [TLWin]::Activate($h) } catch { }
                    return
                }
            }
        }
    }
}

function Show-SessMenu($items) {
    $m = New-Object System.Windows.Forms.ContextMenuStrip
    $nowE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    foreach ($s in $items) {
        $mi = $m.Items.Add("$($s.Name)  ($(Fmt-Ago ($nowE - $s.Ts)))")
        $mi.Tag = $s
        $mi.Add_Click({ Jump-Session $this.Tag })
    }
    $m.Add_Opened({ try { [TLWin]::Fg($this.Handle) } catch { } })
    $script:sessMenu = $m   # GC'ye kapilmasin
    $m.Show([System.Windows.Forms.Cursor]::Position)
}

function Handle-Click([int]$x, [int]$y) {
    $W = $script:form.ClientSize.Width; $H = $script:form.ClientSize.Height
    if ($script:vertical) { $idx = [int][Math]::Floor($y * 3 / $H) } else { $idx = [int][Math]::Floor($x * 3 / $W) }
    if ($idx -lt 0) { $idx = 0 }; if ($idx -gt 2) { $idx = 2 }
    $status = @("done", "waiting", "working")[$idx]
    $items = @($script:sessAll | Where-Object { $_.Status -eq $status })
    if ($items.Count -eq 1) { Jump-Session $items[0] }
    elseif ($items.Count -gt 1) { Show-SessMenu $items }
}

# surukle (tasi) + Ctrl+surukle (boyutlandir) + sol tik (zipla)
$script:drag = $false; $script:resize = $false; $script:dx = 0; $script:dy = 0
$script:startY = 0; $script:startScale = 1.0
$script:form.Add_MouseDown({
    $script:drag = $true; $script:dx = $_.X; $script:dy = $_.Y; $script:moved = 0
    $script:resize = (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -ne 0)
    $script:startY = [System.Windows.Forms.Cursor]::Position.Y
    $script:startScale = $script:scale
})
$script:form.Add_MouseUp({
    $wasDrag = ($script:moved -gt 5) -or $script:resize
    $script:drag = $false
    Save-Pos
    if (-not $wasDrag -and $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Handle-Click $_.X $_.Y }
})
$script:form.Add_MouseMove({
    if (-not $script:drag) { return }
    if ($script:resize) {
        $dyy = $script:startY - [System.Windows.Forms.Cursor]::Position.Y
        $ns = $script:startScale + ($dyy / 110.0)
        if ($ns -lt 0.6) { $ns = 0.6 }; if ($ns -gt 2.8) { $ns = 2.8 }
        $script:scale = $ns
        Resize-Form
        if ($script:hovering) { Show-Info }
    } else {
        $ddx = $_.X - $script:dx; $ddy = $_.Y - $script:dy
        $script:moved += [Math]::Abs($ddx) + [Math]::Abs($ddy)
        $script:form.Left += $ddx; $script:form.Top += $ddy
    }
})
$script:form.Add_MouseWheel({
    if ($_.Delta -gt 0) { $script:scale = [Math]::Min(2.8, $script:scale + 0.12) }
    else { $script:scale = [Math]::Max(0.6, $script:scale - 0.12) }
    Resize-Form; Save-Pos
    if ($script:hovering) { Show-Info }
})
$script:form.Add_MouseEnter({ $script:hovering = $true; Show-Info })
$script:form.Add_MouseLeave({ $script:hovering = $false; try { $script:info.Hide() } catch { } })
# NOT: cift-tik kapatma kaldirildi (sol tik artik zipla) - kapatmak icin sag tik > Close
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$script:orientItem = $menu.Items.Add($(if ($script:vertical) { "Horizontal" } else { "Vertical" }))
$script:orientItem.Add_Click({
    $script:vertical = -not $script:vertical
    Resize-Form
    $script:orientItem.Text = $(if ($script:vertical) { "Horizontal" } else { "Vertical" })
    Save-Pos
})
$miClose = $menu.Items.Add("Close")
$miClose.Add_Click({ $script:info.Hide(); $script:form.Close() })
# menu acilinca on plana al -> baska yere tiklayinca otomatik kapansin
$menu.Add_Opened({ try { [TLWin]::Fg($menu.Handle) } catch { } })
$script:form.ContextMenuStrip = $menu

$script:form.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $sc = $script:scale
    if ($script:vertical) { $cxBase = @(27, 27, 27); $cyBase = @(34, 78, 122) }
    else { $cxBase = @(34, 78, 122); $cyBase = @(27, 27, 27) }
    $r = 15 * $sc
    $grBase = @(6, 10, 14)
    $glow = @(70, 45, 24)
    $bright = @(
        [System.Drawing.Color]::FromArgb(255, 66, 66),
        [System.Drawing.Color]::FromArgb(255, 200, 45),
        [System.Drawing.Color]::FromArgb(74, 224, 105)
    )
    $rgb = @(@(255, 66, 66), @(255, 200, 45), @(74, 224, 105))
    $dim = @(
        [System.Drawing.Color]::FromArgb(60, 30, 30),
        [System.Drawing.Color]::FromArgb(60, 54, 22),
        [System.Drawing.Color]::FromArgb(26, 56, 34)
    )
    $fsize = 11 * $sc; if ($fsize -lt 6) { $fsize = 6 }
    $font = New-Object System.Drawing.Font("Segoe UI", $fsize, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    for ($i = 0; $i -lt 3; $i++) {
        $cx = $cxBase[$i] * $sc
        $cy = $cyBase[$i] * $sc
        $on = $script:cnt[$i] -gt 0
        if ($on) {
            for ($k = 2; $k -ge 0; $k--) {
                $rr = $r + ($grBase[$k] * $sc)
                $c = [System.Drawing.Color]::FromArgb($glow[$k], $rgb[$i][0], $rgb[$i][1], $rgb[$i][2])
                $b = New-Object System.Drawing.SolidBrush($c)
                $g.FillEllipse($b, ($cx - $rr), ($cy - $rr), (2 * $rr), (2 * $rr)); $b.Dispose()
            }
            $b = New-Object System.Drawing.SolidBrush($bright[$i])
            $g.FillEllipse($b, ($cx - $r), ($cy - $r), (2 * $r), (2 * $r)); $b.Dispose()
        } else {
            $b = New-Object System.Drawing.SolidBrush($dim[$i])
            $g.FillEllipse($b, ($cx - $r), ($cy - $r), (2 * $r), (2 * $r)); $b.Dispose()
        }
        # 3dk+ bekleyen soru var -> sarinin etrafina beyaz halka (yanip sonmez, sabit uyari)
        if ($i -eq 1 -and $on -and $script:stuck) {
            $pw = 2 * $sc; if ($pw -lt 1) { $pw = 1 }
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 255, 255, 255), $pw)
            $rr2 = $r + (5 * $sc)
            $g.DrawEllipse($pen, ($cx - $rr2), ($cy - $rr2), (2 * $rr2), (2 * $rr2)); $pen.Dispose()
        }
        if ($on) {
            $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 15, 15, 20))
            $rf = New-Object System.Drawing.RectangleF(($cx - $r), ($cy - $r), (2 * $r), (2 * $r))
            $g.DrawString([string]$script:cnt[$i], $font, $tb, $rf, $sf); $tb.Dispose()
        }
    }
    $font.Dispose()
})

# durum dosyalarini oku (sadece degisiklik oldugunda cagrilir - FileSystemWatcher)
function Scan-Sessions {
    $list = New-Object System.Collections.Generic.List[object]
    $cutoff = (Get-Date).AddHours(-6)
    try {
        Get-ChildItem -Path $script:dir -Filter *.txt -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.LastWriteTime -lt $cutoff) { return }
            $st = ""; $nm = ""; $tl = ""; $ts = [long]0
            try {
                $raw = Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($raw) {
                    $parts = $raw -split "`n"
                    $st = $parts[0].Trim()
                    if ($parts.Count -gt 1) { $nm = $parts[1].Trim() }
                    if ($parts.Count -gt 2) { $tl = $parts[2].Trim() }
                    if ($parts.Count -gt 3) {
                        $tsRaw = $parts[3].Trim()
                        if ($tsRaw -match '^\d+$') { $ts = [long]$tsRaw }
                    }
                }
            } catch { }
            if ($st -ne "working" -and $st -ne "waiting" -and $st -ne "done") { return }
            if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $_.BaseName.Substring(0, [Math]::Min(6, $_.BaseName.Length)) }
            if ($ts -le 0) { $ts = [DateTimeOffset]::new([datetime]::SpecifyKind($_.LastWriteTimeUtc, [System.DateTimeKind]::Utc)).ToUnixTimeSeconds() }
            $list.Add([pscustomobject]@{ Status = $st; Name = $nm; Tool = $tl; Ts = $ts })
        }
    } catch { }
    $script:sessAll = $list
    $d = 0; $w = 0; $k = 0
    foreach ($s in $list) {
        switch ($s.Status) { "working" { $k++ } "waiting" { $w++ } "done" { $d++ } }
    }
    $changed = ($script:cnt[0] -ne $d) -or ($script:cnt[1] -ne $w) -or ($script:cnt[2] -ne $k)
    if ($changed) { $script:cnt = @($d, $w, $k); $script:form.Invalidate() }

    # yeni soru geldi -> cingirak
    if (-not $script:firstTick -and $w -gt $script:prevWait) {
        if ($script:player) { try { $script:player.Play() } catch { } }
        else { try { [System.Media.SystemSounds]::Exclamation.Play() } catch { } }
    }
    # is bitti (kirmizi artti) -> ding-dong (soru sesiyle cakisirsa soru sesi oncelikli)
    elseif (-not $script:firstTick -and $d -gt $script:prevDone) {
        if ($script:playerDone) { try { $script:playerDone.Play() } catch { } }
        else { try { [System.Media.SystemSounds]::Asterisk.Play() } catch { } }
    }
    $script:prevWait = $w
    $script:prevDone = $d
    $script:firstTick = $false
    if ($script:hovering) { Show-Info }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    $script:topTick++
    # her ~1sn: en uste it (baska uygulamaya gecince arkada kalmasin)
    if ($script:topTick % 4 -eq 0) {
        try { [TLWin]::Top($script:form.Handle) } catch { }
        if ($script:hovering) { try { [TLWin]::Top($script:info.Handle) } catch { } }
    }
    # dosya degisti (FSW bayragi) veya 5sn'lik güvenlik taramasi
    if ([TLWatch]::Dirty -or ($script:topTick % 20 -eq 0)) {
        [TLWatch]::Dirty = $false
        Scan-Sessions
    }
    # her ~1sn: takilma kontrolu + hover panelinde canli sureler
    if ($script:topTick % 4 -eq 0) {
        $nowE = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $stk = $false
        foreach ($s in $script:sessAll) {
            if ($s.Status -eq "waiting" -and (($nowE - $s.Ts) -gt 180)) { $stk = $true; break }
        }
        if ($stk -ne $script:stuck) { $script:stuck = $stk; $script:form.Invalidate() }
        if ($script:hovering) { $script:info.Invalidate() }
    }
})
$timer.Start()

[System.Windows.Forms.Application]::Run($script:form)
$script:mutex.ReleaseMutex()
