Add-Type -AssemblyName System.Numerics

# ==============================================================================
# De 5 - Giai tich mach EE2033 (HK261) - N1=2, N2=3, N3=1
# Exact Fourier Series + Frequency-Domain Transfer Function + Time-Domain Verification
# ==============================================================================

$N1 = 2; $N2 = 3; $N3 = 1
$Em = 15.0 + 2.0 * $N1          # 19 V
$f0 = 50.0 + 10.0 * $N2         # 80 Hz
$R_val = 25.0 + 3.0 * $N3       # 28 Ohm
$L_val = (12.0 + $N1) * 1e-3    # 14 mH
$C_val = (15.0 + $N2) * 1e-6    # 18 uF

$Period = 1.0 / $f0
$w0 = 2.0 * [Math]::PI * $f0
$fr = 1.0 / (2.0 * [Math]::PI * [Math]::Sqrt($L_val * $C_val))
$zeta = (1.0 / (2.0 * $R_val)) * [Math]::Sqrt($L_val / $C_val)
$tau = 2.0 * $R_val * $C_val

Write-Output "=== PARAMETERS (De 5: N1=$N1, N2=$N2, N3=$N3) ==="
Write-Output ("Em = {0} V, f0 = {1} Hz, T = {2:F4} ms, w0 = {3:F4} rad/s" -f $Em, $f0, ($Period*1000), $w0)
Write-Output ("R = {0} Ohm, L = {1} mH, C = {2} uF" -f $R_val, ($L_val*1000), ($C_val*1e6))
Write-Output ("fr = {0:F4} Hz, zeta = {1:F4}, tau = {2:F4} ms" -f $fr, $zeta, ($tau*1000))
Write-Output ""

function Get-SourceHarmonic([int]$n) {
    if ($n -eq 0) {
        return [PSCustomObject]@{ n=0; a=($Em/[Math]::PI); b=0.0; amp=($Em/[Math]::PI); phi_cos_deg=0.0; phi_sin_deg=90.0 }
    } elseif ($n -eq 1) {
        return [PSCustomObject]@{ n=1; a=0.0; b=($Em/2.0); amp=($Em/2.0); phi_cos_deg=-90.0; phi_sin_deg=0.0 }
    } elseif (($n % 2) -eq 0) {
        $an = -2.0 * $Em / ([Math]::PI * ($n * $n - 1.0))
        return [PSCustomObject]@{ n=$n; a=$an; b=0.0; amp=[Math]::Abs($an); phi_cos_deg=180.0; phi_sin_deg=-90.0 }
    } else {
        return [PSCustomObject]@{ n=$n; a=0.0; b=0.0; amp=0.0; phi_cos_deg=0.0; phi_sin_deg=0.0 }
    }
}

function Get-H([int]$n) {
    if ($n -eq 0) {
        return [PSCustomObject]@{ mag=0.0; phase_deg=0.0; c=[System.Numerics.Complex]::Zero }
    }
    $w = $n * $w0
    $num = New-Object System.Numerics.Complex (-$w * $w * $L_val * $C_val), 0.0
    $den = New-Object System.Numerics.Complex (1.0 - $w * $w * $L_val * $C_val), ($w * $L_val / $R_val)
    $H = [System.Numerics.Complex]::Divide($num, $den)
    $deg = $H.Phase * 180.0 / [Math]::PI
    if ($deg -lt 0) { $deg += 360.0 }
    return [PSCustomObject]@{ mag=$H.Magnitude; phase_deg=$deg; c=$H }
}

# Numerical integration check (midpoint rule over 10000 intervals) for a0, a1..a8, b1..b8
Write-Output "=== NUMERICAL INTEGRATION VERIFICATION OF FOURIER COEFFICIENTS ==="
$M = 10000
$dt = $Period / $M
foreach ($n in @(0,1,2,3,4,5,6,7,8)) {
    $sumA = 0.0; $sumB = 0.0
    for ($idx = 0; $idx -lt $M; $idx++) {
        $tm = ($idx + 0.5) * $dt
        $et = if ($tm -lt ($Period / 2.0)) { $Em * [Math]::Sin($w0 * $tm) } else { 0.0 }
        $sumA += $et * [Math]::Cos($n * $w0 * $tm) * $dt
        $sumB += $et * [Math]::Sin($n * $w0 * $tm) * $dt
    }
    $an_num = if ($n -eq 0) { $sumA / $Period } else { 2.0 * $sumA / $Period }
    $bn_num = 2.0 * $sumB / $Period
    $ana = Get-SourceHarmonic $n
    Write-Output ("n={0}: a_ana={1,10:F6} (num={2,10:F6}), b_ana={3,10:F6} (num={4,10:F6})" -f $n, $ana.a, $an_num, $ana.b, $bn_num)
}
Write-Output ""

