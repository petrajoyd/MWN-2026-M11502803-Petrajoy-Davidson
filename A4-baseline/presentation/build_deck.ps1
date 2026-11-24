param([string]$Repo = "C:\Users\pj02d\Documents\GitHub\petrajoyd\MWN-2026-M11502803-Petrajoy-Davidson", [string]$Qa = "")
$ErrorActionPreference = "Stop"
$A4 = Join-Path $Repo "A4-baseline"
$OutDir = Join-Path $A4 "presentation"
$Fig = Join-Path $OutDir "figures"
$Out = Join-Path $OutDir "A4-baseline-reproduction.pptx"

# plain style: white slides, black text only, grey for captions and borders
$BLACK = "1A1A1A"; $GREY = "595959"; $LINE = "BFBFBF"; $HEADER = "EDEDED"
$FONT = "Calibri"

function RGB([string]$hex) { $r = [Convert]::ToInt32($hex.Substring(0,2),16); $g = [Convert]::ToInt32($hex.Substring(2,2),16); $b = [Convert]::ToInt32($hex.Substring(4,2),16); return $r + 256*$g + 65536*$b }

function T($slide, [string]$text, $l, $t, $w, $h, $size = 18, $color = $BLACK, $bold = $false, $align = 1) {
    $s = $slide.Shapes.AddTextbox(1, $l, $t, $w, $h)
    $tf = $s.TextFrame; $tf.WordWrap = -1; $tf.AutoSize = 0
    $tf.MarginLeft = 0; $tf.MarginRight = 0; $tf.MarginTop = 0; $tf.MarginBottom = 0
    $tr = $tf.TextRange; $tr.Text = $text
    $tr.Font.Name = $FONT; $tr.Font.Size = $size; $tr.Font.Bold = [int]$bold; $tr.Font.Color.RGB = (RGB $color)
    $tr.ParagraphFormat.Alignment = $align
    return $s
}

function Bullets($slide, [string[]]$items, $l, $t, $w, $h, $size = 18) {
    $s = T $slide ($items -join "`r") $l $t $w $h $size
    $tr = $s.TextFrame.TextRange
    $tr.ParagraphFormat.Bullet.Visible = -1
    $tr.ParagraphFormat.Bullet.Character = 8226
    $tr.ParagraphFormat.SpaceAfter = 8
    $s.TextFrame.Ruler.Levels.Item(1).FirstMargin = 0
    $s.TextFrame.Ruler.Levels.Item(1).LeftMargin = 16
    return $s
}

# centred title, no rule underneath
function Title($slide, [string]$text) { T $slide $text 40 24 880 40 28 $BLACK $true 2 | Out-Null }

function Footer($slide, $n) { T $slide "$n" 860 512 60 14 10 $GREY $false 3 | Out-Null }

function PicFit($slide, [string]$name, $l, $t, $w, $h, $border = $true) {
    $path = Join-Path $Fig $name
    $p = $slide.Shapes.AddPicture($path, 0, -1, $l, $t, -1, -1)
    $p.LockAspectRatio = -1
    $k = [math]::Min($w / $p.Width, $h / $p.Height)
    $p.Width = $p.Width * $k
    $p.Left = $l + ($w - $p.Width) / 2; $p.Top = $t
    if ($border) { $p.Line.Visible = -1; $p.Line.ForeColor.RGB = (RGB $LINE); $p.Line.Weight = 0.75 }
    return $p
}

function Source($slide, [string]$text, $l, $t, $w) { T $slide $text $l $t $w 14 11 $GREY | Out-Null }

