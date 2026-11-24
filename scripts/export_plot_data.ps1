Add-Type -AssemblyName System.Numerics

$rawPath = "d:\MyData\Study\HK261\GTM\HPMR\sim\De5_RLC_Fourier.raw"
$outDir  = "d:\MyData\Study\HK261\GTM\HPMR\report\data"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Parameters (De 5: N1=2, N2=3, N3=1)
$Em = 19.0; $f0 = 80.0; $Period = 1.0 / $f0; $w0 = 2.0 * [Math]::PI * $f0
$R_val = 28.0; $L_val = 0.014; $C_val = 18e-6

function Get-SourceHarmonic([int]$n) {
    if ($n -eq 0) { return @{ amp=($Em/[Math]::PI); phi_cos=0.0 } }
    elseif ($n -eq 1) { return @{ amp=($Em/2.0); phi_cos=-90.0 } }
    elseif (($n % 2) -eq 0) { return @{ amp=(2.0*$Em/([Math]::PI*($n*$n-1.0))); phi_cos=180.0 } }
    else { return @{ amp=0.0; phi_cos=0.0 } }
}

function Get-H([int]$n) {
    if ($n -eq 0) { return @{ mag=0.0; phase_deg=0.0 } }
    $w = $n * $w0
    $num = New-Object System.Numerics.Complex (-$w*$w*$L_val*$C_val), 0.0
    $den = New-Object System.Numerics.Complex (1.0 - $w*$w*$L_val*$C_val), ($w*$L_val/$R_val)
    $H = [System.Numerics.Complex]::Divide($num, $den)
    $deg = $H.Phase * 180.0 / [Math]::PI
    if ($deg -lt 0) { $deg += 360.0 }
    return @{ mag=$H.Magnitude; phase_deg=$deg }
}

# Precompute analytical harmonic terms for u0_3h and u0_5h
$hData = @{}
foreach ($n in @(1,2,4,6,8)) {
    $src = Get-SourceHarmonic $n
    $H = Get-H $n
    $hData[$n] = @{
        amp = $src.amp * $H.mag
        psi_rad = ($src.phi_cos + $H.phase_deg) * [Math]::PI / 180.0
        src_amp = $src.amp
        src_phi_rad = $src.phi_cos * [Math]::PI / 180.0
    }
}
$a0 = $Em / [Math]::PI

# Fast streaming parser for ASCII LTspice .raw
$sr = [System.IO.StreamReader]::new($rawPath)
$nVars = 0
$varIdx = @{}
$inVars = $false
while (-not $sr.EndOfStream) {
    $line = $sr.ReadLine()
    if ($line -match '^No\. Variables:\s*(\d+)') { $nVars = [int]$Matches[1] }
    elseif ($line -eq 'Variables:') { $inVars = $true; continue }
    elseif ($line -eq 'Values:') { break }
    elseif ($inVars) {
        $parts = $line.Trim() -split '\s+'
        if ($parts.Length -ge 2) { $varIdx[$parts[1]] = [int]$parts[0] }
    }
}

$iTime   = $varIdx['time']
$iEReal  = $varIdx['V(e_real)']
$iE3h    = $varIdx['V(e_3h)']
$iE5h    = $varIdx['V(e_5h)']
$iUReal  = $varIdx['V(u0_real)']
$iU3h    = $varIdx['V(u0_3h)']
$iU5h    = $varIdx['V(u0_5h)']

$pts = New-Object System.Collections.Generic.List[object]
$inv = [System.Globalization.CultureInfo]::InvariantCulture

while (-not $sr.EndOfStream) {
    $first = $sr.ReadLine()
    if ([string]::IsNullOrWhiteSpace($first)) { continue }
    $fp = $first.Trim() -split '\s+'
    $tVal = [double]::Parse($fp[1], $inv)
    $vals = New-Object double[] $nVars
    $vals[0] = $tVal
    for ($v = 1; $v -lt $nVars; $v++) {
        $vl = $sr.ReadLine()
        $vals[$v] = [double]::Parse($vl.Trim(), $inv)
    }
    if ($tVal -le 0.0250001) {
        $u3_th = 0.0; $u5_th = 0.0
        foreach ($n in @(1,2,4)) {
            $u3_th += $hData[$n].amp * [Math]::Cos($n * $w0 * $tVal + $hData[$n].psi_rad)
        }
        $u5_th = $u3_th
        foreach ($n in @(6,8)) {
            $u5_th += $hData[$n].amp * [Math]::Cos($n * $w0 * $tVal + $hData[$n].psi_rad)
        }
        $pts.Add([PSCustomObject]@{
            t = $tVal
            e_real = $vals[$iEReal]
            e_3h   = $vals[$iE3h]
            e_5h   = $vals[$iE5h]
            u_real = $vals[$iUReal]
            u_3h   = $vals[$iU3h]
            u_5h   = $vals[$iU5h]
            u3_th  = $u3_th
            u5_th  = $u5_th
        })
    }
}
$sr.Close()

