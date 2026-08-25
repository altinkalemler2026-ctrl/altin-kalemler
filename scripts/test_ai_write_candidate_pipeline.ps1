#requires -Version 5.1
<#
.SYNOPSIS
    Birlesik write-candidate self-test: STEP 01-09, tek komut, deterministik.

.DESCRIPTION
    - Yalnizca docs/project/ai-handoff/sandbox/selftest/runtime-<GUID>/ altinda
      fixture ve aday dosyalari uretir; hicbir kanonik veya gercek proje
      dosyasini DEGISTIRMEZ, SILMEZ, TASIMAZ.
    - validate_ai_write_candidate.ps1 salt-okunur validator'u cocuk powershell
      sureciyle calistirilir; TestMode yalnizca fixture gorev durumu icindir.
    - OpenCode/model/ag/DB/Docker/Supabase/git cagrisi YOKTUR.
    - Exit kodlari: 0 = AI_WRITE_CANDIDATE_PIPELINE_PASS,
                    2 = CANDIDATE_SELFTEST_FAILED,
                    3 = CANDIDATE_SELFTEST_PRECONDITION_FAILED.
#>

$ErrorActionPreference = 'Stop'

$runGuid = $null
$runtimeDir = $null
$selftestRoot = $null
$originalLocation = Get-Location