function Table($slide, $rows, $l, $t, $w, $h, $colW, $size = 14) {
    $nr = $rows.Count; $nc = $rows[0].Count
    $shape = $slide.Shapes.AddTable($nr, $nc, $l, $t, $w, $h)
    $tbl = $shape.Table
    $tbl.ApplyStyle("{5940675A-B579-460E-94D1-54222C63F5DA}")
    for ($c = 1; $c -le $nc; $c++) { $tbl.Columns.Item($c).Width = $colW[$c-1] }
    for ($r = 1; $r -le $nr; $r++) {
        $tbl.Rows.Item($r).Height = 10
        for ($c = 1; $c -le $nc; $c++) {
            $cell = $tbl.Cell($r, $c)
            $tf = $cell.Shape.TextFrame
            $tf.MarginLeft = 6; $tf.MarginRight = 6; $tf.MarginTop = 3; $tf.MarginBottom = 3
            $tr = $tf.TextRange; $tr.Text = [string]$rows[$r-1][$c-1]
            $tr.Font.Name = $FONT; $tr.Font.Size = $size; $tr.Font.Color.RGB = (RGB $BLACK)
            $cell.Shape.Fill.Visible = -1; $cell.Shape.Fill.Solid()
            if ($r -eq 1) { $tr.Font.Bold = 1; $cell.Shape.Fill.ForeColor.RGB = (RGB $HEADER) } else { $cell.Shape.Fill.ForeColor.RGB = (RGB "FFFFFF") }
            foreach ($b in 1, 2, 3, 4) { $cell.Borders.Item($b).ForeColor.RGB = (RGB $LINE); $cell.Borders.Item($b).Weight = 0.75 }
        }
    }
    return $shape
}

function Box($slide, [string]$text, $l, $t, $w, $h, $size = 14) {
    $s = $slide.Shapes.AddShape(1, $l, $t, $w, $h)
    $s.Fill.ForeColor.RGB = (RGB "FFFFFF"); $s.Line.ForeColor.RGB = (RGB $LINE); $s.Line.Weight = 1.25
    $tf = $s.TextFrame; $tf.WordWrap = -1; $tf.MarginLeft = 8; $tf.MarginRight = 8
    $tr = $tf.TextRange; $tr.Text = $text
    $tr.Font.Name = $FONT; $tr.Font.Size = $size; $tr.Font.Color.RGB = (RGB $BLACK)
    $tr.ParagraphFormat.Alignment = 2
    return $s
}
function Arrow($slide, $x1, $y1, $x2, $y2) {
    $a = $slide.Shapes.AddLine($x1, $y1, $x2, $y2)
    $a.Line.ForeColor.RGB = (RGB $GREY); $a.Line.Weight = 1.5; $a.Line.EndArrowheadStyle = 2
}

$notes = @{}
function Notes($slide, $n) { if ($notes.ContainsKey($n)) { $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $notes[$n] } }
function NewSlide($n) { $s = $pres.Slides.Add($n, 12); $s.FollowMasterBackground = 0; $s.Background.Fill.Solid(); $s.Background.Fill.ForeColor.RGB = (RGB "FFFFFF"); return $s }

# ---------- speaker notes ----------
$notes[1] = "For A4 I reproduced one result from the paper I picked in A3, Rana et al. in IEEE TVT 2024. I rebuilt their scenario in ns-3 with 5G-LENA and tried to get their Fig. 6."
$notes[2] = "This is Fig. 6. It shows how the service rate drops when the delay before the RAN goes from 10 to 80 ms. Service rate means the share of 2-second windows where a flow meets all its QoS targets. Their scheduler, FLS and CBAP aren't public, so I used the PF and QoS schedulers that come with 5G-LENA. So I'm after the same scenario and trend, not the exact curve."
$notes[3] = "I have one macro cell at 3.7 GHz and one small cell at 28 GHz, on different bands. There are 16 UEs moving around. The fast ones stay on the macro, because 5G-LENA has no handover. I used 100 MHz instead of 200 so the runs finish in time."
$notes[4] = "Three slices with the same priorities as the paper: MTC first, then VoIP, then video. When the paper doesn't give a number, I picked one. The two real differences are UDP instead of TCP echo, and where I put the Pareto distribution for video."
$notes[5] = "Here I checked what my runs actually sent against each model. VoIP and video match almost exactly. MTC varies more between flows because each state can last up to a second. Video comes out at 14.25 instead of 15 Mbit/s because I cap the frame size."
$notes[6] = "All traffic is UDP, so the server delay doesn't change what happens in the RAN. So I simulate the RAN once per scheduler and seed, and add the server delay afterwards for each value on the x-axis. That's 10 runs instead of 80."
$notes[7] = "The trend matches: the service rate drops as the delay grows, and faster after 40 to 50 ms, like in the paper. But my values are 25 to 30 points lower. The next slides are about why."
$notes[8] = "MTC and VoIP are around 75 to 85 percent at 10 ms. Video is the weak one. Looking only at the RAN, video loses 2.8 percent of its packets with PF and 6.6 percent with QoS, and some packets take very long."
$notes[9] = "Most of the gap comes from the small cell. On the macro, slow UEs meet their targets in 82 to 97 percent of windows. On the 28 GHz small cell it's only 4 to 60 percent. In the paper a UE can use several gNBs at once; in 5G-LENA it's stuck on one. If I only count the macro UEs, the curve goes up by about 14 points."
$notes[10] = "The rest of the gap: their schedulers look at packet deadlines, PF and QoS don't. QoS is below PF because I had to set its fairness exponent to zero to stop a crash, and then it ignores channel quality. The strict video loss target isn't the reason; loosening it changes less than one point."
$notes[11] = "These are the problems I hit on the way. I found all of them with a small script that prints loss and delay for every UE."
$notes[12] = "To sum up: the scenario, traffic, metric and trend are reproduced, the level isn't, and I can explain why. The main lesson for my project is that the delay outside the RAN matters as much as the slice share."

