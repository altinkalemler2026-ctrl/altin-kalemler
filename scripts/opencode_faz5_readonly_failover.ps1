#requires -Version 5.1
<#
.SYNOPSIS
    Faz 5 salt okunur otomatik failover calistiricisi.
.DESCRIPTION
    Primary: opencode run --command faz5-qa  (Ox Alpha)
    Cikti "15 PASS / 0 FAIL" kaniti iceriyorsa basariyla biter.
    Gercek provider basarisizlik imzasi (network_error, HTTP 429,
    429 Too Many Requests, rate limit exceeded/exhausted/reached,
    quota exceeded/exhausted/reached, request/provider/model satirinda
    timeout/timed out, Provider finish_reason: error/network), sifir olmayan
    exit code veya 15/0 kanidi yoksa otomatik olarak
    opencode run --command faz5-handoff (MiMo) calistirilir.
    MiMo ciktisi yalnizca HANDOFF_STATUS: PASS, NEXT_ACTION: AWAIT_HUMAN_TASK
    ve FILES_CHANGED: NONE iceriyorsa failover basarili sayilir.
.NOTES
    - Yalnizca ekrana cikti verir; log/state/todo/rapor dosyasi olusturmaz.
    - Docker/DB/Supabase/git komutu, Invoke-Expression, Start-Process ve
      harici ag cagrisi kullanmaz.
    - Calistirma suresince BOM'suz UTF-8 kodlama ve kapali ANSI renk kullanir;
      onceki degerleri finally blokunda geri yukler.
    - PowerShell 5.1'in 2>&1 yonlendirmesinde urettigi NativeCommandError
      sarmalayicilari ekrana yazilmaz; ham metin uzerinde gercek hata kanitlari
      yine de algilanir.
#>
param([switch]$ForceFallback)

# --- 1) Mevcut degerleri sakla ---
$originalLocation = Get-Location
$originalConsoleEncoding = [Console]::OutputEncoding
$originalOutputEncoding = $OutputEncoding
$hadNoColor = Test-Path -LiteralPath 'Env:NO_COLOR'
$hadForceColor = Test-Path -LiteralPath 'Env:FORCE_COLOR'
$originalNoColor = $null
$originalForceColor = $null
if ($hadNoColor) { $originalNoColor = $env:NO_COLOR }
if ($hadForceColor) { $originalForceColor = $env:FORCE_COLOR }