try {
    # --- Proje koku ---
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

    function Fail-Precondition {
        param([string]$Reason)
        Write-Host "CANDIDATE_SELFTEST_PRECONDITION_FAILED: $Reason"
        exit 3
    }
    function Fail-Step {
        param([string]$Step, [string]$Reason)
        Write-Host "CANDIDATE_SELFTEST_FAILED: ${Step}: $Reason"
        exit 2
    }

    function Get-JProp {
        # Unary virgul: tek ogeli diziler pipeline'da unwrap edilmemesi icin.
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -eq $prop) { return $null }
        $value = $prop.Value
        return , $value
    }

    function Get-Sha256HexFromFile {
        param([string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    function Get-Sha256HexFromBytes {
        param([byte[]]$Bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($Bytes)
            return (([System.BitConverter]::ToString($hashBytes)) -replace '-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function Invoke-ValidatorRun {
        param([string]$CandidateFile, [string]$StateFile)
        $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:validatorPath -CandidatePath $CandidateFile -TaskStatePath $StateFile -TestMode 2>&1)
        $code = $LASTEXITCODE
        $text = (($out | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join "`n")
        return [pscustomobject]@{ ExitCode = [int]$code; Output = $text }
    }

    function Save-VariantCandidate {
        param([string]$VariantFile, [scriptblock]$Mutate)
        $obj = Get-Content -LiteralPath $script:positiveCandFile -Raw | ConvertFrom-Json
        & $Mutate $obj
        ($obj | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $VariantFile -Encoding UTF8
        return $VariantFile
    }

    # --- ON KOSULLAR ---
    $canonicalTaskFile = Join-Path $projectRoot 'docs\project\ai-handoff\current-task.json'
    $taskStateSchema   = Join-Path $projectRoot 'docs\project\ai-handoff\task-state.schema.json'
    $candSchema        = Join-Path $projectRoot 'docs\project\ai-handoff\write-candidate.schema.json'
    $script:validatorPath = Join-Path $projectRoot 'scripts\validate_ai_write_candidate.ps1'

    foreach ($mustExist in @($canonicalTaskFile, $taskStateSchema, $candSchema, $validatorPath)) {
        if (-not (Test-Path -LiteralPath $mustExist -PathType Leaf)) {
            Fail-Precondition "zorunlu dosya bulunamadi: $mustExist"
        }
    }

    try {
        $canonical = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Fail-Precondition "kanonik current-task.json parse edilemedi: $($_.Exception.Message)"
    }

    $autoWriteFailover = Get-JProp (Get-JProp $canonical 'execution_policy') 'automatic_write_failover'
    if (-not ($autoWriteFailover -is [bool])) {
        Fail-Precondition "automatic_write_failover gercek boolean degil (tip=$($autoWriteFailover.GetType().Name))"
    }
    if ($autoWriteFailover -ne $false) {
        Fail-Precondition "automatic_write_failover false degil (deger=$autoWriteFailover)"
    }

    # Kanonik dosyalarin bütünlük referanslari (STEP 09 karsilastirmasi icin).
    $canonicalShaBefore = Get-Sha256HexFromFile $canonicalTaskFile
    $taskSchemaShaBefore = Get-Sha256HexFromFile $taskStateSchema
    $candSchemaShaBefore = Get-Sha256HexFromFile $candSchema

    # --- Benzersiz runtime klasoru (yalnizca selftest altinda) ---
    $runGuid = [guid]::NewGuid().ToString('N')
    $selftestRoot = Join-Path $projectRoot 'docs\project\ai-handoff\sandbox\selftest'
    # Self-test tarafindan olusturulmayan onceden var olan ogeler (varsa)
    # kaydedilir; STEP 09 yalnizca YENI olusan ogeleri denetler.
    $preExistingSelftest = @()
    if (Test-Path -LiteralPath $selftestRoot) {
        $preExistingSelftest = @(Get-ChildItem -LiteralPath $selftestRoot -Force | ForEach-Object { $_.Name })
    }
    $runtimeDir = Join-Path $selftestRoot ("runtime-" + $runGuid)
    New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
    if ($preExistingSelftest.Count -gt 0) {
        Write-Host ("CANDIDATE_SELFTEST_INFO: selftest altinda self-test disindan gelen ogeler: " + ($preExistingSelftest -join ', '))
    }

    # --- Sabit test verileri ---
    $fixtureRevision = 777
    $acceptanceCriterion = 'SAFE_CANDIDATE_VALIDATION_ONLY'
    $contentText = 'SAFE_CANDIDATE_VALIDATION_TEST'
    $relTargetFwd = ('docs/project/ai-handoff/sandbox/selftest/runtime-' + $runGuid + '/target.txt')

    # --- Fixture task state (kanonikten derin kopya, yalniz runtime icinde) ---
    $fixture = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Json -Depth 25 | ConvertFrom-Json
    $fixture.revision = $fixtureRevision
    $fixture.task_mode = 'write'
    $fixture.status = 'in_progress'
    $fixture.scope.allowed_paths = @($relTargetFwd)
    $fixture.task.acceptance_criteria = @($acceptanceCriterion)

    $fixtureStateFile = Join-Path $runtimeDir 'fixture-task-state.json'
    ($fixture | ConvertTo-Json -Depth 25) | Set-Content -LiteralPath $fixtureStateFile -Encoding UTF8

    # --- Pozitif create adayi ---
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($contentText)
    $contentB64 = [System.Convert]::ToBase64String($contentBytes)
    $contentSha = Get-Sha256HexFromBytes $contentBytes

    $positiveCand = [ordered]@{
        schema_version = 1
        task_revision = $fixtureRevision
        canonical_report = 'docs/reports/latest-faz5-security-validation.md'
        producer = [ordered]@{ role = 'primary'; model = 'opencode/big-pickle' }
        status = 'READY_FOR_VALIDATION'
        changes = @(
            [ordered]@{
                path = $relTargetFwd
                operation = 'create'
                expected_sha256 = $null
                content_base64 = $contentB64
                content_sha256 = $contentSha
            }
        )
        acceptance_criteria = @($acceptanceCriterion)
        safety = [ordered]@{
            production_accessed = $false
            db_command_ran = $false
            git_write_ran = $false
            secret_accessed = $false
            delete_requested = $false
            real_project_files_changed = $false
        }
    }

    $script:positiveCandFile = Join-Path $runtimeDir 'positive-create.json'
    ($positiveCand | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $script:positiveCandFile -Encoding UTF8

    # ================= STEP 01 — POWERSHELL SYNTAX =================
    $parseFailures = @()
    foreach ($psFile in @((Join-Path $projectRoot 'scripts\validate_ai_write_candidate.ps1'), (Join-Path $projectRoot 'scripts\test_ai_write_candidate_pipeline.ps1'))) {
        $tok = $null; $err = $null
        [System.Management.Automation.Language.Parser]::ParseFile($psFile, [ref]$tok, [ref]$err) | Out-Null
        if ($err -and $err.Count -gt 0) {
            $parseFailures += ("$psFile -> $($err[0].Message)")
        }
    }
    if ($parseFailures.Count -gt 0) {
        Fail-Step 'STEP_01' ($parseFailures -join ' | ')
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_01_PASS'

    # ================= STEP 02 — KANONIK TASK STATE =================
    $tsOut = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\validate_ai_task_state.ps1') 2>&1)
    $tsText = (($tsOut | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join "`n")
    $tsCode = $LASTEXITCODE
    if ([int]$tsCode -ne 0 -or -not $tsText.Contains('TASK_STATE_VALID')) {
        Fail-Step 'STEP_02' "exit=$tsCode output=$tsText"
    }
    $awfNow = Get-JProp (Get-JProp $canonical 'execution_policy') 'automatic_write_failover'
    if (-not ($awfNow -is [bool]) -or $awfNow -ne $false) {
        Fail-Step 'STEP_02' 'automatic_write_failover false degil'
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_02_PASS'

    # ================= STEP 03 — POZITIF CREATE ADAYI =================
    $run3 = Invoke-ValidatorRun -CandidateFile $script:positiveCandFile -StateFile $fixtureStateFile
    if ($run3.ExitCode -ne 0 -or -not $run3.Output.Contains('WRITE_CANDIDATE_VALID')) {
        Fail-Step 'STEP_03' "exit=$($run3.ExitCode) output=$($run3.Output)"
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_03_PASS'

    # ================= STEP 04 — YANLIS CONTENT HASH =================
    $badHashFile = Save-VariantCandidate -VariantFile (Join-Path $runtimeDir 'negative-bad-content-hash.json') -Mutate {
        param($obj)
        $obj.changes[0].content_sha256 = ('deadbeef' * 8)
    }
    $run4 = Invoke-ValidatorRun -CandidateFile $badHashFile -StateFile $fixtureStateFile
    if ($run4.ExitCode -ne 2 -or -not $run4.Output.Contains('WRITE_CANDIDATE_ERROR') -or -not $run4.Output.Contains('content_sha256 decode edilmis icerikle eslesmiyor')) {
        Fail-Step 'STEP_04' "exit=$($run4.ExitCode) output=$($run4.Output)"
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_04_PASS'

    # ================= STEP 05 — PATH ESCAPE / IZINSIZ YOL =================
    $escapeFile = Save-VariantCandidate -VariantFile (Join-Path $runtimeDir 'negative-path-escape.json') -Mutate {
        param($obj)
        $obj.changes[0].path = '../outside.txt'
    }
    $run5 = Invoke-ValidatorRun -CandidateFile $escapeFile -StateFile $fixtureStateFile
    if ($run5.ExitCode -ne 2 -or -not $run5.Output.Contains('WRITE_CANDIDATE_ERROR') -or -not $run5.Output.Contains('guvensiz yol')) {
        Fail-Step 'STEP_05' "exit=$($run5.ExitCode) output=$($run5.Output)"
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_05_PASS'

    # ================= STEP 06 — STALE REVISION =================
    $staleRevFile = Save-VariantCandidate -VariantFile (Join-Path $runtimeDir 'negative-stale-revision.json') -Mutate {
        param($obj)
        $obj.task_revision = ($fixtureRevision + 1)
    }
    $run6 = Invoke-ValidatorRun -CandidateFile $staleRevFile -StateFile $fixtureStateFile
    if ($run6.ExitCode -ne 2 -or -not $run6.Output.Contains('WRITE_CANDIDATE_ERROR') -or -not $run6.Output.Contains('task_revision current-task.revision ile ayni olmali')) {
        Fail-Step 'STEP_06' "exit=$($run6.ExitCode) output=$($run6.Output)"
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_06_PASS'

    # ================= STEP 07 — KAPALI GOREV DURUMU =================
    $closedFixture = Get-Content -LiteralPath $fixtureStateFile -Raw | ConvertFrom-Json
    $closedFixture.status = 'awaiting_human_task'
    $closedStateFile = Join-Path $runtimeDir 'fixture-task-state-closed.json'
    ($closedFixture | ConvertTo-Json -Depth 25) | Set-Content -LiteralPath $closedStateFile -Encoding UTF8

    $run7 = Invoke-ValidatorRun -CandidateFile $script:positiveCandFile -StateFile $closedStateFile
    if ($run7.ExitCode -ne 2 -or -not $run7.Output.Contains('WRITE_CANDIDATE_ERROR') -or -not $run7.Output.Contains('aday paket reddedilir')) {
        Fail-Step 'STEP_07' "exit=$($run7.ExitCode) output=$($run7.Output)"
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_07_PASS'

    # ================= STEP 08 — SAFETY IHLALI =================
    $safetyFile = Save-VariantCandidate -VariantFile (Join-Path $runtimeDir 'negative-safety-violation.json') -Mutate {
        param($obj)
        $obj.safety.real_project_files_changed = $true
    }
    $run8 = Invoke-ValidatorRun -CandidateFile $safetyFile -StateFile $fixtureStateFile
    if ($run8.ExitCode -ne 2 -or -not $run8.Output.Contains('WRITE_CANDIDATE_ERROR') -or -not $run8.Output.Contains('safety.real_project_files_changed gercek boolean false olmali')) {
        Fail-Step 'STEP_08' "exit=$($run8.ExitCode) output=$($run8.Output)"
    }
    Write-Host 'CANDIDATE_SELFTEST_STEP_08_PASS'

    # ================= STEP 09 — NO APPLICATION / DEGISMEZLIK =================
    $targetRealPath = Join-Path $projectRoot ('docs\project\ai-handoff\sandbox\selftest\runtime-' + $runGuid + '\target.txt')
    if (Test-Path -LiteralPath $targetRealPath) {
        Fail-Step 'STEP_09' "hedef dosya uygulandi: $targetRealPath"
    }

    $canonicalShaAfter = Get-Sha256HexFromFile $canonicalTaskFile
    if ($canonicalShaAfter -cne $canonicalShaBefore) {
        Fail-Step 'STEP_09' 'kanonik current-task.json SHA-256 degisti'
    }

    try {
        $canonicalReparse = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $awfFinal = Get-JProp (Get-JProp $canonicalReparse 'execution_policy') 'automatic_write_failover'
        if (-not ($awfFinal -is [bool]) -or $awfFinal -ne $false) {
            Fail-Step 'STEP_09' 'kanonik automatic_write_failover false degil'
        }
    }
    catch {
        Fail-Step 'STEP_09' "kanonik current-task.json yeniden parse edilemedi: $($_.Exception.Message)"
    }

    if ((Get-Sha256HexFromFile $taskStateSchema) -cne $taskSchemaShaBefore) {
        Fail-Step 'STEP_09' 'task-state.schema.json degisti'
    }
    if ((Get-Sha256HexFromFile $candSchema) -cne $candSchemaShaBefore) {
        Fail-Step 'STEP_09' 'write-candidate.schema.json degisti'
    }

    $selftestChildren = @(Get-ChildItem -LiteralPath $selftestRoot -Force)
    foreach ($child in $selftestChildren) {
        $isOurs = ($child.Name -ceq ("runtime-" + $runGuid))
        $isPreExisting = ($preExistingSelftest -ccontains $child.Name)
        if (-not $isOurs -and -not $isPreExisting) {
            Fail-Step 'STEP_09' "self-test tarafindan runtime disinda olusturulan oge: $($child.Name)"
        }
    }

    Write-Host 'CANDIDATE_SELFTEST_STEP_09_PASS'

    Write-Host 'AI_WRITE_CANDIDATE_PIPELINE_PASS'
    exit 0
}
finally {
    # --- Guvenli temizlik: yalnizca dogrulanmis tam runtime klasoru ---
    try {
        if ($null -ne $runtimeDir -and (Test-Path -LiteralPath $runtimeDir)) {
            $resolvedRt = (Resolve-Path -LiteralPath $runtimeDir).Path
            $resolvedSelf = (Resolve-Path -LiteralPath $selftestRoot).Path
            $expectedName = "runtime-" + $runGuid
            $selfPrefix = $resolvedSelf.TrimEnd('\', '/')
            if (-not $resolvedRt.StartsWith($selfPrefix + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'runtime klasoru selftest kokunde degil'
            }
            $actualName = $resolvedRt.Substring($selfPrefix.Length).Trim('\', '/')
            $underSelf = (($resolvedRt.TrimEnd('\', '/') + '\').StartsWith(($resolvedSelf.TrimEnd('\', '/') + '\'), [System.StringComparison]::OrdinalIgnoreCase))
            $notProjectRoot = ($resolvedRt.TrimEnd('\', '/') -ine $projectRoot.TrimEnd('\', '/'))
            $notSelfRoot = ($resolvedRt.TrimEnd('\', '/') -ine $resolvedSelf.TrimEnd('\', '/'))
            if (($actualName -ceq $expectedName) -and $underSelf -and $notProjectRoot -and $notSelfRoot) {
                Remove-Item -LiteralPath $resolvedRt -Recurse -Force
                if (Test-Path -LiteralPath $resolvedRt) {
                    Write-Host 'CANDIDATE_SELFTEST_RUNTIME_CLEANUP_INCOMPLETE'
                } else {
                    Write-Host 'CANDIDATE_SELFTEST_RUNTIME_CLEANED'
                }
            } else {
                Write-Host 'CANDIDATE_SELFTEST_RUNTIME_CLEANUP_SKIPPED_UNSAFE_PATH'
            }
        }
    }
    catch {
        Write-Host "CANDIDATE_SELFTEST_RUNTIME_CLEANUP_WARNING: $($_.Exception.Message)"
    }
    Set-Location -LiteralPath $originalLocation.Path
}