# ---------- build ----------
$app = New-Object -ComObject PowerPoint.Application
$pres = $app.Presentations.Add(0)
$pres.PageSetup.SlideWidth = 960; $pres.PageSetup.SlideHeight = 540

# 1. Title
$s = NewSlide 1
T $s "A4: Baseline Reproduction" 60 160 840 50 36 $BLACK $true 2 | Out-Null
T $s "Reproducing Fig. 6 of Rana et al. (IEEE TVT 2024) in ns-3 and 5G-LENA" 60 220 840 40 20 $GREY $false 2 | Out-Null
T $s "Petrajoy Davidson (M11502803)`rMultimedia Wireless Networks (ET5907701), Advanced path`r2026/12/01" 60 310 840 80 16 $BLACK $false 2 | Out-Null
Notes $s 1

# 2. The figure
$s = NewSlide 2
Title $s "The figure I reproduce"
$p = PicFit $s "rana-fig6.png" 40 90 450 300
Source $s "M. K. Rana et al., IEEE Trans. Veh. Technol., vol. 73, no. 3, 2024, Fig. 6" 40 ($p.Top + $p.Height + 4) 450
Bullets $s @(
    "The x-axis is the mean delay between the server and the UPF, from 10 to 80 ms",
    "Service rate is the share of 2 s windows in which a flow meets all its QoS targets",
    "I picked it because the delay outside the RAN is what my intent check has to account for",
    "Their scheduler, FLS and CBAP are not public, so I use the PF and QoS schedulers of 5G-LENA",
    "So I aim for the same scenario and trend, not the exact curve"
) 515 92 405 380 16 | Out-Null
Footer $s 2; Notes $s 2

# 3. Scenario
$s = NewSlide 3
Title $s "Scenario"
$p = PicFit $s "scenario.png" 40 80 360 400 $false
Source $s "Where the UEs start (run PF-s1). Each UE moves inside its cell's box." 40 ($p.Top + $p.Height + 2) 360
$rows = @(
    @("", "Setting"),
    @("Simulator", "ns-3.48 + 5G-LENA v5.1"),
    @("Cells", "macro 3.7 GHz (UMa, 43 dBm) and small cell 28 GHz (UMi, 30 dBm) on separate bands"),
    @("Bandwidth", "100 MHz each (paper: 200 MHz), μ = 1 and μ = 2, TDD"),
    @("Antennas", "gNB 2×4, UE 1×2 (paper: 2×2 MIMO)"),
    @("Channel", "3GPP TR 38.901 with shadowing"),
    @("UEs", "16 in total: 6 MTC, 6 VoIP, 4 video (11 macro, 5 small cell)"),
    @("Mobility", "random way-point, 20 % at 100 km/h (macro only), 80 % at 3 km/h"),
    @("Schedulers", "PF and QoS (5G-LENA OFDMA)"),
    @("Time", "12.5 s per run: 2 s warm-up, then 5 windows of 2 s"),
    @("Runs", "2 schedulers × 5 seeds (RngRun 1–5) = 10 runs")
)
Table $s $rows 420 84 500 300 @(95, 405) 13 | Out-Null
Footer $s 3; Notes $s 3