Write-Output ("Parsed {0} points in [0, 25 ms]" -f $pts.Count)

# Compute exact time-weighted (trapezoidal) RMSE over 1 steady-state period [0, 12.5 ms]
$p1 = $pts | Where-Object { $_.t -le 0.0125001 }
function Calc-ErrMetrics($arr, $propA, $propB) {
    $intErrSq = 0.0; $intRefSq = 0.0; $maxAbs = 0.0; $totT = 0.0
    for ($k = 0; $k -lt ($arr.Count - 1); $k++) {
        $dt = $arr[$k+1].t - $arr[$k].t
        $d0 = $arr[$k].$propA - $arr[$k].$propB
        $d1 = $arr[$k+1].$propA - $arr[$k+1].$propB
        $r0 = $arr[$k].$propB
        $r1 = $arr[$k+1].$propB
        $intErrSq += 0.5 * ($d0*$d0 + $d1*$d1) * $dt
        $intRefSq += 0.5 * ($r0*$r0 + $r1*$r1) * $dt
        $totT += $dt
        $a0 = [Math]::Abs($d0); if ($a0 -gt $maxAbs) { $maxAbs = $a0 }
    }
    $rmse = [Math]::Sqrt($intErrSq / $totT)
    $rmsRef = [Math]::Sqrt($intRefSq / $totT)
    $nrmse = ($rmse / $rmsRef) * 100.0
    return [PSCustomObject]@{ RMSE=$rmse; NRMSE_pct=$nrmse; MaxAbs=$maxAbs; RMS_Ref=$rmsRef }
}

$m_3th_vs_3sim   = Calc-ErrMetrics $p1 'u3_th' 'u_3h'
$m_5th_vs_5sim   = Calc-ErrMetrics $p1 'u5_th' 'u_5h'
$m_3sim_vs_real  = Calc-ErrMetrics $p1 'u_3h'  'u_real'
$m_5sim_vs_real  = Calc-ErrMetrics $p1 'u_5h'  'u_real'
$m_3th_vs_real   = Calc-ErrMetrics $p1 'u3_th' 'u_real'
$m_5th_vs_real   = Calc-ErrMetrics $p1 'u5_th' 'u_real'

Write-Output "=== EXACT COMPARISON METRICS OVER 1 PERIOD [0, 12.5 ms] ==="
Write-Output ("Theory 3h  vs LTspice 3h : RMSE = {0:F6} V | NRMSE = {1:F4}% | MaxAbs = {2:F6} V" -f $m_3th_vs_3sim.RMSE, $m_3th_vs_3sim.NRMSE_pct, $m_3th_vs_3sim.MaxAbs)
Write-Output ("Theory 5h  vs LTspice 5h : RMSE = {0:F6} V | NRMSE = {1:F4}% | MaxAbs = {2:F6} V" -f $m_5th_vs_5sim.RMSE, $m_5th_vs_5sim.NRMSE_pct, $m_5th_vs_5sim.MaxAbs)
Write-Output ("LTspice 3h vs LTspice d  : RMSE = {0:F4} V   | NRMSE = {1:F2}%   | MaxAbs = {2:F4} V" -f $m_3sim_vs_real.RMSE, $m_3sim_vs_real.NRMSE_pct, $m_3sim_vs_real.MaxAbs)
Write-Output ("LTspice 5h vs LTspice d  : RMSE = {0:F4} V   | NRMSE = {1:F2}%   | MaxAbs = {2:F4} V" -f $m_5sim_vs_real.RMSE, $m_5sim_vs_real.NRMSE_pct, $m_5sim_vs_real.MaxAbs)
Write-Output ("Theory 3h  vs LTspice d  : RMSE = {0:F4} V   | NRMSE = {1:F2}%   | MaxAbs = {2:F4} V" -f $m_3th_vs_real.RMSE, $m_3th_vs_real.NRMSE_pct, $m_3th_vs_real.MaxAbs)
Write-Output ("Theory 5h  vs LTspice d  : RMSE = {0:F4} V   | NRMSE = {1:F2}%   | MaxAbs = {2:F4} V" -f $m_5th_vs_real.RMSE, $m_5th_vs_real.NRMSE_pct, $m_5th_vs_real.MaxAbs)

