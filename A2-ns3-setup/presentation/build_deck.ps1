param([string]$Repo = "C:\Users\pj02d\Documents\GitHub\petrajoyd\MWN-2026-M11502803-Petrajoy-Davidson")
$ErrorActionPreference = "Stop"
$A2 = Join-Path $Repo "A2-ns3-setup"
$Res = Join-Path $A2 "results"
$OutDir = Join-Path $A2 "presentation"
$Out = Join-Path $OutDir "A2-ns3-setup-traffic-model.pptx"

# ---------- palette (hex) ----------
$INK = "13293D"; $BLUE = "2A78D6"; $ORANGE = "EB6834"; $RED = "C0392B"; $GREEN = "1E7B34"
$MUTED = "52514E"; $TINT = "EEF2F6"; $WHITE = "FFFFFF"; $LIGHT = "C9D6E3"; $REDTINT = "FBE7E4"; $BLUETINT = "E3EEFB"; $ORTINT = "FDEBE3"
$HEAD = "Cambria"; $BODY = "Calibri"
$TOTAL = 10

function RGB([string]$hex) { $r = [Convert]::ToInt32($hex.Substring(0,2),16); $g = [Convert]::ToInt32($hex.Substring(2,2),16); $b = [Convert]::ToInt32($hex.Substring(4,2),16); return $r + 256*$g + 65536*$b }

function Nb([string]$x) {
    # keep numbers with their units and digit groups on one line (non-breaking spaces)
    $nb = [string][char]160
    $x = $x -replace '(\d) (?=(%|kB|kbit|ms|MHz|Mbps|GHz|B\b|fps|min\b|s\b|UEs\b))', ('$1' + $nb)
    $x = $x -replace '(\d) (\d{3})', ('$1' + $nb + '$2')
    $x = $x -replace '\+/- ', ('+/-' + $nb)
    $x = $x -replace '(\d+) / (\d+)', ('$1' + $nb + '/' + $nb + '$2')
    return $x
}

function T($slide, [string]$text, $l, $t, $w, $h, $size = 16, $color = $INK, $bold = $false, $font = $BODY, $align = 1, $name = $null) {
    $text = Nb $text
    $s = $slide.Shapes.AddTextbox(1, $l, $t, $w, $h)
    $tf = $s.TextFrame; $tf.WordWrap = -1; $tf.AutoSize = 0
    $tf.MarginLeft = 0; $tf.MarginRight = 0; $tf.MarginTop = 0; $tf.MarginBottom = 0
    $tr = $tf.TextRange; $tr.Text = $text
    $tr.Font.Name = $font; $tr.Font.Size = $size; $tr.Font.Bold = [int]$bold; $tr.Font.Color.RGB = (RGB $color)
    $tr.ParagraphFormat.Alignment = $align
    if ($name) { $s.Name = $name }
    return $s
}

function Box($slide, $l, $t, $w, $h, $fill, $rounded = $true, $name = $null) {
    $type = if ($rounded) { 5 } else { 1 }
    $s = $slide.Shapes.AddShape($type, $l, $t, $w, $h)
    if ($rounded) { $s.Adjustments.Item(1) = 0.08 }
    $s.Fill.ForeColor.RGB = (RGB $fill); $s.Line.Visible = 0; $s.Shadow.Visible = 0
    $s.TextFrame.TextRange.Text = ""
    if ($name) { $s.Name = $name }
    return $s
}

function Circle($slide, $l, $t, $d, $fill, [string]$label, $size = 16) {
    $s = $slide.Shapes.AddShape(9, $l, $t, $d, $d)
    $s.Fill.ForeColor.RGB = (RGB $fill); $s.Line.Visible = 0; $s.Shadow.Visible = 0
    $tf = $s.TextFrame; $tf.MarginLeft = 0; $tf.MarginRight = 0; $tf.MarginTop = 0; $tf.MarginBottom = 0
    $tr = $tf.TextRange; $tr.Text = $label; $tr.Font.Name = $BODY; $tr.Font.Size = $size; $tr.Font.Bold = 1
    $tr.Font.Color.RGB = (RGB $WHITE); $tr.ParagraphFormat.Alignment = 2
    $tf.VerticalAnchor = 3
    return $s
}