# 4. Traffic model
$s = NewSlide 4
Title $s "Traffic model"
$rows = @(
    @("", "MTC", "VoIP", "Video"),
    @("Source", "4 states lasting 1, 0.5, 0.5, 0.5 s on average; 0, 55, 50, 0 packets/s", "Poisson, one packet every 20 ms on average", "30 frames/s, Pareto frame size (α = 2.5, capped at 4× the mean)"),
    @("Packet size", "100 B", "32 B", "up to 1400 B"),
    @("Mean rate", "16.8 kbit/s", "12.8 kbit/s", "14.25 Mbit/s"),
    @("5QI (priority)", "80 (68), served first", "7 (70)", "9 (90), served last"),
    @("QoS target", "≤ 100 ms, loss ≤ 1e-2", "≤ 100 ms, loss ≤ 1e-2, jitter ≤ 40 ms", "≤ 100 ms, loss ≤ 1e-6, jitter ≤ 40 ms"),
    @("UEs (macro / small)", "6 (4 / 2)", "6 (4 / 2)", "4 (3 / 1)")
)
Table $s $rows 40 84 880 260 @(130, 290, 210, 250) 14 | Out-Null
T $s "Same as the paper" 40 305 160 20 16 $BLACK $true | Out-Null
T $s "Model types, MTC states and rates, VoIP rate, 30 fps video, priorities and QoS targets." 210 305 710 40 16 | Out-Null
T $s "Different" 40 350 160 20 16 $BLACK $true | Out-Null
T $s "MTC uses UDP instead of TCP echo. Video uses Pareto for the frame size, not the inter-arrival time. Flows never stop (the paper uses 120 s flows). Packet sizes, MTC transitions and the Pareto shape are not in the paper, so I chose them." 210 350 710 80 16 | Out-Null
Footer $s 4; Notes $s 4

# 5. Traffic check
$s = NewSlide 5
Title $s "Checking the traffic"
$p = PicFit $s "traffic_model.png" 40 82 560 410
$rows = @(
    @("Slice", "Model", "Measured"),
    @("MTC", "16.8 kbit/s", "17.8 ± 7.0 kbit/s"),
    @("VoIP", "12.8 kbit/s", "12.8 ± 0.6 kbit/s"),
    @("Video", "14.25 Mbit/s", "14.23 ± 0.40 Mbit/s")
)
Table $s $rows 620 84 300 120 @(60, 110, 130) 13 | Out-Null
Bullets $s @(
    "Measured over all 10 runs, from 2 to 12 s",
    "Video frames average 59.3 kB (model 59.4 kB)",
    "VoIP packets arrive every 19.9 ms on average (model 20 ms)",
    "MTC varies more between flows because each state lasts up to 1 s",
    "Video is 14.25 Mbit/s instead of 15 because the frame size is capped"
) 620 230 300 260 14 | Out-Null
Footer $s 5; Notes $s 5

# 6. Method
$s = NewSlide 6
Title $s "Method"
$y1 = 100; $h = 78; $w = 260
Box $s "Scenario in ns-3 + 5G-LENA" 40 $y1 $w $h | Out-Null
Box $s "10 runs`r(PF and QoS, seeds 1–5)" 350 $y1 $w $h | Out-Null
Box $s "Log every packet`rRAN delay = rx time − tx time" 660 $y1 $w $h | Out-Null
Arrow $s 300 ($y1 + $h/2) 350 ($y1 + $h/2); Arrow $s 610 ($y1 + $h/2) 660 ($y1 + $h/2)
$y2 = 240
Box $s "Add the server delay`rExp(D), D = 10 … 80 ms`rone value per flow every 2 s" 660 $y2 $w 90 | Out-Null
Box $s "Check each 2 s window`rpackets later than 100 ms count as lost`rloss and jitter targets" 350 $y2 $w 90 | Out-Null
Box $s "Service rate`raveraged over flows, slices and seeds`r(95 % confidence interval)" 40 $y2 $w 90 | Out-Null
Arrow $s 790 ($y1 + $h) 790 $y2
Arrow $s 660 ($y2 + 45) 610 ($y2 + 45); Arrow $s 350 ($y2 + 45) 300 ($y2 + 45)
Bullets $s @(
    "All traffic is UDP, so the server delay doesn't change what happens in the RAN. It only adds to each packet's delay.",
    "That lets me add it afterwards: 10 simulations instead of 80",
    "PF and QoS get the same random delays, so the comparison is fair"
) 40 370 880 120 16 | Out-Null
Footer $s 6; Notes $s 6

