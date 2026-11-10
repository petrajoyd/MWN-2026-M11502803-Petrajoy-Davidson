param([string]$Repo = "C:\Users\pj02d\Documents\GitHub\petrajoyd\MWN-2026-M11502803-Petrajoy-Davidson", [string]$Script = "")
$ErrorActionPreference = "Stop"
$A3 = Join-Path $Repo "A3-literature-review"
$OutDir = Join-Path $A3 "presentation"
$Fig = Join-Path $OutDir "figures"
$Out = Join-Path $OutDir "A3-literature-review.pptx"

# plain style: white slides, black text, one dark blue for emphasis
$BLACK = "1A1A1A"; $GREY = "595959"; $LINE = "BFBFBF"; $HEADER = "EDEDED"; $BLUE = "1F4E79"; $RED = "C00000"
$FONT = "Calibri"
$TOTAL = 13

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

# optional speaker notes from a script kept outside the repo (-Script path): "## N. Title (m:ss)" sections
$notes = @{}
if ($Script -and (Test-Path $Script)) {
    $text = Get-Content $Script -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, '(?ms)^## (\d+)\. [^\r\n]*\r?\n(.*?)(?=^## \d+\. |\z)')) {
        $notes[[int]$m.Groups[1].Value] = ($m.Groups[2].Value.Trim() -replace '\r?\n\r?\n', "`r`r" -replace '\r?\n', ' ')
    }
}
function Notes($slide, $n) { if ($notes.ContainsKey($n)) { $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $notes[$n] } }

function NewSlide($n) { $s = $pres.Slides.Add($n, 12); $s.FollowMasterBackground = 0; $s.Background.Fill.Solid(); $s.Background.Fill.ForeColor.RGB = (RGB "FFFFFF"); return $s }

# ---------- slide templates (same three slides for every paper, in the TA's order) ----------

# 1) Problem, importance, challenges: the paper's own title block, then three labelled rows
function ProblemSlide($n, [string]$tag, [string]$titlePng, [string]$venue, [string]$problem, [string]$importance, [string]$challenges) {
    $s = NewSlide $n
    Title $s "$tag Problem, importance, challenges"
    $p = PicFit $s $titlePng 40 84 880 120
    Source $s $venue 40 ($p.Top + $p.Height + 4) 880
    $y = $p.Top + $p.Height + 34
    foreach ($row in @(@("Problem", $problem), @("Importance", $importance), @("Challenges", $challenges))) {
        T $s $row[0] 40 $y 140 24 18 $BLUE $true | Out-Null
        $tb = T $s $row[1] 180 $y 740 70 17
        $y += 82
    }
    Footer $s $n; Notes $s $n
}

# 2) System model: the paper's figure on the left, environment / inputs / outputs / metrics on the right
function ModelSlide($n, [string]$tag, [string]$figPng, [string]$figSource, $rows, $figW = 420) {
    $s = NewSlide $n
    Title $s "$tag System model"
    $p = PicFit $s $figPng 40 84 $figW 390
    Source $s $figSource 40 ($p.Top + $p.Height + 4) $figW
    $tx = 40 + $figW + 24; $tw = 920 - $tx
    $all = @(, @("Element", "Description")) + $rows
    Table $s $all $tx 84 $tw 200 @(110, ($tw - 110)) 13 | Out-Null
    Footer $s $n; Notes $s $n
}

# 3) Results and settings to reproduce: result figure left, settings table right ("not stated" in red)
function ResultSlide($n, [string]$tag, [string]$figPng, [string]$figSource, [string]$keyResult, $settings, $figW = 430) {
    $s = NewSlide $n
    Title $s "$tag Experimental results and settings to reproduce"
    $p = PicFit $s $figPng 40 84 $figW 330
    Source $s $figSource 40 ($p.Top + $p.Height + 4) $figW
    T $s $keyResult 40 ($p.Top + $p.Height + 24) $figW 70 15 $BLACK $true | Out-Null
    $tx = 40 + $figW + 24; $tw = 920 - $tx
    $all = @(, @("Setting", "In the paper")) + $settings
    $t = Table $s $all $tx 84 $tw 200 @(110, ($tw - 110)) 13
    for ($r = 2; $r -le $all.Count; $r++) {
        $tr = $t.Table.Cell($r, 2).Shape.TextFrame.TextRange
        # colour only the clauses that say something is missing
        foreach ($m in [regex]::Matches($tr.Text, '(?:^|; )([^;]*not stated[^;]*)')) {
            $g = $m.Groups[1]
            $tr.Characters($g.Index + 1, $g.Length).Font.Color.RGB = (RGB $RED)
        }
    }
    Footer $s $n; Notes $s $n
}

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

