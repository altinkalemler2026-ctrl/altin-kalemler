#requires -Version 5.1
<#
.SYNOPSIS
    Guvenli sandbox yazma failover testi calistiricisi.
.DESCRIPTION
    Primary : opencode run --command ai-sandbox-write-primary  (Ox Alpha)
    Fallback: opencode run --command ai-sandbox-write-fallback (MiMo)

    Primary yalnizca asagidaki kosullarin TAMAMinda PASS sayilir:
      - native exit code 0
      - docs/project/ai-handoff/sandbox/primary-result.json mevcut
      - JSON parse ediliyor
      - schema_version=1, test_type=sandbox_write_failover
      - writer=primary, status=PASS
      - scope=docs/project/ai-handoff/sandbox-only
      - model bos olmayan string
      - production_accessed / db_command_ran / git_write_ran /
        real_project_files_changed alanlarinin tamami false

    Gercek provider basarisizlik imzasi (network_error, Provider finish_reason:
    error/network, HTTP 429, 429 Too Many Requests, rate limit
    exceeded/exhausted/reached, quota exceeded/exhausted/reached,
    request/provider/model satirinda timeout/timed out), sifir olmayan exit code
    veya gecersiz sonuc varsa fallback calistirilir. -ForceFallback ile primary
    atlanir. Yedek ayni kontrollerle fallback-result.json uzerinden dogrulanir.

    On kosullar:
      - opencode.cmd veya opencode bulunmali
      - scripts/validate_ai_task_state.ps1 bulunmali (yalniz VARLIK kontrolu;
        script calistirilmaz)
      - docs/project/ai-handoff/current-task.json icinde execution_policy.
        automatic_write_failover kesinlikle false olmali. Bu deger HICBIR
        kosulda degistirilmez; dosya yalnizca okunur.