function Arrow($slide, $l, $t, $w, $h, $color = $MUTED) {
    $s = $slide.Shapes.AddShape(33, $l, $t, $w, $h)
    $s.Fill.ForeColor.RGB = (RGB $color); $s.Line.Visible = 0; $s.Shadow.Visible = 0
    return $s
}

function Title($slide, [string]$text) { T $slide $text 40 26 880 48 30 $INK $true $HEAD 1 "Title" | Out-Null }

function Footer($slide, $n) {
    T $slide "Petrajoy Davidson  |  A2: ns-3 Setup & Traffic Model" 40 508 500 16 10 $MUTED | Out-Null
    T $slide "$n / $TOTAL" 820 508 100 16 10 $MUTED $false $BODY 3 | Out-Null
}

function Bg($slide, $hex) { $slide.FollowMasterBackground = 0; $slide.Background.Fill.Solid(); $slide.Background.Fill.ForeColor.RGB = (RGB $hex) }

function Pic($slide, $path, $l, $t, $w, $h) {
    $s = $slide.Shapes.AddPicture($path, 0, -1, $l, $t, $w, $h)
    return $s
}

function Table($slide, $rows, $l, $t, $w, $h, $colW, $size = 13) {
    $nr = $rows.Count; $nc = $rows[0].Count
    $shape = $slide.Shapes.AddTable($nr, $nc, $l, $t, $w, $h)
    $tbl = $shape.Table
    $tbl.ApplyStyle("{2D5ABB26-0587-4C30-8999-92F81FD0307C}")  # No Style, No Grid
    for ($c = 1; $c -le $nc; $c++) { $tbl.Columns.Item($c).Width = $colW[$c-1] }
    for ($r = 1; $r -le $nr; $r++) {
        for ($c = 1; $c -le $nc; $c++) {
            $cell = $tbl.Cell($r, $c)
            $tf = $cell.Shape.TextFrame
            $tf.MarginLeft = 6; $tf.MarginRight = 6; $tf.MarginTop = 4; $tf.MarginBottom = 4
            $tr = $tf.TextRange; $tr.Text = (Nb ([string]$rows[$r-1][$c-1]))
            $tr.Font.Name = $BODY; $tr.Font.Size = $size
            if ($r -eq 1) {
                $tr.Font.Bold = 1; $tr.Font.Color.RGB = (RGB $WHITE)
                $cell.Shape.Fill.Visible = -1; $cell.Shape.Fill.Solid(); $cell.Shape.Fill.ForeColor.RGB = (RGB $INK)
            } else {
                $tr.Font.Color.RGB = (RGB $INK)
                $cell.Shape.Fill.Visible = -1; $cell.Shape.Fill.Solid()
                $cell.Shape.Fill.ForeColor.RGB = (RGB $(if ($r % 2 -eq 0) { $WHITE } else { $TINT }))
            }
        }
    }
    return $shape
}

# speaker notes from script.md: "## N. Title (m:ss)" sections
$script = Get-Content (Join-Path $OutDir "script.md") -Raw -Encoding UTF8
$notes = @{}
foreach ($m in [regex]::Matches($script, '(?ms)^## (\d+)\. [^\r\n]*\r?\n(.*?)(?=^## \d+\. |\z)')) {
    $notes[[int]$m.Groups[1].Value] = ($m.Groups[2].Value.Trim() -replace '\r?\n\r?\n', "`r`r" -replace '\r?\n', ' ')
}
function Notes($slide, $n) { $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $notes[$n] }