# 2. Papers selected
$s = NewSlide 2
Title $s "Papers selected"
T $s "Starting point (A2): a 90 / 10 split that passed the capacity check broke slice B's SLA (p95 delay 12.7 ms > 10 ms, 10 % loss) when slice B was heavily loaded." 40 84 880 50 16 | Out-Null
$rows = @(
    @("", "Paper", "Venue", "What I use it for"),
    @("[1]", "Rana et al., A QoS improving downlink scheduling scheme for slicing in 5G RAN", "IEEE Trans. Veh. Technol., vol. 73, no. 3, 2024", "how slices share resources; how a slice's QoS is scored; 5G-LENA scenario"),
    @("[2]", "Polese et al., ColO-RAN: developing ML-based xApps for open RAN closed-loop control", "IEEE Trans. Mobile Comput., vol. 22, no. 10, 2023", "how slicing actions are defined; which measurements describe a slice"),
    @("[3]", "Habib et al., Harnessing LLMs, Informers and decision transformers for intent-driven RAN management in 6G", "IEEE Trans. Netw. Sci. Eng., vol. 13, 2026", "closest prior work to my check: validating an intent before it is executed")
)
Table $s $rows 40 150 880 120 @(40, 340, 210, 290) 15 | Out-Null
T $s "For each paper: (1) problem, importance, challenges; (2) system model; (3) results and the settings needed to reproduce them. Then the revised proposal." 40 400 880 50 16 $GREY | Out-Null
Footer $s 2; Notes $s 2

# ===== [1] Rana et al. =====
ProblemSlide 3 "[1] Rana et al.:" "rana-title.png" "IEEE Trans. Veh. Technol., vol. 73, no. 3, pp. 4219-4233, Mar. 2024" `
    "Split a cell's radio resources among slices with different QoS targets and priorities, at every scheduling interval." `
    "Static per-slice reservation protects each slice but wastes spectrum; fixed priorities starve low-priority slices." `
    "The delay before the RAN (server to UPF) is random and eats into the deadline; 'sequential' slice schedulers collapse under load; the optimal allocation is NP-hard."

ModelSlide 4 "[1] Rana et al.:" "rana-fig2-scenario.png" "Source: [1], Fig. 2" @(
    @("Environment", "5G-LENA (ns-3). Macro cells at 3.7 GHz + small cells at 28 GHz, 2 x 2 km; 80 % users indoor (3 km/h), 20 % outdoor (100 km/h)"),
    @("Inputs", "per-slice load (number of flows) of MTC, VoIP and video slices; slice priority vector; server-to-UPF delay (exponential, mean 20 ms)"),
    @("Outputs", "per-packet resource block allocation at each scheduling interval"),
    @("Metrics", "service rate: share of 2 s windows in which a flow meets all targets (delay, inter-packet delay, loss, throughput); goodput = throughput x (1 - PLR), late packets lost; max supported load")
) 440

ResultSlide 5 "[1] Rana et al.:" "rana-fig6-fig7.png" "Source: [1], Figs. 6 and 7" `
    "At 80 ms end-to-end delay the proposed scheduler keeps about 84% service rate; FLS and CBAP drop to about 77%." @(
    @("Topology", "macro (43 dBm) + small cells (30 dBm), 866 m apart, small-cell radius 250 m; number of UEs per slice not stated"),
    @("Traffic", "MTC 4-state semi-Markov (TCP echo); VoIP 12.65 kbit/s; H.265 4K video 15 Mbit/s, Pareto; packet sizes not stated"),
    @("PHY / MAC", "200 MHz, SCS 15/30/60 kHz, TDD, 2x2 MIMO, 3GPP CQI/MCS tables; compared schedulers: proposed, FLS, CBAP, iRSS"),
    @("Simulation time", "results taken after 1200 s warm-up; total length not stated"),
    @("Seeds / runs", "not stated")
) 380

# ===== [2] ColO-RAN =====
ProblemSlide 6 "[2] Polese et al.:" "coloran-title.png" "IEEE Trans. Mobile Comput., vol. 22, no. 10, pp. 5787-5800, Oct. 2023 (screenshot: arXiv version)" `
    "Design, train and test DRL xApps that control RAN slicing (PRBs per slice) and scheduling through the O-RAN near-RT RIC." `
    "O-RAN enables data-driven closed-loop control, but without large datasets and testbeds it was rarely tried on a real RAN." `
    "Collecting data at scale; testing closed-loop ML without causing outages; missing or irregular KPM reports; generalising to new deployments; choosing features."

ModelSlide 7 "[2] Polese et al.:" "coloran-fig13-actions.png" "Source: [2], Fig. 13 (PRB split per slice: eMBB, MTC, URLLC)" @(
    @("Environment", "Colosseum emulator, Rome scenario: 7 srsRAN base stations, 42 UEs, 3 slices (eMBB, MTC, URLLC), O-RAN near-RT RIC over E2"),
    @("Inputs", "KPM reports: downlink rate, buffer occupancy, PRB ratio, PHY transport blocks (last 10 reports, compressed by an autoencoder)"),
    @("Outputs", "xApp action: PRBs per slice out of 50 (always summing to 50) and scheduler per slice (RR, WF, PF)"),
    @("Metrics", "eMBB throughput; MTC PHY TBs per second; MTC/URLLC buffer size (bytes); URLLC PRB ratio = PRBs granted / requested")
) 430

ResultSlide 8 "[2] Polese et al.:" "coloran-fig7-results.png" "Source: [2], Fig. 7" `
    "DRL agents that control the PRB split beat fixed allocations, even the one chosen most often, [36, 3, 11]." @(
    @("Topology", "7 base stations, 42 UEs (2 per slice per BS), positions from a real Rome deployment"),
    @("Traffic", "slice-based: eMBB 4 Mbit/s CBR, MTC 44.6 kbit/s and URLLC 89.3 kbit/s Poisson per UE; uniform: 1.5 Mbit/s per UE"),
    @("PHY / MAC", "LTE (srsRAN), DL 0.98 GHz, UL 1.02 GHz, 10 MHz = 50 PRBs; schedulers RR, WF, PF"),
    @("Simulation time", "3.4 GB / 73 h of traces in total; length of each experiment not stated"),
    @("Seeds / runs", "not stated (hardware emulation)")
) 380