.NOTES
    - Sonuc dosyalari ASLA silinmez, birlestirilmez, tasinmaz, yeniden
      adlandirilmaz; otomatik merge, patch uygulama veya promotion YAPILMAZ.
      Hicbir sonuc gercek proje dosyasina uygulanmaz.
    - Script ag, DB, Docker, Supabase ve git komutu CALISTIRMAZ;
      Invoke-Expression ve Start-Process KULLANMAZ.
    - Calistirma suresince BOM'suz UTF-8 kodlama ve kapali ANSI renk kullanir;
      onceki degerleri finally blokunda geri yukler.
    - PowerShell 5.1'in 2>&1 yonlendirmesinde urettigi NativeCommandError
      sarmalayicilari ekrana yazilmaz; ham metin uzerinde gercek hata kanitlari
      yine de algilanir.
    - Exit kodlari: 0 = SANDBOX_PRIMARY_PASS veya SANDBOX_FALLBACK_PASS,
      2 = SANDBOX_WRITE_FAILOVER_FAILED, 3 = on kosul eksikligi.
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

    # --- 3) On kosullar ---
    $opencodeCommand = Get-Command 'opencode.cmd' -ErrorAction SilentlyContinue
    if ($null -eq $opencodeCommand) {
        $opencodeCommand = Get-Command 'opencode' -ErrorAction SilentlyContinue
    }
    if ($null -eq $opencodeCommand) {
        Write-Host 'PRECONDITION_MISSING: opencode komutu bulunamadi.'
        exit 3
    }
    $opencodeExecutable = $opencodeCommand.Source

    $validatorPath = Join-Path $projectRoot 'scripts\validate_ai_task_state.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath)) {
        Write-Host 'PRECONDITION_MISSING: validate_ai_task_state.ps1 bulunamadi:'
        Write-Host $validatorPath
        exit 3
    }

    $currentTaskPath = Join-Path $projectRoot 'docs\project\ai-handoff\current-task.json'
    if (-not (Test-Path -LiteralPath $currentTaskPath)) {
        Write-Host 'PRECONDITION_MISSING: current-task.json bulunamadi:'
        Write-Host $currentTaskPath
        exit 3
    }
    $taskState = $null
    try {
        $taskState = Get-Content -LiteralPath $currentTaskPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "PRECONDITION_MISSING: current-task.json parse edilemedi: $($_.Exception.Message)"
        exit 3
    }

    # Global automatic_write_failover kesinlikle false olmali; deger OKUNUR,
    # hicbir kosulda DEGISTIRILMEZ.
    function Get-JProp {
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $p = $Object.PSObject.Properties[$Name]
        if ($null -eq $p) { return $null }
        return $p.Value
    }

    $execPolicy = Get-JProp -Object $taskState -Name 'execution_policy'
    $autoWriteFailover = Get-JProp -Object $execPolicy -Name 'automatic_write_failover'
    if (($null -eq $autoWriteFailover) -or ($autoWriteFailover -isnot [bool]) -or ($autoWriteFailover -ne $false)) {
        Write-Host 'PRECONDITION_MISSING: execution_policy.automatic_write_failover false olmali.'
        Write-Host 'Global ayar insan onayi olmadan degistirilemez; sandbox testi bu ayarla sinirlidir.'
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

    # Sandbox sonuc dosyasini dogrular. Dosya ASLA silinmez veya
    # degistirilmez; yalnizca okunur.
    function Test-SandboxResultFile {
        param([string]$Path, [string]$ExpectedWriter)
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        try {
            $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        catch {
            return $false
        }
        if ($null -eq $json) { return $false }
        if ((Get-JProp -Object $json -Name 'schema_version') -ne 1) { return $false }
        if ((Get-JProp -Object $json -Name 'test_type') -cne 'sandbox_write_failover') { return $false }
        if ((Get-JProp -Object $json -Name 'writer') -cne $ExpectedWriter) { return $false }
        if ((Get-JProp -Object $json -Name 'status') -cne 'PASS') { return $false }
        if ((Get-JProp -Object $json -Name 'scope') -cne 'docs/project/ai-handoff/sandbox-only') { return $false }
        $modelValue = Get-JProp -Object $json -Name 'model'
        if (-not ($modelValue -is [string]) -or [string]::IsNullOrWhiteSpace($modelValue)) { return $false }
        foreach ($flag in @('production_accessed', 'db_command_ran', 'git_write_ran', 'real_project_files_changed')) {
            $v = Get-JProp -Object $json -Name $flag
            if (($v -isnot [bool]) -or ($v -ne $false)) { return $false }
        }
        return $true
    }

    $primaryResultPath   = Join-Path $projectRoot 'docs\project\ai-handoff\sandbox\primary-result.json'
    $fallbackResultPath  = Join-Path $projectRoot 'docs\project\ai-handoff\sandbox\fallback-result.json'

    # --- 4) Primary (Ox Alpha) ---
    $primaryPassed = $false

    if ($ForceFallback) {
        # Yalnizca test amacli: primary cagrisi atlanir, dogrudan fallback'e gidilir.
        Write-Host 'PRIMARY_SKIPPED: -ForceFallback aktif; primary cagrisi atlandi.'
    }
    else {
        Write-Host 'SANDBOX_PRIMARY_START: opencode run --command ai-sandbox-write-primary'
        $primaryRaw = @(& $opencodeExecutable run --command ai-sandbox-write-primary 2>&1)
        $primaryExitCode = $LASTEXITCODE
        $primaryVisible = Format-ToolOutput -CapturedOutput $primaryRaw
        if ($primaryVisible) { Write-Host $primaryVisible }

        # Tespit ham metin uzerinde yapilir; NativeCommandError gurultusu filtrelenmez.
        $primaryRawText = ConvertTo-RawText -CapturedOutput $primaryRaw
        $hasFailureSig = Test-ProviderFailureSignature -Text $primaryRawText
        $resultOk = Test-SandboxResultFile -Path $primaryResultPath -ExpectedWriter 'primary'

        if (($primaryExitCode -eq 0) -and (-not $hasFailureSig) -and $resultOk) {
            Write-Host 'SANDBOX_PRIMARY_PASS'
            $primaryPassed = $true
        }
        else {
            # Not: primary-result.json varsa bile SILINMEZ; fallback sonucla
            # BIRLESTIRILMEZ.
            Write-Host ('SANDBOX_PRIMARY_FAILED (exit={0}, resultValid={1}, providerFailure={2})' -f $primaryExitCode, $resultOk, $hasFailureSig)
        }
    }

    if ($primaryPassed) {
        exit 0
    }

    # --- 5) Failover: MiMo ---
    Write-Host 'SANDBOX_FAILOVER_START: opencode run --command ai-sandbox-write-fallback'
    $fallbackRaw = @(& $opencodeExecutable run --command ai-sandbox-write-fallback 2>&1)
    $fallbackExitCode = $LASTEXITCODE
    $fallbackVisible = Format-ToolOutput -CapturedOutput $fallbackRaw
    if ($fallbackVisible) { Write-Host $fallbackVisible }

    $fallbackRawText = ConvertTo-RawText -CapturedOutput $fallbackRaw
    $fallbackHasFailureSig = Test-ProviderFailureSignature -Text $fallbackRawText
    $fallbackResultOk = Test-SandboxResultFile -Path $fallbackResultPath -ExpectedWriter 'fallback'

    if (($fallbackExitCode -eq 0) -and (-not $fallbackHasFailureSig) -and $fallbackResultOk) {
        Write-Host 'SANDBOX_FALLBACK_PASS'
        exit 0
    }
    else {
        Write-Host ('SANDBOX_WRITE_FAILOVER_FAILED (exit={0}, resultValid={1}, providerFailure={2})' -f $fallbackExitCode, $fallbackResultOk, $fallbackHasFailureSig)
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