# 7. Results
$s = NewSlide 7
Title $s "Results"
$p = PicFit $s "fig6-mine-vs-rana.png" 40 82 560 340
Source $s "Mine: mean over 5 seeds, band = 95 % confidence interval. Rana: values read from Fig. 6." 40 ($p.Top + $p.Height + 4) 560
$rows = @(
    @("Delay", "PF", "QoS", "FLS"),
    @("10 ms", "69.4 ± 5.3", "65.4 ± 13.6", "95.1"),
    @("40 ms", "62.9 ± 7.5", "60.7 ± 10.8", "89.5"),
    @("80 ms", "41.6 ± 4.8", "41.1 ± 9.8", "77.4")
)
Table $s $rows 620 84 300 130 @(60, 80, 90, 70) 13 | Out-Null
Bullets $s @(
    "Same shape as the paper: the service rate drops as the delay grows, faster after 40–50 ms",
    "My values are 25 to 30 points below FLS and CBAP",
    "QoS does not beat PF (explained on slide 10)"
) 620 240 300 220 15 | Out-Null
Footer $s 7; Notes $s 7

# 8. Per slice
$s = NewSlide 8
Title $s "Results per slice"
T $s "Service rate per slice (%)" 40 84 420 20 15 $BLACK $true | Out-Null
$rows = @(
    @("Slice", "10 ms", "40 ms", "80 ms"),
    @("MTC  PF / QoS", "84 / 86", "78 / 79", "54 / 53"),
    @("VoIP  PF / QoS", "75 / 79", "72 / 75", "48 / 54"),
    @("Video  PF / QoS", "49 / 32", "39 / 29", "23 / 16")
)
Table $s $rows 40 110 420 130 @(150, 90, 90, 90) 14 | Out-Null
T $s "RAN only, without the server delay" 500 84 420 20 15 $BLACK $true | Out-Null
$rows = @(
    @("Slice", "Loss", "Mean", "p95", "p99"),
    @("MTC  PF", "0.7 %", "4.2 ms", "6.7 ms", "58 ms"),
    @("VoIP  PF", "0.7 %", "4.1 ms", "6.8 ms", "65 ms"),
    @("Video  PF", "2.8 %", "23.5 ms", "116 ms", "276 ms"),
    @("Video  QoS", "6.6 %", "49.5 ms", "254 ms", "455 ms")
)
Table $s $rows 500 110 420 150 @(100, 70, 80, 85, 85) 14 | Out-Null
Bullets $s @(
    "MTC and VoIP have about 4 ms mean RAN delay, but the slowest 1 % of packets take 50–75 ms",
    "Video is the weakest slice: at 10 ms, 10 % (PF) and 21 % (QoS) of its packets per window are lost or late",
    "QoS loses twice as much video as PF"
) 40 290 880 180 17 | Out-Null
Footer $s 8; Notes $s 8