# ---------- build ----------
$app = New-Object -ComObject PowerPoint.Application
$pres = $app.Presentations.Add(0)
$pres.PageSetup.SlideWidth = 960; $pres.PageSetup.SlideHeight = 540

# ===== 1. Title (dark) =====
$s = $pres.Slides.Add(1, 12); Bg $s $INK
T $s "MULTIMEDIA WIRELESS NETWORKS  |  A2" 60 96 840 20 14 $ORANGE $true | Out-Null
T $s "An intent can fit and still break a slice" 60 124 840 110 42 $WHITE $true $HEAD | Out-Null
T $s "ns-3.48 + 5G-LENA setup, a 3GPP TR 26.926 XR video traffic model, and a first intent-driven slicing scenario" 60 200 780 56 18 $LIGHT | Out-Null
# carrier motif: 100 MHz split 90 / 10
Box $s 60 290 756 44 $BLUE $true "SliceA" | Out-Null
Box $s 822 290 78 44 $ORANGE $true "SliceB" | Out-Null
T $s "slice A  90 %" 76 303 300 20 15 $WHITE $true | Out-Null
T $s "B 10 %" 822 303 78 20 13 $WHITE $true $BODY 2 | Out-Null
T $s "one 100 MHz carrier, split by an intent" 60 340 400 18 12 $LIGHT | Out-Null
T $s "Petrajoy Davidson  |  M11502803  |  Advanced path: IBN for O-RAN slicing  |  2026/10/20" 60 470 840 20 14 $LIGHT | Out-Null
Notes $s 1

