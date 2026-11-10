param([string]$Repo = "C:\Users\pj02d\Documents\GitHub\petrajoyd\MWN-2026-M11502803-Petrajoy-Davidson")
$ErrorActionPreference = "Stop"
$A3 = Join-Path $Repo "A3-literature-review"
$OutDir = Join-Path $A3 "presentation"
$Fig = Join-Path $OutDir "figures"
$Out = Join-Path $OutDir "A3-literature-review.pptx"

# plain style: white slides, black text, one dark blue for emphasis
$BLACK = "1A1A1A"; $GREY = "595959"; $LINE = "BFBFBF"; $HEADER = "EDEDED"; $BLUE = "1F4E79"; $RED = "C00000"
$FONT = "Calibri"
$TOTAL = 12

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

# bullet list: one paragraph per item, real PowerPoint bullets
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

function Title($slide, [string]$text) {
    T $slide $text 40 24 880 40 28 $BLACK $true | Out-Null
    $l = $slide.Shapes.AddLine(40, 70, 920, 70); $l.Line.ForeColor.RGB = (RGB $LINE); $l.Line.Weight = 1
}

function Footer($slide, $n) {
    T $slide "Petrajoy Davidson  |  A3 Literature Review" 40 512 500 14 10 $GREY | Out-Null
    T $slide "$n" 860 512 60 14 10 $GREY $false 3 | Out-Null
}

# picture scaled to fit inside a box, keeping its aspect ratio, with a thin border
function PicFit($slide, [string]$name, $l, $t, $w, $h) {
    $path = Join-Path $Fig $name
    $p = $slide.Shapes.AddPicture($path, 0, -1, $l, $t, -1, -1)
    $p.LockAspectRatio = -1
    $k = [math]::Min($w / $p.Width, $h / $p.Height)
    $p.Width = $p.Width * $k
    $p.Left = $l + ($w - $p.Width) / 2; $p.Top = $t
    $p.Line.Visible = -1; $p.Line.ForeColor.RGB = (RGB $LINE); $p.Line.Weight = 0.75
    return $p
}

function Source($slide, [string]$text, $l, $t, $w) { T $slide $text $l $t $w 14 11 $GREY | Out-Null }