# 9. Small cell
$s = NewSlide 9
Title $s "Why my results are lower"
T $s "Windows that meet the QoS targets (PF, 10 ms)" 40 84 420 20 15 $BLACK $true | Out-Null
$rows = @(
    @("Slice", "Macro 3 km/h", "Macro 100 km/h", "Small cell"),
    @("MTC", "97 %", "92 %", "60 %"),
    @("VoIP", "92 %", "84 %", "46 %"),
    @("Video", "82 %", "28 %", "4 %")
)
Table $s $rows 40 110 420 130 @(75, 110, 125, 110) 14 | Out-Null
Bullets $s @(
    "In Rana's setup a UE can use several gNBs from one shared resource pool",
    "In 5G-LENA a UE stays on one gNB with no handover, so a UE in a bad 28 GHz spot stays stuck there",
    "With only the macro UEs, the curve goes up by 14 points at 10 ms (83 % vs. 69 %)"
) 40 270 420 220 16 | Out-Null
$p = PicFit $s "fig6-macro-only.png" 480 84 440 300
Source $s "Same runs, counting only the macro UEs" 480 ($p.Top + $p.Height + 4) 440
Footer $s 9; Notes $s 9

# 10. Differences
$s = NewSlide 10
Title $s "Differences from the paper"
$rows = @(
    @("What I see", "Why"),
    @("Same trend", "More server delay leaves less of the 100 ms budget for the RAN"),
    @("25–30 points lower", "Each UE is tied to one gNB; small-cell UEs miss their targets in 40–96 % of windows"),
    @("Macro UEs still ~14 points lower", "PF and QoS don't look at packet deadlines, unlike Rana's scheduler, FLS and CBAP. Also 100 instead of 200 MHz, no MIMO, 12.5 s runs"),
    @("QoS no better than PF", "I set its fairness exponent to 0 to avoid a 5G-LENA crash, so it ignores channel quality and video loss doubles"),
    @("Steeper drop", "My schedulers can't react to a packet's remaining time, and Rana's delay model is not fully described"),
    @("Wide confidence intervals", "Only 4 video UEs and 5 seeds"),
    @("Not the reason", "The strict video loss target: loosening it to 1e-2 changes less than 1 point")
)
Table $s $rows 40 84 880 360 @(250, 630) 18 | Out-Null
Footer $s 10; Notes $s 10

# 11. Problems
$s = NewSlide 11
Title $s "Problems I ran into"
$rows = @(
    @("Problem", "Cause", "Fix"),
    @("QoS runs crashed (assert: weight > 0)", "a UE with no signal gets a zero weight", "fairness exponent set to 0"),
    @("10 % VoIP and 30 % video loss", "UEs too far from the cells, up to 350 m from the 28 GHz one", "smaller UE areas, ± 110 m and ± 300 m"),
    @("6 simulated seconds took 17 minutes", "200 MHz, 4×8 antennas and 28 UEs", "100 MHz, 2×4 antennas, 16 UEs: 8–10 min per run"),
    @("Macro cell overloaded", "5 video UEs at 15 Mbit/s on one cell", "4 video UEs")
)
Table $s $rows 40 84 880 260 @(290, 330, 260) 17 | Out-Null
T $s "I found these with a small script that prints loss and delay for every UE (diag_run.py)." 40 360 880 30 17 $GREY | Out-Null
Footer $s 11; Notes $s 11

# 12. Conclusion
$s = NewSlide 12
Title $s "Conclusion"
Bullets $s @(
    "I rebuilt Rana's scenario, traffic and metric, and the trend of Fig. 6 matches",
    "The level doesn't match. Most of the gap comes from UEs being tied to one gNB, the rest from the schedulers and my simplifications",
    "For the final project I reuse this setup and vary the slice share and slice B's load to test my intent check"
) 40 96 880 220 18 | Out-Null
T $s "The delay outside the RAN matters as much as the slice share, so my intent check has to account for it." 40 340 880 70 22 $BLACK $true 2 | Out-Null
Footer $s 12; Notes $s 12

# ---------- save + export PNGs for QA ----------
if (Test-Path $Out) { Remove-Item $Out -Force }
$pres.SaveAs($Out, 24)
if (-not $Qa) { $Qa = Join-Path $env:TEMP "a4deck_qa" }
New-Item -ItemType Directory -Force $Qa | Out-Null
Get-ChildItem $Qa -Filter *.png | Remove-Item -Force
for ($i = 1; $i -le $pres.Slides.Count; $i++) { $pres.Slides.Item($i).Export((Join-Path $Qa ("slide-{0:D2}.png" -f $i)), "PNG", 1600, 900) }
$pres.Close(); $app.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
"Saved $Out"; "QA images in $Qa"