try {
    # --- 2) BOM'suz UTF-8 kodlama + renk kapama ---
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
    $env:NO_COLOR = '1'
    $env:FORCE_COLOR = '0'

    # --- Proje kokunu bul ve gec ---
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    Set-Location -LiteralPath $projectRoot

    $canonicalReport = Join-Path $projectRoot 'docs\reports\latest-faz5-security-validation.md'

    # --- 3) OpenCode calistirilabiliri coz (on kosul) ---
    $opencodeCommand = Get-Command 'opencode.cmd' -ErrorAction SilentlyContinue
    if ($null -eq $opencodeCommand) {
        $opencodeCommand = Get-Command 'opencode' -ErrorAction SilentlyContinue
    }
    if ($null -eq $opencodeCommand) {
        Write-Host 'PRECONDITION_MISSING: opencode komutu bulunamadi.'
        exit 3
    }
    $opencodeExecutable = $opencodeCommand.Source

    if (-not (Test-Path -LiteralPath $canonicalReport)) {
        Write-Host 'PRECONDITION_MISSING: kanonik rapor bulunamadi:'
        Write-Host $canonicalReport
        exit 3
    }

    # --- Gercek provider basarisizlik kaliplari (daraltilmis; buyuk/kucuk harf duyarsiz) ---
    # Tek basina 'rate limit', 'quota', 'timeout', 'FAIL' veya kod/fonksiyon adi icindeki
    # '_rate_limit' benzeri gecisler basarisizlik SAYILMAZ.
    function Test-ProviderFailureSignature {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        foreach ($line in ($Text -split "(`r)?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match 'network_error') { return $true }
            if (($line -match 'provider\s+finish_reason\s*:') -and ($line -match 'error|network')) { return $true }
            if ($line -match 'http\s+429') { return $true }
            if ($line -match '429\s+too\s+many\s+requests') { return $true }
            if ($line -match 'rate\s+limit\s+(exceeded|exhausted|reached)') { return $true }
            if ($line -match 'quota\s+(exceeded|exhausted|reached)') { return $true }
            if (($line -match '\b(request|provider|model)\b') -and ($line -match 'timeout|timed\s+out')) { return $true }
        }
        return $false
    }

    function Test-PrimaryProof {
        param([string]$Text)
        return [bool]($Text -match '15\s*PASS\s*/\s*0\s*FAIL')
    }

    # Yakalanan akisin ham metnini uretir (tum kayitlar; tespit icin).
    function ConvertTo-RawText {
        param($CapturedOutput)
        $parts = foreach ($item in $CapturedOutput) {
            if ($null -ne $item) { $item.ToString() }
        }
        return ($parts -join "`n")
    }

    # Kullaniciya yazilacak gorunur metni uretir:
    # FullyQualifiedErrorId'i tam olarak 'NativeCommandError' olan ErrorRecord
    # sarmalayicilari gizlenir; diger tum cikti aynen korunur.
    function Format-ToolOutput {
        param($CapturedOutput)
        $visibleLines = foreach ($item in $CapturedOutput) {
            if ($null -eq $item) { continue }
            if (($item -is [System.Management.Automation.ErrorRecord]) -and
                ($item.FullyQualifiedErrorId -eq 'NativeCommandError')) {
                continue
            }
            $item.ToString()
        }
        return ($visibleLines -join "`n")
    }

    $primaryPassed = $false

    if ($ForceFallback) {
        # Yalnizca test amacli: Ox cagrisi atlanir, dogrudan MiMo handoff'a gidilir.
        Write-Host 'PRIMARY_SKIPPED: -ForceFallback aktif; Ox cagrisi atlandi.'
    }
    else {
        Write-Host 'PRIMARY_START: opencode run --command faz5-qa'
        $primaryRaw = @(& $opencodeExecutable run --command faz5-qa 2>&1)
        $primaryExitCode = $LASTEXITCODE
        $primaryVisible = Format-ToolOutput -CapturedOutput $primaryRaw
        if ($primaryVisible) { Write-Host $primaryVisible }

        # Tespit ham metin uzerinde yapilir; NativeCommandError gurultusu filtrelenmez.
        $primaryRawText = ConvertTo-RawText -CapturedOutput $primaryRaw
        $hasProof      = Test-PrimaryProof -Text $primaryRawText
        $hasFailureSig = Test-ProviderFailureSignature -Text $primaryRawText

        if (($primaryExitCode -eq 0) -and $hasProof -and (-not $hasFailureSig)) {
            Write-Host 'PRIMARY_PASS'
            $primaryPassed = $true
        }
        else {
            Write-Host ('PRIMARY_FAILED (exit={0}, proof={1}, providerFailure={2})' -f $primaryExitCode, $hasProof, $hasFailureSig)
        }
    }

    if ($primaryPassed) {
        exit 0
    }

    # --- Failover: MiMo handoff ---
    Write-Host 'FAILOVER_START: opencode run --command faz5-handoff'
    $fallbackRaw = @(& $opencodeExecutable run --command faz5-handoff 2>&1)
    $fallbackExitCode = $LASTEXITCODE
    $fallbackVisible = Format-ToolOutput -CapturedOutput $fallbackRaw
    if ($fallbackVisible) { Write-Host $fallbackVisible }

    $fallbackRawText = ConvertTo-RawText -CapturedOutput $fallbackRaw
    $statusOk  = [bool]($fallbackRawText -match 'HANDOFF_STATUS:\s*PASS')
    $nextOk    = [bool]($fallbackRawText -match 'NEXT_ACTION:\s*AWAIT_HUMAN_TASK')
    $filesOk   = [bool]($fallbackRawText -match 'FILES_CHANGED:\s*NONE')

    if (($fallbackExitCode -eq 0) -and $statusOk -and $nextOk -and $filesOk) {
        Write-Host 'FAILOVER_PASS'
        exit 0
    }
    else {
        Write-Host ('FAILOVER_FAILED (exit={0}, statusPass={1}, awaitHuman={2}, filesNone={3})' -f $fallbackExitCode, $statusOk, $nextOk, $filesOk)
        exit 2
    }
}
finally {
    # --- Onceki durumu geri yukle ---
    Set-Location -LiteralPath $originalLocation.Path
    [Console]::OutputEncoding = $originalConsoleEncoding
    $OutputEncoding = $originalOutputEncoding
    if ($hadNoColor) {
        $env:NO_COLOR = $originalNoColor
    }
    else {
        Remove-Item -LiteralPath 'Env:NO_COLOR' -ErrorAction SilentlyContinue
    }
    if ($hadForceColor) {
        $env:FORCE_COLOR = $originalForceColor
    }
    else {
        Remove-Item -LiteralPath 'Env:FORCE_COLOR' -ErrorAction SilentlyContinue
    }
}