function Table($slide, $rows, $l, $t, $w, $h, $colW, $size = 14) {
    $nr = $rows.Count; $nc = $rows[0].Count
    $shape = $slide.Shapes.AddTable($nr, $nc, $l, $t, $w, $h)
    $tbl = $shape.Table
    $tbl.ApplyStyle("{5940675A-B579-460E-94D1-54222C63F5DA}")  # No Style, Table Grid
    for ($c = 1; $c -le $nc; $c++) { $tbl.Columns.Item($c).Width = $colW[$c-1] }
    for ($r = 1; $r -le $nr; $r++) {
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

# speaker notes from script.md: "## N. Title (m:ss)" sections
$script = Get-Content (Join-Path $OutDir "script.md") -Raw -Encoding UTF8
$notes = @{}
foreach ($m in [regex]::Matches($script, '(?ms)^## (\d+)\. [^\r\n]*\r?\n(.*?)(?=^## \d+\. |\z)')) {
    $notes[[int]$m.Groups[1].Value] = ($m.Groups[2].Value.Trim() -replace '\r?\n\r?\n', "`r`r" -replace '\r?\n', ' ')
}
function Notes($slide, $n) { $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $notes[$n] }

function NewSlide($n) { $s = $pres.Slides.Add($n, 12); $s.FollowMasterBackground = 0; $s.Background.Fill.Solid(); $s.Background.Fill.ForeColor.RGB = (RGB "FFFFFF"); return $s }

# ---------- build ----------
$app = New-Object -ComObject PowerPoint.Application
$pres = $app.Presentations.Add(0)
$pres.PageSetup.SlideWidth = 960; $pres.PageSetup.SlideHeight = 540

# 1. Title
$s = NewSlide 1
T $s "A3: Literature Review" 60 150 840 50 36 $BLACK $true | Out-Null
T $s "RAN slicing QoS and intent validation: three IEEE Transactions papers and my revised proposal" 60 210 840 60 20 $GREY | Out-Null
$l = $s.Shapes.AddLine(60, 290, 900, 290); $l.Line.ForeColor.RGB = (RGB $LINE)
T $s "Petrajoy Davidson (M11502803)`rMultimedia Wireless Networks (ET5907701), Advanced path`r2026/11/17" 60 310 840 80 16 $BLACK | Out-Null
Notes $s 1

# 2. Where A2 left me
$s = NewSlide 2
Title $s "Where A2 left me"
$rows = @(
    @("Intent", "Split A / B", "Slice B load", "Slice B p95 delay", "Slice B loss", "Slice B SLA"),
    @("a70", "70 / 30 MHz", "0.4 Mbps", "1.0 ms", "0.00 %", "met"),
    @("a90", "90 / 10 MHz", "0.4 Mbps", "1.0 ms", "0.00 %", "met"),
    @("a70-heavyB", "70 / 30 MHz", "40 Mbps", "1.1 ms", "0.01 %", "met"),
    @("a90-heavyB", "90 / 10 MHz", "40 Mbps", "12.7 ms", "9.99 %", "violated")
)
$t2 = Table $s $rows 40 90 880 180 @(140, 140, 140, 170, 140, 150) 16
for ($c = 1; $c -le 6; $c++) { $t2.Table.Cell(5, $c).Shape.TextFrame.TextRange.Font.Bold = 1; $t2.Table.Cell(5, $c).Shape.TextFrame.TextRange.Font.Color.RGB = (RGB $RED) }
Source $s "My A2 runs: ns-3.48 + 5G-LENA v5.1, 1 gNB, 100 MHz at 28 GHz split into two BWPs. SLA: p95 delay <= 10 ms, loss <= 1 %." 40 ($t2.Top + $t2.Height + 8) 880
T $s "All four intents passed the capacity-only check. Questions I took to the literature:" 40 330 880 24 18 $BLACK $true | Out-Null
Bullets $s @("Is it known that a share which fits can still break another slice?", "How should a slice's QoS be measured?", "Has anyone checked an intent like this before it is enacted?") 40 364 880 120 18 | Out-Null
Footer $s 2; Notes $s 2

# 3. Papers
$s = NewSlide 3
Title $s "Papers selected"
$rows = @(
    @("", "Paper", "Venue", "What I use it for"),
    @("[1]", "Rana et al., A QoS improving downlink scheduling scheme for slicing in 5G RAN", "IEEE Trans. Veh. Technol., vol. 73, no. 3, 2024", "how slices share resources; how a slice's QoS is scored; 5G-LENA scenario"),
    @("[2]", "Polese et al., ColO-RAN: developing ML-based xApps for open RAN closed-loop control", "IEEE Trans. Mobile Comput., vol. 22, no. 10, 2023", "how slicing actions are defined; which measurements describe a slice"),
    @("[3]", "Habib et al., Harnessing LLMs, Informers and decision transformers for intent-driven RAN management in 6G", "IEEE Trans. Netw. Sci. Eng., vol. 13, 2026", "closest prior work to my check: validating an intent before it is executed")
)
Table $s $rows 40 90 880 120 @(40, 340, 210, 290) 15 | Out-Null
T $s "First pass on about 12 candidates, kept only IEEE Transactions papers; second pass on every figure and parameter table." 40 300 880 40 16 $GREY | Out-Null
Footer $s 3; Notes $s 3

# 4. Rana: scenario
$s = NewSlide 4
Title $s "[1] Rana et al.: scenario and system model"
$p = PicFit $s "rana-fig2-scenario.png" 40 84 470 320
Source $s "Source: [1], Fig. 2" 40 ($p.Top + $p.Height + 4) 470
$p = PicFit $s "rana-table3-params.png" 540 84 380 196
Source $s "Source: [1], Table III" 540 ($p.Top + $p.Height + 4) 380
Bullets $s @("Simulated in 5G-LENA (ns-3)", "3 slices: MTC, VoIP, 4K video (15 Mbps)", "80 % users indoor at 3 km/h, 20 % outdoor at 100 km/h", "Server-to-UPF delay: exponential, mean 20 ms") 540 316 380 160 15 | Out-Null
Footer $s 4; Notes $s 4

# 5. Rana: metric + results
$s = NewSlide 5
Title $s "[1] Rana et al.: service rate and results"
$p = PicFit $s "rana-fig6-fig7.png" 40 82 400 410
Source $s "Source: [1], Figs. 6 and 7" 40 ($p.Top + $p.Height + 4) 400
T $s "Service rate" 470 90 450 24 18 $BLUE $true | Out-Null
T $s "Share of 2 s windows (3GPP averaging window) in which a flow meets all its targets: delay, inter-packet delay, loss and throughput. Late packets count as lost." 470 118 450 90 16 | Out-Null
T $s "Results" 470 220 450 24 18 $BLUE $true | Out-Null
Bullets $s @("Fig. 6: as end-to-end delay grows to 80 ms, the proposed scheduler stays above ~84 %; FLS and CBAP drop to ~77 %", "Fig. 7: with inter-packet delay up to 36 ms, proposed ~77 %, others below 60 %", "In A2 I used one average per run, which hides short outages") 470 248 450 220 16 | Out-Null
Footer $s 5; Notes $s 5

# 6. Rana: load trade-off + reproduction
$s = NewSlide 6
Title $s "[1] Rana et al.: load trade-off and what I can reproduce"
$p = PicFit $s "rana-fig4-load.png" 40 84 450 240
Source $s "Source: [1], Fig. 4" 40 ($p.Top + $p.Height + 4) 450
T $s "When the cell is full, flows added to one slice are paid for by the other slice. This is my A2 result, at a larger scale." 40 ($p.Top + $p.Height + 26) 450 70 16 | Out-Null
$rows = @(
    @("Needed to reproduce", "In the paper?"),
    @("Layout, bands, power, SCS", "yes"),
    @("Traffic models, QoS targets", "yes, no packet sizes"),
    @("Users per slice", "no"),
    @("Simulation length, seeds", "no (warm-up 1200 s)"),
    @("Scheduler source code", "no")
)
$t6 = Table $s $rows 520 84 400 230 @(230, 170) 14
for ($r = 4; $r -le 6; $r++) { $t6.Table.Cell($r, 2).Shape.TextFrame.TextRange.Font.Color.RGB = (RGB $RED) }
T $s "A4 plan: rebuild the scenario in 5G-LENA (one macro and one small cell first) and reproduce the trend of Fig. 6 with 5G-LENA's own QoS and PF schedulers, 10 seeds." 520 340 400 120 16 | Out-Null
Footer $s 6; Notes $s 6

# 7. ColO-RAN: setup
$s = NewSlide 7
Title $s "[2] Polese et al. (ColO-RAN): setup and slicing actions"
$p = PicFit $s "coloran-table2-params.png" 40 84 440 230
Source $s "Source: [2], Table 2" 40 ($p.Top + $p.Height + 4) 440
$p13 = PicFit $s "coloran-fig13-actions.png" 510 84 410 350
Source $s "Source: [2], Fig. 13 (PRB split per slice: eMBB, MTC, URLLC)" 510 ($p13.Top + $p13.Height + 4) 410
Bullets $s @("Colosseum emulator, srsRAN base stations, O-RAN near-RT RIC", "Slicing action = number of PRBs per slice, always summing to 50", "Every allocation 'fits'; only QoS tells them apart") 40 350 440 140 15 | Out-Null
Footer $s 7; Notes $s 7

# 8. ColO-RAN: results
$s = NewSlide 8
Title $s "[2] Polese et al. (ColO-RAN): results"
$p = PicFit $s "coloran-fig7-results.png" 40 82 400 410
Source $s "Source: [2], Fig. 7" 40 ($p.Top + $p.Height + 4) 400
Bullets $s @("DRL agents that control the PRB split beat fixed allocations, even the most-chosen one [36, 3, 11]", "Agents observe buffer occupancy, PRB ratio (granted / requested), rate and PHY TBs; other KPMs were redundant", "Online training on the live RAN lowered users' throughput while the agent explored", "For my check: read slice B's buffer occupancy and PRB use") 470 92 450 380 16 | Out-Null
Footer $s 8; Notes $s 8

# 9. Habib
$s = NewSlide 9
Title $s "[3] Habib et al.: intent validation before execution"
$p = PicFit $s "habib-fig1-system.png" 40 82 230 380
Source $s "Source: [3], Fig. 1" 40 ($p.Top + $p.Height + 4) 230
$p9 = PicFit $s "habib-fig9-validation.png" 300 82 620 310
Source $s "Source: [3], Fig. 9 (red = intent wrongly validated)" 300 ($p9.Top + $p9.Height + 4) 620
Bullets $s @("Informer forecasts cell load, loss and power; a lookup table decides 'QoS drift' -> reject", "Reported 88 %: 12 of 100 wrong. Red marks sit on both rows, but misses and false rejections are not reported separately", "Cell-level, no per-slice SLA; simulator and seeds not stated") 300 ($p9.Top + $p9.Height + 26) 620 120 15 | Out-Null
Footer $s 9; Notes $s 9

# 10. Gap
$s = NewSlide 10
Title $s "Comparison and gap"
$rows = @(
    @("", "[1] Rana", "[2] ColO-RAN", "[3] Habib", "My project"),
    @("Who sets the slice share?", "the scheduler", "the DRL agent", "-", "an operator intent"),
    @("Checked before enactment?", "no", "no", "yes, cell level", "yes, per slice"),
    @("Slice QoS judged by", "service rate", "rate, buffer", "cell QoS drift", "service rate"),
    @("Misses and false rejections reported separately?", "-", "-", "no (one accuracy)", "yes"),
    @("Seeds / CI reported?", "no", "no", "no", "10 seeds, 95 % CI")
)
Table $s $rows 40 90 880 260 @(220, 150, 150, 160, 200) 16 | Out-Null
T $s "Gap: in [1] and [2] the network picks the share itself; nobody checks a share requested from outside. [3] checks, but per cell and with one accuracy number that mixes misses and false rejections." 40 380 880 80 18 | Out-Null
Footer $s 10; Notes $s 10

# 11. Changes
$s = NewSlide 11
Title $s "Revised proposal: what changed and why"
$rows = @(
    @("A1", "A3 (revised)", "Why"),
    @("A4 baseline not chosen", "Rana et al. [1]: their 5G-LENA scenario, trend of Fig. 6", "IEEE Transactions study on my simulator"),
    @("Intent = slice A share", "Intent = (slice A share, slice B load)", "A2 and [1] Fig. 4: share alone cannot tell"),
    @("SLA met or not, per run", "Service rate over 2 s windows; late packets lost", "[1]; also fixes my A2 backlog issue"),
    @("Check inputs not defined", "Slice B buffer occupancy and PRB use", "[2]"),
    @("Detection + false rejection", "Full confusion matrix + wasted bandwidth, vs Habib's rule", "[3] gives one accuracy only"),
    @("-", "Out of scope: LLM parsing, DRL, new schedulers", "focus on the check itself")
)
Table $s $rows 40 90 880 200 @(220, 380, 280) 16 | Out-Null
Footer $s 11; Notes $s 11

# 12. Plan
$s = NewSlide 12
Title $s "Plan and take-away"
Bullets $s @("A4 (12/1): Rana et al.'s scenario in 5G-LENA, service rate vs end-to-end delay, 10 seeds, compared with their Fig. 6", "Final (12/22): map slice B's service rate over (share, load), then the QoS-aware check vs capacity-only and Habib's threshold rule") 40 96 880 140 18 | Out-Null
$l = $s.Shapes.AddLine(40, 280, 920, 280); $l.Line.ForeColor.RGB = (RGB $LINE)
T $s "Take-away" 40 300 880 24 18 $BLUE $true | Out-Null
T $s "Whether a slice share is safe depends on the load of both slices, and none of the papers checks a requested share before it is enacted." 40 330 880 80 22 $BLACK $true | Out-Null
Footer $s 12; Notes $s 12

# ---------- save + export PNGs for QA ----------
if (Test-Path $Out) { Remove-Item $Out -Force }
$pres.SaveAs($Out, 24)
$qa = Join-Path $env:TEMP "a3deck_qa"; New-Item -ItemType Directory -Force $qa | Out-Null
Get-ChildItem $qa -Filter *.png | Remove-Item -Force
for ($i = 1; $i -le $pres.Slides.Count; $i++) { $pres.Slides.Item($i).Export((Join-Path $qa ("slide-{0:D2}.png" -f $i)), "PNG", 1600, 900) }
$pres.Close(); $app.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
"Saved $Out"; "QA images in $qa"