# ===== 2. Problem =====
$s = $pres.Slides.Add(2, 12); Bg $s $WHITE
Title $s "Does `"it fits`" mean `"it is safe`"?"
$labels = @(
    @("1  INTENT", "`"Give the video slice 90 % of the carrier`"", $TINT, $INK),
    @("2  CAPACITY CHECK", "Shares add up to 100 % and every slice keeps some RBs:  ACCEPT", $TINT, $INK),
    @("3  ENACT", "Bandwidth parts reconfigured: 90 MHz / 10 MHz", $TINT, $INK),
    @("4  SLICE B QoS", "Still within its SLA?", $ORTINT, $ORANGE)
)
$x = 40; $bw = 196; $gap = 32
for ($i = 0; $i -lt 4; $i++) {
    $l = $labels[$i]
    Box $s $x 120 $bw 160 $l[2] | Out-Null
    T $s $l[0] ($x + 16) 138 ($bw - 32) 20 13 $(if ($i -eq 3) { $ORANGE } else { $BLUE }) $true | Out-Null
    T $s $l[1] ($x + 16) 166 ($bw - 32) 100 17 $INK $false | Out-Null
    if ($i -lt 3) { Arrow $s ($x + $bw + 6) 189 20 22 | Out-Null } else { T $s "?" ($x + 16) 206 ($bw - 32) 60 48 $ORANGE $true $HEAD | Out-Null }
    $x += $bw + $gap
}
T $s "No human in the loop: steps 1 to 3 run automatically." 40 310 880 24 16 $MUTED | Out-Null
T $s "Today's feasibility check stops at step 2. In A2 I built this whole loop in ns-3, so step 4 is measured, not assumed." 40 348 880 60 20 $INK $true | Out-Null
Footer $s 2; Notes $s 2

# ===== 3. Setup and what broke =====
$s = $pres.Slides.Add(3, 12); Bg $s $WHITE
Title $s "Setup: ns-3.48 + 5G-LENA v5.1 on my lab VM"
Box $s 40 92 330 396 $TINT | Out-Null
T $s "PLATFORM" 60 110 290 18 13 $BLUE $true | Out-Null
T $s ("ns-3.48  +  5G-LENA 5g-lena-v5.1.y`r" + "Ubuntu 22.04.4 VM, 8 vCPU, 16 GiB`r" + "g++ 11.4  |  CMake 3.31.6  |  Python 3.10`r" + "examples + tests, -j4") 60 136 290 120 15 $INK | Out-Null
T $s "53 min" 60 290 290 70 54 $INK $true $HEAD | Out-Null
T $s "full build, 2 389 targets; my scenario then compiled first time" 60 362 280 50 14 $MUTED | Out-Null
T $s "WHAT BROKE" 400 96 520 18 13 $ORANGE $true | Out-Null
$broke = @(
    @("Refused to run as root", "I cloned in a root shell; moved the tree to user joy"),
    @("CMake 3.22, but 3.25 required", "user-level CMake 3.31.6 from pip, nothing else on the VM changed"),
    @("README install commands out of date", "followed the compatibility table: v5.1 with ns-3.48"),
    @("Wireshark showed my video as `"TAPA`"", "UDP port 5000 belongs to that dissector; disabled it")
)
$y = 124
for ($i = 0; $i -lt 4; $i++) {
    Circle $s 400 $y 34 $ORANGE ([string]($i + 1)) | Out-Null
    T $s $broke[$i][0] 448 ($y - 1) 470 22 17 $INK $true | Out-Null
    T $s $broke[$i][1] 448 ($y + 22) 470 40 14 $MUTED | Out-Null
    $y += 92
}
Footer $s 3; Notes $s 3

# ===== 4. 3GPP model =====
$s = $pres.Slides.Add(4, 12); Bg $s $WHITE
Title $s "The 3GPP XR video model (TR 26.926)"
$rows = @(
    @("Parameter", "Model"),
    @("Frame rate F", "60 fps"),
    @("Data rate R", "30 Mbps per UE"),
    @("Frame size", "truncated Gaussian: mean R/(8F), STD 10.5 %, range 50 to 150 %"),
    @("Frame jitter", "truncated Gaussian: mean 0, STD 2 ms, range -4 to +4 ms"),
    @("Arrival of frame k", "t = k/F + J (jitter around a fixed grid)"),
    @("Packets (my choice)", "frame cut into <= 1 400 B UDP payloads, back to back")
)
Table $s $rows 40 96 520 300 @(150, 370) 14 | Out-Null
$tiles = @(@("62.5 kB", "mean frame size"), @("16.7 ms", "frame period"), @("+/- 4 ms", "jitter bound"), @("~45", "packets per frame"))
for ($i = 0; $i -lt 4; $i++) {
    $tx = 590 + ($i % 2) * 170; $ty = 96 + [math]::Floor($i / 2) * 150
    Box $s $tx $ty 155 134 $BLUETINT | Out-Null
    T $s $tiles[$i][0] ($tx + 12) ($ty + 26) 131 50 30 $INK $true $HEAD 2 | Out-Null
    T $s $tiles[$i][1] ($tx + 12) ($ty + 84) 131 36 14 $MUTED $false $BODY 2 | Out-Null
}
T $s "26.926 is a Technical Report (TR), not a TS. Its video model is the RAN1 XR model of TR 38.838, Sec. 5.1.1, Table 5.1.1.1-1." 40 440 880 40 13 $MUTED | Out-Null
Footer $s 4; Notes $s 4

# ===== 5. Built-in vs mine =====
$s = $pres.Slides.Add(5, 12); Bg $s $WHITE
Title $s "Why I did not use the built-in generator"
Box $s 40 96 250 300 $ORTINT | Out-Null
T $s "FRAME SIZE SPREAD (STD)" 58 112 214 18 12 $ORANGE $true | Out-Null
T $s "81 B" 58 140 214 60 46 $ORANGE $true $HEAD | Out-Null
T $s "5G-LENA built-in" 58 202 214 20 14 $MUTED | Out-Null
T $s "6 563 B" 58 246 214 60 46 $INK $true $HEAD | Out-Null
T $s "3GPP model (10.5 % of 62.5 kB)" 58 308 214 40 14 $MUTED | Out-Null
$rows = @(
    @("", "3GPP TR 26.926 / 38.838", "5G-LENA v5.1 built-in"),
    @("Frame size spread", "STD = 10.5 % of the mean", "variance = 0.105 x mean, so STD ~ 81 B"),
    @("Jitter range", "-4 to +4 ms", "-2 to +2 ms"),
    @("Jitter type", "around a fixed grid", "added to every gap (random walk)"),
    @("Jitter resolution", "continuous", "whole milliseconds")
)
Table $s $rows 316 96 604 240 @(150, 207, 247) 14 | Out-Null
T $s "So I wrote XrVideoApp: rejection-sampled truncated Gaussians, variance = STD squared, jitter on a fixed grid. AI-assisted; every parameter checked against the table." 316 356 604 60 15 $INK $true | Out-Null
T $s "Source: contrib/nr/utils/traffic-generators/model/traffic-generator-3gpp-generic-video.cc (5g-lena-v5.1.y), lines 262, 299, 303" 40 440 880 36 12 $MUTED | Out-Null
Footer $s 5; Notes $s 5

# ===== 6. Scenario =====
$s = $pres.Slides.Add(6, 12); Bg $s $WHITE
Title $s "The scenario: an intent loop in ns-3"
$steps = @(@("Intent JSON", "share, UEs, traffic, slice B SLA"), @("intent_enact.py", "capacity-only check, translate"), @("ns-3 run", "a2-intent-slicing"), @("analyze.py", "PDF/CDF, KPIs, SLA verdict"))
$x = 40; $bw = 196
for ($i = 0; $i -lt 4; $i++) {
    Box $s $x 92 $bw 70 $TINT | Out-Null
    T $s $steps[$i][0] ($x + 14) 104 ($bw - 28) 22 16 $INK $true | Out-Null
    T $s $steps[$i][1] ($x + 14) 128 ($bw - 28) 30 13 $MUTED | Out-Null
    if ($i -lt 3) { Arrow $s ($x + $bw + 6) 116 20 22 | Out-Null }
    $x += $bw + 32
}
T $s "1 gNB, 100 MHz at 28 GHz, numerology 2, UMi channel; the intent sets the split into two bandwidth parts" 40 184 880 20 14 $MUTED | Out-Null
Box $s 40 212 616 40 $BLUE | Out-Null
Box $s 662 212 258 40 $ORANGE | Out-Null
T $s "BWP 0  =  slice A  (share from the intent)" 56 223 590 20 15 $WHITE $true | Out-Null
T $s "BWP 1  =  slice B" 676 223 230 20 15 $WHITE $true | Out-Null
Box $s 40 272 430 150 $BLUETINT | Out-Null
T $s "SLICE A  |  eMBB video  |  5QI 9" 58 288 400 18 13 $BLUE $true | Out-Null
T $s ("2 UEs, 30 Mbps each`r" + "XR video from my XrVideoApp`r" + "(3GPP TR 26.926 model)") 58 314 400 100 17 $INK | Out-Null
Box $s 490 272 430 150 $ORTINT | Out-Null
T $s "SLICE B  |  low latency  |  5QI 80" 508 288 400 18 13 $ORANGE $true | Out-Null
T $s ("2 UEs: 100 B every 4 ms (light)`r" + "or 1 000 B every 0.4 ms (heavy, 20 Mbps each)`r" + "SLA: p95 delay <= 10 ms, loss <= 1 %") 508 314 400 100 17 $INK | Out-Null
Footer $s 6; Notes $s 6

# ===== 7. Verification =====
$s = $pres.Slides.Add(7, 12); Bg $s $WHITE
Title $s "My traffic matches the 3GPP model"
$fig = Join-Path $Res "intent-a70-traffic-model.png"
$p = Pic $s $fig 520 76 -1 -1
$scale = 424 / $p.Height; $p.Height = 424; $p.Width = $p.Width * 1; $p.Left = 920 - $p.Width; $p.Top = 76
T $s "KS TEST AGAINST THE MODEL (660 FRAMES)" 40 96 440 18 13 $BLUE $true | Out-Null
$ks = @(@("0.38", "frame size"), @("0.98", "frame jitter"), @("0.95", "frame inter-arrival"))
for ($i = 0; $i -lt 3; $i++) {
    $ty = 124 + $i * 78
    T $s ("p = " + $ks[$i][0]) 40 $ty 200 50 34 $INK $true $HEAD | Out-Null
    T $s $ks[$i][1] 240 ($ty + 14) 220 24 17 $MUTED | Out-Null
}
T $s "All p > 0.05: no evidence that my generator differs from the model." 40 364 440 44 16 $INK $true | Out-Null
T $s "Means: 62.3 vs 62.5 kB per frame, 16.66 vs 16.67 ms between frames." 40 414 440 40 15 $MUTED | Out-Null
T $s "Blue = my ns-3 run, orange = 3GPP model" 40 462 440 20 13 $MUTED | Out-Null
Footer $s 7; Notes $s 7

# ===== 8. Wireshark =====
$s = $pres.Slides.Add(8, 12); Bg $s $WHITE
Title $s "Proof on the wire"
$io = Join-Path $Res "intent-a70-rh-8-1_IO_zoom.png"
$p = Pic $s $io 40 92 -1 -1
$p.LockAspectRatio = -1; $p.Width = 590; $p.Left = 40; $p.Top = 92
$capY = 92 + $p.Height + 12
T $s "Wireshark I/O graph, 1 ms bins, first 1.2 s: one spike per video frame (red), slice B flat (blue). A ~500 kbit spike is one 62.5 kB frame." 40 $capY 590 50 14 $MUTED | Out-Null
Box $s 660 92 260 380 $TINT | Out-Null
T $s "VIDEO PACKETS COUNTED" 680 110 220 18 13 $BLUE $true | Out-Null
T $s "29 715" 680 136 220 60 46 $INK $true $HEAD | Out-Null
T $s "in all three sources:" 680 200 220 20 15 $MUTED | Out-Null
$src = @(@("Wireshark (PCAP)", "29 715"), @("FlowMonitor", "29 715"), @("my send log", "29 715"))
for ($i = 0; $i -lt 3; $i++) {
    $ty = 236 + $i * 40
    T $s $src[$i][0] 680 $ty 140 22 16 $INK | Out-Null
    T $s $src[$i][1] 820 $ty 80 22 16 $INK $true $BODY 3 | Out-Null
}
T $s "330 frames per UE, 43 to 53 packets each, 15.5 to 17.4 ms apart" 680 372 220 70 14 $MUTED | Out-Null
Footer $s 8; Notes $s 8

# ===== 9. Results =====
$s = $pres.Slides.Add(9, 12); Bg $s $WHITE
Title $s "Four intents accepted, one breaks slice B"
$rows = @(
    @("Intent", "Split A / B", "Slice B load", "B p95 delay", "B loss", "Slice B SLA"),
    @("a70", "70 / 30 MHz", "0.4 Mbps", "1.0 ms", "0.00 %", "met"),
    @("a90", "90 / 10 MHz", "0.4 Mbps", "1.0 ms", "0.00 %", "met"),
    @("a70-heavyB", "70 / 30 MHz", "40 Mbps", "1.1 ms", "0.01 %", "met"),
    @("a90-heavyB", "90 / 10 MHz", "40 Mbps", "12.7 ms", "9.99 %", "VIOLATED")
)
$tshape = Table $s $rows 40 96 600 250 @(110, 100, 100, 100, 85, 105) 15
$tbl = $tshape.Table
for ($c = 1; $c -le 6; $c++) {
    $cell = $tbl.Cell(5, $c); $cell.Shape.Fill.ForeColor.RGB = (RGB $REDTINT)
    $cell.Shape.TextFrame.TextRange.Font.Bold = 1; $cell.Shape.TextFrame.TextRange.Font.Color.RGB = (RGB $RED)
}
for ($r = 2; $r -le 4; $r++) { $tbl.Cell($r, 6).Shape.TextFrame.TextRange.Font.Color.RGB = (RGB $GREEN); $tbl.Cell($r, 6).Shape.TextFrame.TextRange.Font.Bold = 1 }
T $s "All four passed the capacity-only check. Slice A is unchanged in all four (2 x 30 Mbps, 0 % loss)." 40 ($tshape.Top + $tshape.Height + 16) 600 44 15 $MUTED | Out-Null
Box $s 670 96 250 376 $REDTINT | Out-Null
T $s "SLICE B, a90-heavyB" 690 114 210 18 13 $RED $true | Out-Null
T $s "12.7 ms" 690 140 210 60 48 $RED $true $HEAD | Out-Null
T $s "p95 delay vs 10 ms budget; 10 % of packets not delivered" 690 204 210 60 15 $INK | Out-Null
T $s "Same 90 / 10 split: safe when slice B is light, harmful when it is heavy. The shares alone cannot tell." 690 290 210 120 16 $INK $true | Out-Null
Footer $s 9; Notes $s 9

# ===== 10. Take-aways (dark) =====
$s = $pres.Slides.Add(10, 12); Bg $s $INK
T $s "Take-aways" 40 26 880 48 30 $WHITE $true $HEAD 1 "Title" | Out-Null
$tk = @(
    "ns-3.48 + 5G-LENA v5.1 runs on my VM; setup and what broke are documented",
    "My XR video generator matches 3GPP TR 26.926: PDF/CDF, KS tests, Wireshark",
    "The capacity-only check accepts an intent that breaks slice B's SLA; harm depends on the victim's load, not only the share"
)
$y = 96
for ($i = 0; $i -lt 3; $i++) {
    Circle $s 40 $y 36 $ORANGE ([string]($i + 1)) | Out-Null
    T $s $tk[$i] 92 ($y + 4) 828 50 19 $WHITE | Out-Null
    $y += 70
}
T $s "NEXT" 40 318 880 18 13 $ORANGE $true | Out-Null
$nx = @(@("A3", "baseline paper on RAN slicing QoS"), @("A4", "sweep share x slice B load, 10+ seeds, 95 % CI"), @("Final", "QoS-aware check that rejects intents like a90-heavyB"))
for ($i = 0; $i -lt 3; $i++) {
    $bx = 40 + $i * 300
    Box $s $bx 344 280 100 "1E3A52" | Out-Null
    T $s $nx[$i][0] ($bx + 16) 358 248 24 18 $ORANGE $true | Out-Null
    T $s $nx[$i][1] ($bx + 16) 386 248 50 15 $WHITE | Out-Null
}
T $s "Limits: one seed and 6 s per run; `"loss`" under overload is backlog left at the end of the run." 40 466 880 20 13 $LIGHT | Out-Null
T $s "$TOTAL / $TOTAL" 820 508 100 16 10 $LIGHT $false $BODY 3 | Out-Null
Notes $s 10

# ---------- save + export PNGs for QA ----------
if (Test-Path $Out) { Remove-Item $Out -Force }
$pres.SaveAs($Out, 24)
$qa = Join-Path $env:TEMP "a2deck_qa"; New-Item -ItemType Directory -Force $qa | Out-Null
Get-ChildItem $qa -Filter *.png | Remove-Item -Force
for ($i = 1; $i -le $pres.Slides.Count; $i++) { $pres.Slides.Item($i).Export((Join-Path $qa ("slide-{0:D2}.png" -f $i)), "PNG", 1600, 900) }
$pres.Close(); $app.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
"Saved $Out"; "QA images in $qa"