Write-Output "=== HARMONIC TABLE (Non-zero AC harmonics n=1,2,4,6,8,10,12) ==="
$harmonics = @(1,2,4,6,8,10,12)
$rows = @()
foreach ($n in $harmonics) {
    $src = Get-SourceHarmonic $n
    $H   = Get-H $n
    $u_amp = $src.amp * $H.mag
    $psi_cos = $src.phi_cos_deg + $H.phase_deg
    while ($psi_cos -gt 180.0) { $psi_cos -= 360.0 }
    while ($psi_cos -le -180.0) { $psi_cos += 360.0 }
    $psi_sin = $src.phi_sin_deg + $H.phase_deg
    while ($psi_sin -gt 180.0) { $psi_sin -= 360.0 }
    while ($psi_sin -le -180.0) { $psi_sin += 360.0 }

    $row = [PSCustomObject]@{
        n = $n
        f_Hz = $n * $f0
        E_amp = $src.amp
        E_phi_sin = $src.phi_sin_deg
        E_phi_cos = $src.phi_cos_deg
        H_mag = $H.mag
        H_deg = $H.phase_deg
        U0_amp = $u_amp
        U0_psi_cos = $psi_cos
        U0_psi_sin = $psi_sin
    }
    $rows += $row
    Write-Output ("n={0,2} | f={1,4} Hz | En={2,8:F4} V (sin:{3,5:F0}d) | |H|={4,7:F4} < {5,7:F2}d | U0n={6,7:F4} V (cos:{7,7:F2}d, sin:{8,7:F2}d)" -f $n, $row.f_Hz, $row.E_amp, $row.E_phi_sin, $row.H_mag, $row.H_deg, $row.U0_amp, $row.U0_psi_cos, $row.U0_psi_sin)
}
Write-Output ""

# Parseval RMS
$rms3 = [Math]::Sqrt(0.5 * (($rows | Where-Object { $_.n -in @(1,2,4) } | ForEach-Object { $_.U0_amp * $_.U0_amp } | Measure-Object -Sum).Sum))
$rms5 = [Math]::Sqrt(0.5 * (($rows | Where-Object { $_.n -in @(1,2,4,6,8) } | ForEach-Object { $_.U0_amp * $_.U0_amp } | Measure-Object -Sum).Sum))

$sumSqAll = 0.0
foreach ($n in (1..400)) {
    $src = Get-SourceHarmonic $n
    if ($src.amp -gt 0) {
        $H = Get-H $n
        $u = $src.amp * $H.mag
        $sumSqAll += $u * $u
    }
}
$rmsInf = [Math]::Sqrt(0.5 * $sumSqAll)

# Time-domain evaluation over 1 period (4000 points) for 3h, 5h, and 400h (exact reference)
$Npts = 4000
$u3_vals = New-Object double[] $Npts
$u5_vals = New-Object double[] $Npts
$uInf_vals = New-Object double[] $Npts

$listAll = @(1) + (1..200 | ForEach-Object { 2 * $_ })
$hCache = @{}
foreach ($n in $listAll) {
    $src = Get-SourceHarmonic $n
    $H = Get-H $n
    $u = $src.amp * $H.mag
    $psi_rad = ($src.phi_cos_deg + $H.phase_deg) * [Math]::PI / 180.0
    $hCache[$n] = @{ amp=$u; psi=$psi_rad }
}

for ($idx = 0; $idx -lt $Npts; $idx++) {
    $tm = $idx * $Period / $Npts
    $v3 = 0.0; $v5 = 0.0; $vInf = 0.0
    foreach ($n in $listAll) {
        $val = $hCache[$n].amp * [Math]::Cos($n * $w0 * $tm + $hCache[$n].psi)
        $vInf += $val
        if ($n -le 4) { $v3 += $val }
        if ($n -le 8) { $v5 += $val }
    }
    $u3_vals[$idx] = $v3
    $u5_vals[$idx] = $v5
    $uInf_vals[$idx] = $vInf
}

function Get-Stats($arr, $ref) {
    $max = ($arr | Measure-Object -Maximum).Maximum
    $min = ($arr | Measure-Object -Minimum).Minimum
    $pp  = $max - $min
    $sumSq = 0.0; $errSq = 0.0; $refSq = 0.0
    for ($idx = 0; $idx -lt $arr.Length; $idx++) {
        $sumSq += $arr[$idx] * $arr[$idx]
        $d = $arr[$idx] - $ref[$idx]
        $errSq += $d * $d
        $refSq += $ref[$idx] * $ref[$idx]
    }
    $rms = [Math]::Sqrt($sumSq / $arr.Length)
    $rmse = [Math]::Sqrt($errSq / $arr.Length)
    $nrmse = ($rmse / [Math]::Sqrt($refSq / $arr.Length)) * 100.0
    return [PSCustomObject]@{ Max=$max; Min=$min; PP=$pp; RMS=$rms; RMSE=$rmse; NRMSE_pct=$nrmse }
}

$s3 = Get-Stats $u3_vals $uInf_vals
$s5 = Get-Stats $u5_vals $uInf_vals
$sInf = Get-Stats $uInf_vals $uInf_vals

Write-Output "=== THEORETICAL WAVEFORM STATS (Exact 1-period steady state) ==="
Write-Output ("3 harmonics (n=1,2,4):       Max={0:F4} V, Min={1:F4} V, Vpp={2:F4} V, RMS={3:F4} V (Parseval={4:F4} V), RMSE_vs_exact={5:F4} V ({6:F2}%)" -f $s3.Max, $s3.Min, $s3.PP, $s3.RMS, $rms3, $s3.RMSE, $s3.NRMSE_pct)
Write-Output ("5 harmonics (n=1,2,4,6,8):   Max={0:F4} V, Min={1:F4} V, Vpp={2:F4} V, RMS={3:F4} V (Parseval={4:F4} V), RMSE_vs_exact={5:F4} V ({6:F2}%)" -f $s5.Max, $s5.Min, $s5.PP, $s5.RMS, $rms5, $s5.RMSE, $s5.NRMSE_pct)
Write-Output ("Exact (200 even+n=1):        Max={0:F4} V, Min={1:F4} V, Vpp={2:F4} V, RMS={3:F4} V (Parseval={4:F4} V)" -f $sInf.Max, $sInf.Min, $sInf.PP, $sInf.RMS, $rmsInf)