# Export decimated waveforms_2T.dat (~500 points across [0, 25 ms])
$sb2 = New-Object System.Text.StringBuilder
[void]$sb2.AppendLine("t_ms e_real e_3h e_5h u0_real u0_3h_sim u0_5h_sim u0_3h_th u0_5h_th")
$step2 = [Math]::Max(1, [int][Math]::Floor($pts.Count / 500))
for ($k = 0; $k -lt $pts.Count; $k += $step2) {
    $p = $pts[$k]
    [void]$sb2.AppendLine(([string]::Format($inv, "{0:F4} {1:F5} {2:F5} {3:F5} {4:F5} {5:F5} {6:F5} {7:F5} {8:F5}", ($p.t*1000), $p.e_real, $p.e_3h, $p.e_5h, $p.u_real, $p.u_3h, $p.u_5h, $p.u3_th, $p.u5_th)))
}
$last2 = $pts[$pts.Count - 1]
[void]$sb2.AppendLine(([string]::Format($inv, "{0:F4} {1:F5} {2:F5} {3:F5} {4:F5} {5:F5} {6:F5} {7:F5} {8:F5}", ($last2.t*1000), $last2.e_real, $last2.e_3h, $last2.e_5h, $last2.u_real, $last2.u_3h, $last2.u_5h, $last2.u3_th, $last2.u5_th)))
[System.IO.File]::WriteAllText((Join-Path $outDir "waveforms_2T.dat"), $sb2.ToString())

# Export waveforms_1T.dat (~400 points across [0, 12.5 ms] with error columns)
$sb1 = New-Object System.Text.StringBuilder
[void]$sb1.AppendLine("t_ms u0_real u0_3h_sim u0_5h_sim u0_3h_th u0_5h_th err_3h err_5h")
$step1 = [Math]::Max(1, [int][Math]::Floor($p1.Count / 400))
for ($k = 0; $k -lt $p1.Count; $k += $step1) {
    $p = $p1[$k]
    [void]$sb1.AppendLine(([string]::Format($inv, "{0:F4} {1:F5} {2:F5} {3:F5} {4:F5} {5:F5} {6:F5} {7:F5}", ($p.t*1000), $p.u_real, $p.u_3h, $p.u_5h, $p.u3_th, $p.u5_th, ($p.u_3h - $p.u_real), ($p.u_5h - $p.u_real))))
}
$last1 = $p1[$p1.Count - 1]
[void]$sb1.AppendLine(([string]::Format($inv, "{0:F4} {1:F5} {2:F5} {3:F5} {4:F5} {5:F5} {6:F5} {7:F5}", ($last1.t*1000), $last1.u_real, $last1.u_3h, $last1.u_5h, $last1.u3_th, $last1.u5_th, ($last1.u_3h - $last1.u_real), ($last1.u_5h - $last1.u_real))))
[System.IO.File]::WriteAllText((Join-Path $outDir "waveforms_1T.dat"), $sb1.ToString())

# Export spectrum.dat (n = 0, 1, 2, 4, 6, 8, 10, 12) + continuous |H(f)| Bode curve
$sbSp = New-Object System.Text.StringBuilder
[void]$sbSp.AppendLine("n f_Hz E_amp H_mag U0_amp")
foreach ($n in @(0,1,2,4,6,8,10,12)) {
    $src = Get-SourceHarmonic $n
    $H   = Get-H $n
    [void]$sbSp.AppendLine(([string]::Format($inv, "{0} {1} {2:F5} {3:F5} {4:F5}", $n, ($n*$f0), $src.amp, $H.mag, ($src.amp*$H.mag))))
}
[System.IO.File]::WriteAllText((Join-Path $outDir "spectrum.dat"), $sbSp.ToString())

$sbBode = New-Object System.Text.StringBuilder
[void]$sbBode.AppendLine("f_Hz H_mag H_deg")
for ($f = 10; $f -le 1000; $f += 5) {
    $w = 2.0 * [Math]::PI * $f
    $num = New-Object System.Numerics.Complex (-$w*$w*$L_val*$C_val), 0.0
    $den = New-Object System.Numerics.Complex (1.0 - $w*$w*$L_val*$C_val), ($w*$L_val/$R_val)
    $H = [System.Numerics.Complex]::Divide($num, $den)
    $deg = $H.Phase * 180.0 / [Math]::PI
    if ($deg -lt 0) { $deg += 360.0 }
    [void]$sbBode.AppendLine(([string]::Format($inv, "{0} {1:F5} {2:F3}", $f, $H.Magnitude, $deg)))
}
[System.IO.File]::WriteAllText((Join-Path $outDir "bode.dat"), $sbBode.ToString())

Write-Output "Exported plot data files to $outDir"
