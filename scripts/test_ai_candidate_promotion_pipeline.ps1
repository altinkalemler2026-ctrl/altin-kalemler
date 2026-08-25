#requires -Version 5.1
<#
.SYNOPSIS
    Sandbox apply kapisinin birlesik promotion/rollback self-testi (STEP 01-10).

.DESCRIPTION
    - Yalnizca docs/project/ai-handoff/sandbox/selftest/runtime-<GUID>/ icinde
      fixture uretir; kanonik dosyalari SHA-256 ile degismezlik denetimine tabi
      tutar; hicbir gercek proje dosyasina uygulama yapmaz.
    - OpenCode/model, ag, DB/Docker/Supabase ve GIT cagrisi YOKTUR.
#>

$ErrorActionPreference = 'Stop'

$runGuid = $null
$runtimeDir = $null
$selftestRoot = $null
$originalLocation = Get-Location
$script:SawExitFive = $false

try {
    # --- Proje koku ve yardimcilar ---
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

    function Fail-Precondition {
        param([string]$Reason)
        Write-Host "PROMOTION_SELFTEST_PRECONDITION_FAILED: $Reason"
        exit 3
    }
    function Fail-Step {
        param([string]$Step, [string]$Reason)
        Write-Host "PROMOTION_SELFTEST_FAILED: ${Step}: $Reason"
        exit 2
    }

    function Get-JProp {
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
            return (([System.BitConverter]::ToString($sha.ComputeHash($Bytes))) -replace '-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function Test-BytesEqual {
        param([byte[]]$A, [byte[]]$B)
        if ($null -eq $A -or $null -eq $B) { return ($null -eq $A -and $null -eq $B) }
        if ($A.Length -ne $B.Length) { return $false }
        return [System.Linq.Enumerable]::SequenceEqual([byte[]]$A, [byte[]]$B)
    }

    function New-CandidateJsonText {
        param([object[]]$Changes, [int]$RevisionValue, [string[]]$Criteria)
        $cand = [ordered]@{
            schema_version = 1
            task_revision = $RevisionValue
            canonical_report = 'docs/reports/latest-faz5-security-validation.md'
            producer = [ordered]@{ role = 'primary'; model = 'opencode/big-pickle' }
            status = 'READY_FOR_VALIDATION'
            changes = $Changes
            acceptance_criteria = $Criteria
            safety = [ordered]@{
                production_accessed = $false
                db_command_ran = $false
                git_write_ran = $false
                secret_accessed = $false
                delete_requested = $false
                real_project_files_changed = $false
            }
        }
        return (($cand | ConvertTo-Json -Depth 12) + "`n")
    }

    function New-ChangeEntry {
        param([string]$RelPathFwd, [string]$Operation, [string]$ContentText, [object]$ExpectedSha = $null)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($ContentText)
        $sha = Get-Sha256HexFromBytes $bytes
        $b64 = [System.Convert]::ToBase64String($bytes)
        return [ordered]@{
            path = $RelPathFwd
            operation = $Operation
            expected_sha256 = $ExpectedSha
            content_base64 = $b64
            content_sha256 = $sha
        }
    }

    function Write-TextFileUtf8 {
        param([string]$Path, [string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($true)))
        return $Path
    }

    function Invoke-ApplyRun {
        param([string]$CandidateFile, [string]$StateFile, [string]$Token, [int]$InjectAfter = 0)
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:applyScript,
            '-CandidatePath', $CandidateFile, '-TaskStatePath', $StateFile,
            '-ApprovalToken', $Token, '-TestMode')
        if ($InjectAfter -gt 0) { $args += @('-InjectFailureAfterWrite', [string]$InjectAfter) }
        $out = @(& powershell.exe @args 2>&1)
        $code = $LASTEXITCODE
        $text = (($out | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join "`n")
        if ([int]$code -eq 5) {
            $script:SawExitFive = $true
            Write-Host 'PROMOTION_SELFTEST_CRITICAL: ROLLBACK_FAILED'
            exit 5
        }
        return [pscustomobject]@{ ExitCode = [int]$code; Output = $text }
    }

    # --- ON KOSULLAR ---
    $canonicalTaskFile = Join-Path $projectRoot 'docs\project\ai-handoff\current-task.json'
    $taskStateSchema   = Join-Path $projectRoot 'docs\project\ai-handoff\task-state.schema.json'
    $candSchema        = Join-Path $projectRoot 'docs\project\ai-handoff\write-candidate.schema.json'
    $script:validatorScript = Join-Path $projectRoot 'scripts\validate_ai_write_candidate.ps1'
    $script:candidatePipeline = Join-Path $projectRoot 'scripts\test_ai_write_candidate_pipeline.ps1'
    $script:applyScript = Join-Path $projectRoot 'scripts\apply_ai_write_candidate_sandbox.ps1'

    foreach ($mustExist in @($canonicalTaskFile, $taskStateSchema, $candSchema, $script:validatorScript, $script:candidatePipeline, $script:applyScript)) {
        if (-not (Test-Path -LiteralPath $mustExist -PathType Leaf)) {
            Fail-Precondition "zorunlu dosya bulunamadi: $mustExist"
        }
    }

    # Kanonik baslangic hash'leri (STEP 10 karsilastirmasi)
    $hashCurrentBefore = Get-Sha256HexFromFile $canonicalTaskFile
    $hashStateSchemaBefore = Get-Sha256HexFromFile $taskStateSchema
    $hashCandSchemaBefore = Get-Sha256HexFromFile $candSchema
    $hashValidatorBefore = Get-Sha256HexFromFile $script:validatorScript

    try {
        $canonical = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Fail-Precondition "kanonik current-task.json parse hatasi: $($_.Exception.Message)"
    }
    $awfStart = Get-JProp (Get-JProp $canonical 'execution_policy') 'automatic_write_failover'
    if (-not ($awfStart -is [bool]) -or $awfStart -ne $false) {
        Fail-Precondition 'automatic_write_failover baslangicta gercek boolean false degil'
    }

    # --- Runtime klasoru + selftest snapshot ---
    $runGuid = [guid]::NewGuid().ToString('N')
    $selftestRoot = Join-Path $projectRoot 'docs\project\ai-handoff\sandbox\selftest'
    $preExistingSelftest = @()
    if (Test-Path -LiteralPath $selftestRoot) {
        $preExistingSelftest = @(Get-ChildItem -LiteralPath $selftestRoot -Force | ForEach-Object { $_.Name })
    }
    $runtimeDir = Join-Path $selftestRoot ("runtime-" + $runGuid)
    New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

    # --- Sabitler ---
    $fixtureRevision = 888
    $criteriaList = @('SAFE_PROMOTION_PIPELINE_TEST')
    $relT1 = ("docs/project/ai-handoff/sandbox/selftest/runtime-" + $runGuid + "/target1.txt")
    $relT2 = ("docs/project/ai-handoff/sandbox/selftest/runtime-" + $runGuid + "/target2.txt")
    $relT3 = ("docs/project/ai-handoff/sandbox/selftest/runtime-" + $runGuid + "/nested/target3.txt")
    $fullT1 = Join-Path $runtimeDir 'target1.txt'
    $fullT2 = Join-Path $runtimeDir 'target2.txt'
    $fullT3 = Join-Path $runtimeDir 'nested\target3.txt'

    # --- Fixture task state (iki hedefli, nested parent dahil) ---
    $fixture = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Json -Depth 25 | ConvertFrom-Json
    $fixture.revision = $fixtureRevision
    $fixture.task_mode = 'write'
    $fixture.status = 'in_progress'
    $fixture.scope.allowed_paths = @($relT1, $relT2, $relT3)
    $fixture.task.acceptance_criteria = $criteriaList

    $fixtureStateFile = Write-TextFileUtf8 -Path (Join-Path $runtimeDir 'fixture-task-state.json') `
        -Text (($fixture | ConvertTo-Json -Depth 25) + "`n")

    # ================= STEP 01 — SYNTAX =================
    $parseFailures = @()
    foreach ($psFile in @($script:applyScript, (Join-Path $projectRoot 'scripts\test_ai_candidate_promotion_pipeline.ps1'), $script:validatorScript)) {
        $tok = $null; $err = $null
        [System.Management.Automation.Language.Parser]::ParseFile($psFile, [ref]$tok, [ref]$err) | Out-Null
        if ($err -and $err.Count -gt 0) { $parseFailures += ("$psFile -> $($err[0].Message)") }
    }
    if ($parseFailures.Count -gt 0) { Fail-Step 'STEP_01' ($parseFailures -join ' | ') }
    Write-Host 'PROMOTION_SELFTEST_STEP_01_PASS'

    # ================= STEP 02 — MEVCUT CANDIDATE PIPELINE =================
    $cpOut = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:candidatePipeline 2>&1)
    $cpCode = $LASTEXITCODE
    $cpText = (($cpOut | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join "`n")
    if ([int]$cpCode -ne 0 -or -not $cpText.Contains('AI_WRITE_CANDIDATE_PIPELINE_PASS')) {
        Fail-Step 'STEP_02' "exit=$cpCode output=$cpText"
    }
    Write-Host 'PROMOTION_SELFTEST_STEP_02_PASS'

    # ================= STEP 03 — ONAY TOKEN'I REDDI =================
    $contentA = 'PROMOTION_TARGET_ALPHA_CONTENT'
    $createA = New-ChangeEntry -RelPathFwd $relT1 -Operation 'create' -ContentText $contentA -ExpectedSha $null
    $candAFile = Write-TextFileUtf8 -Path (Join-Path $runtimeDir 'candidate-create-a.json') `
        -Text (New-CandidateJsonText -Changes @($createA) -RevisionValue $fixtureRevision -Criteria $criteriaList)

    $shaA = Get-Sha256HexFromBytes ([System.Text.Encoding]::UTF8.GetBytes($contentA))
    $runBad = Invoke-ApplyRun -CandidateFile $candAFile -StateFile $fixtureStateFile -Token 'APPROVE_SANDBOX_CANDIDATE:WRONG'
    if ($runBad.ExitCode -ne 2 -or -not $runBad.Output.Contains('SANDBOX_APPLY_REJECTED: APPROVAL_TOKEN_INVALID')) {
        Fail-Step 'STEP_03' "exit=$($runBad.ExitCode) output=$($runBad.Output)"
    }
    if (Test-Path -LiteralPath $fullT1) { Fail-Step 'STEP_03' 'yanlis token ile target olustu' }
    Write-Host 'PROMOTION_SELFTEST_STEP_03_PASS'

    # ================= STEP 04 — GECERLI CREATE =================
    function Get-ApprovalTokenForFile {
        param([string]$File)
        return ("APPROVE_SANDBOX_CANDIDATE:" + $fixtureRevision + ":" + (Get-Sha256HexFromFile $File))
    }

    $tokenA = Get-ApprovalTokenForFile -File $candAFile
    $runOk = Invoke-ApplyRun -CandidateFile $candAFile -StateFile $fixtureStateFile -Token $tokenA
    if ($runOk.ExitCode -ne 0 -or -not $runOk.Output.Contains('SANDBOX_CANDIDATE_APPLIED')) {
        Fail-Step 'STEP_04' "exit=$($runOk.ExitCode) output=$($runOk.Output)"
    }
    if (-not (Test-Path -LiteralPath $fullT1 -PathType Leaf)) { Fail-Step 'STEP_04' 'target1 olusmadi' }
    $t1ShaAfterCreate = Get-Sha256HexFromFile $fullT1
    if ($t1ShaAfterCreate -cne $shaA) { Fail-Step 'STEP_04' "target hash adayla ayni degil: $t1ShaAfterCreate" }
    Write-Host 'PROMOTION_SELFTEST_STEP_04_PASS'

    # ================= STEP 05 — CREATE REPLAY REDDI =================
    $runReplay = Invoke-ApplyRun -CandidateFile $candAFile -StateFile $fixtureStateFile -Token $tokenA
    if ($runReplay.ExitCode -ne 2 -or -not $runReplay.Output.Contains('SANDBOX_APPLY_REJECTED')) {
        Fail-Step 'STEP_05' "exit=$($runReplay.ExitCode) output=$($runReplay.Output)"
    }
    if ((Get-Sha256HexFromFile $fullT1) -cne $shaA) { Fail-Step 'STEP_05' 'replay reddinde target degisti' }
    Write-Host 'PROMOTION_SELFTEST_STEP_05_PASS'

    # ================= STEP 06 — GECERLI REPLACE =================
    $contentB = 'PROMOTION_TARGET_BETA_CONTENT'
    $replaceB = New-ChangeEntry -RelPathFwd $relT1 -Operation 'replace' -ContentText $contentB -ExpectedSha $shaA
    $candBFile = Write-TextFileUtf8 -Path (Join-Path $runtimeDir 'candidate-replace-b.json') `
        -Text (New-CandidateJsonText -Changes @($replaceB) -RevisionValue $fixtureRevision -Criteria $criteriaList)
    $shaB = Get-Sha256HexFromBytes ([System.Text.Encoding]::UTF8.GetBytes($contentB))

    $runB = Invoke-ApplyRun -CandidateFile $candBFile -StateFile $fixtureStateFile -Token (Get-ApprovalTokenForFile -File $candBFile)
    if ($runB.ExitCode -ne 0 -or -not $runB.Output.Contains('SANDBOX_CANDIDATE_APPLIED')) {
        Fail-Step 'STEP_06' "exit=$($runB.ExitCode) output=$($runB.Output)"
    }
    if ((Get-Sha256HexFromFile $fullT1) -cne $shaB) { Fail-Step 'STEP_06' 'replace sonrasi target hash yanlis' }
    Write-Host 'PROMOTION_SELFTEST_STEP_06_PASS'

    # ================= STEP 07 — ENJEKTE HATA + ROLLBACK =================
    $bytesBeforeInject = [System.IO.File]::ReadAllBytes($fullT1)
    $shaBeforeInject = Get-Sha256HexFromBytes $bytesBeforeInject

    $contentC = 'PROMOTION_TARGET_GAMMA_CONTENT'
    $replaceC = New-ChangeEntry -RelPathFwd $relT1 -Operation 'replace' -ContentText $contentC -ExpectedSha $shaB
    $candCFile = Write-TextFileUtf8 -Path (Join-Path $runtimeDir 'candidate-replace-c-inject.json') `
        -Text (New-CandidateJsonText -Changes @($replaceC) -RevisionValue $fixtureRevision -Criteria $criteriaList)

    $runC = Invoke-ApplyRun -CandidateFile $candCFile -StateFile $fixtureStateFile `
        -Token (Get-ApprovalTokenForFile -File $candCFile) -InjectAfter 1
    if ($runC.ExitCode -ne 4 -or -not $runC.Output.Contains('SANDBOX_APPLY_ROLLED_BACK')) {
        Fail-Step 'STEP_07' "exit=$($runC.ExitCode) output=$($runC.Output)"
    }
    $bytesAfterRollback = [System.IO.File]::ReadAllBytes($fullT1)
    if (-not (Test-BytesEqual -A $bytesBeforeInject -B $bytesAfterRollback)) {
        Fail-Step 'STEP_07' 'rollback sonrasi byte icerik eski haliyle ayni degil'
    }
    if ((Get-Sha256HexFromBytes $bytesAfterRollback) -cne $shaBeforeInject) {
        Fail-Step 'STEP_07' 'rollback sonrasi SHA eski degerle ayni degil'
    }
    $leftoverTemps = @(Get-ChildItem -LiteralPath $runtimeDir -Force -Recurse | Where-Object { $_.Name -like '*.applytmp-*' })
    if ($leftoverTemps.Count -gt 0) { Fail-Step 'STEP_07' "temp kalinti: $($leftoverTemps[0].Name)" }
    Write-Host 'PROMOTION_SELFTEST_STEP_07_PASS'

    # ================= STEP 08 — COKLU DOSYA TRANSACTION ROLLBACK =================
    $contentX = 'PROMOTION_MULTI_X_CONTENT'
    $contentY = 'PROMOTION_MULTI_Y_CONTENT'
    $multiCreate = @(
        (New-ChangeEntry -RelPathFwd $relT2 -Operation 'create' -ContentText $contentX -ExpectedSha $null),
        (New-ChangeEntry -RelPathFwd $relT3 -Operation 'create' -ContentText $contentY -ExpectedSha $null)
    )
    $candMultiFile = Write-TextFileUtf8 -Path (Join-Path $runtimeDir 'candidate-multi-create-inject.json') `
        -Text (New-CandidateJsonText -Changes $multiCreate -RevisionValue $fixtureRevision -Criteria $criteriaList)

    $runM = Invoke-ApplyRun -CandidateFile $candMultiFile -StateFile $fixtureStateFile `
        -Token (Get-ApprovalTokenForFile -File $candMultiFile) -InjectAfter 1
    if ($runM.ExitCode -ne 4 -or -not $runM.Output.Contains('SANDBOX_APPLY_ROLLED_BACK')) {
        Fail-Step 'STEP_08' "exit=$($runM.ExitCode) output=$($runM.Output)"
    }
    if (Test-Path -LiteralPath $fullT2) { Fail-Step 'STEP_08' 'birinci hedef eski durumuna donmedi (hala mevcut)' }
    if (Test-Path -LiteralPath $fullT3) { Fail-Step 'STEP_08' 'ikinci hedef degisti/olusturuldu' }
    if ((Get-Sha256HexFromFile $fullT1) -cne $shaBeforeInject) { Fail-Step 'STEP_08' 'dokunulmamis hedef degisti' }
    Write-Host 'PROMOTION_SELFTEST_STEP_08_PASS'

    # ================= STEP 09 — PATH ESCAPE / RUNTIME DISI RED =================
    $escape = New-ChangeEntry -RelPathFwd '../outside.txt' -Operation 'create' -ContentText 'ESCAPE_ATTEMPT' -ExpectedSha $null
    $candEscapeFile = Write-TextFileUtf8 -Path (Join-Path $runtimeDir 'candidate-escape.json') `
        -Text (New-CandidateJsonText -Changes @($escape) -RevisionValue $fixtureRevision -Criteria $criteriaList)

    $runE = Invoke-ApplyRun -CandidateFile $candEscapeFile -StateFile $fixtureStateFile `
        -Token (Get-ApprovalTokenForFile -File $candEscapeFile)
    if ($runE.ExitCode -ne 2 -or -not $runE.Output.Contains('SANDBOX_APPLY_REJECTED')) {
        Fail-Step 'STEP_09' "exit=$($runE.ExitCode) output=$($runE.Output)"
    }
    if (Test-Path -LiteralPath (Join-Path $runtimeDir '..\outside.txt')) {
        Fail-Step 'STEP_09' 'runtime disinda dosya olustu'
    }
    Write-Host 'PROMOTION_SELFTEST_STEP_09_PASS'

    # ================= STEP 10 — KANONIK DEGISMEZLIK VE TEMIZLIK =================
    if ((Get-Sha256HexFromFile $canonicalTaskFile) -cne $hashCurrentBefore) { Fail-Step 'STEP_10' 'current-task.json hash degisti' }
    if ((Get-Sha256HexFromFile $taskStateSchema) -cne $hashStateSchemaBefore) { Fail-Step 'STEP_10' 'task-state.schema.json hash degisti' }
    if ((Get-Sha256HexFromFile $candSchema) -cne $hashCandSchemaBefore) { Fail-Step 'STEP_10' 'write-candidate.schema.json hash degisti' }
    if ((Get-Sha256HexFromFile $script:validatorScript) -cne $hashValidatorBefore) { Fail-Step 'STEP_10' 'validate_ai_write_candidate.ps1 hash degisti' }

    try {
        $canonicalEnd = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $awfEnd = Get-JProp (Get-JProp $canonicalEnd 'execution_policy') 'automatic_write_failover'
        if (-not ($awfEnd -is [bool]) -or $awfEnd -ne $false) { Fail-Step 'STEP_10' 'automatic_write_failover false degil' }
    }
    catch {
        Fail-Step 'STEP_10' "kanonik yeniden parse edilemedi: $($_.Exception.Message)"
    }

    $selftestNow = @(Get-ChildItem -LiteralPath $selftestRoot -Force)
    foreach ($child in $selftestNow) {
        $isOurs = ($child.Name -ceq ("runtime-" + $runGuid))
        $isPreExisting = ($preExistingSelftest -ccontains $child.Name)
        if (-not $isOurs -and -not $isPreExisting) {
            Fail-Step 'STEP_10' "self-test tarafindan runtime disinda olusturulan oge: $($child.Name)"
        }
    }
    $leftoverAny = @(Get-ChildItem -LiteralPath $runtimeDir -Force -Recurse | Where-Object { $_.Name -like '*.applytmp-*' })
    if ($leftoverAny.Count -gt 0) { Fail-Step 'STEP_10' "temp/backup kalinti: $($leftoverAny[0].Name)" }
    if ($script:SawExitFive) { Fail-Step 'STEP_10' 'exit 5 gerceklesti' }

    # --- Guvenli temizlik: yalniz bu testin runtime klasoru ---
    $resolvedRt = (Resolve-Path -LiteralPath $runtimeDir).Path
    $resolvedSelf = (Resolve-Path -LiteralPath $selftestRoot).Path
    $leafOk = ([System.IO.Path]::GetFileName($resolvedRt)) -cmatch '^runtime-[0-9a-f]{32}$'
    $underSelf = ($resolvedRt.TrimEnd('\', '/') + '\').StartsWith(($resolvedSelf.TrimEnd('\', '/') + '\'), [System.StringComparison]::OrdinalIgnoreCase)
    $notSelfRoot = ($resolvedRt.TrimEnd('\', '/') -ine $resolvedSelf.TrimEnd('\', '/'))
    $notProjectRoot = ($resolvedRt.TrimEnd('\', '/') -ine $projectRoot.TrimEnd('\', '/'))
    $sandboxRootFull = (Resolve-Path -LiteralPath (Join-Path $selftestRoot '..')).Path
    $notSandboxRoot = ($resolvedRt.TrimEnd('\', '/') -ine $sandboxRootFull.TrimEnd('\', '/'))
    if ($leafOk -and $underSelf -and $notSelfRoot -and $notProjectRoot -and $notSandboxRoot) {
        Remove-Item -LiteralPath $resolvedRt -Recurse -Force
        if (Test-Path -LiteralPath $resolvedRt) { Fail-Step 'STEP_10' 'runtime klasoru silinemedi' }
    }
    else {
        Fail-Step 'STEP_10' 'temizlik guvenlik dogrulamasi basarisiz'
    }

    Write-Host 'PROMOTION_SELFTEST_STEP_10_PASS'
    Write-Host 'AI_CANDIDATE_PROMOTION_PIPELINE_PASS'
    exit 0
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
}