# ===== [3] Habib et al. =====
ProblemSlide 9 "[3] Habib et al.:" "habib-title.png" "IEEE Trans. Netw. Sci. Eng., vol. 13, pp. 4187-4206, 2026 (screenshot: arXiv version)" `
    "Turn a natural-language intent into RAN actions, and check before execution whether the intent would degrade the network." `
    "A well-formed intent can still hurt, e.g. 'increase energy efficiency by 30 %' during peak traffic." `
    "Rule-based validation does not adapt to network changes; few-shot LLM parsing is inefficient; RL orchestration needs hand-made rewards."

ModelSlide 10 "[3] Habib et al.:" "habib-fig1-system.png" "Source: [3], Fig. 1" @(
    @("Environment", "macro cell with dense small cells, NR-LTE dual connectivity, 60 users; video, gaming, voice and URLLC traffic"),
    @("Inputs", "natural-language intent (type + magnitude); time series of cell traffic load, packet loss and power"),
    @("Outputs", "intent valid / invalid (Informer forecast + lookup table of 'QoS drift'); then which RAN applications to run"),
    @("Metrics", "validation accuracy; forecast MAE; throughput, delay and energy efficiency of the orchestration")
) 250

ResultSlide 11 "[3] Habib et al.:" "habib-fig9-validation.png" "Source: [3], Fig. 9 (red = intent wrongly validated)" `
    "88 %: 12 of 100 intents wrong. Red marks sit on both rows, but misses and false rejections are not reported separately." @(
    @("Topology", "macro + small cells, 60 users; number of base stations and mobility not stated"),
    @("Traffic", "video Pareto 12.5 ms, gaming uniform 40 ms, voice Poisson 20 ms, URLLC Poisson 0.5 ms; packet sizes not stated"),
    @("PHY / MAC", "NR 3.5 / 30 GHz, 50-100 MHz, SCS 15 / 60 kHz, 43 dBm; LTE 800 MHz, 40 MHz; scheduler not stated"),
    @("Simulation time", "plots in time slots; slot length and duration not stated"),
    @("Seeds / runs", "not stated; simulator name not stated")
) 470

# 12. Revised proposal
$s = NewSlide 12
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
Footer $s 12; Notes $s 12

# 13. Plan
$s = NewSlide 13
Title $s "Plan and take-away"
Bullets $s @("A4 (12/1): Rana et al.'s scenario in 5G-LENA, service rate vs end-to-end delay, 10 seeds, compared with their Fig. 6", "Final (12/22): map slice B's service rate over (share, load), then the QoS-aware check vs capacity-only and Habib's threshold rule") 40 96 880 140 18 | Out-Null
$l = $s.Shapes.AddLine(40, 280, 920, 280); $l.Line.ForeColor.RGB = (RGB $LINE)
T $s "Take-away" 40 300 880 24 18 $BLUE $true | Out-Null
T $s "Whether a slice share is safe depends on the load of both slices, and none of the papers checks a requested share before it is enacted." 40 330 880 80 22 $BLACK $true | Out-Null
Footer $s 13; Notes $s 13

# ---------- save + export PNGs for QA ----------
if (Test-Path $Out) { Remove-Item $Out -Force }
$pres.SaveAs($Out, 24)
$qa = Join-Path $env:TEMP "a3deck_qa"; New-Item -ItemType Directory -Force $qa | Out-Null
Get-ChildItem $qa -Filter *.png | Remove-Item -Force
for ($i = 1; $i -le $pres.Slides.Count; $i++) { $pres.Slides.Item($i).Export((Join-Path $qa ("slide-{0:D2}.png" -f $i)), "PNG", 1600, 900) }
$pres.Close(); $app.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
"Saved $Out"; "QA images in $qa"
