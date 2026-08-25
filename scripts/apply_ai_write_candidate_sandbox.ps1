#requires -Version 5.1
<#
.SYNOPSIS
    Dogrulanmis write-candidate adaylarini YALNIZCA sandbox/selftest runtime
    klasoru icinde uygulayan atomik kapı: approval token + preimage hash +
    atomic yazim + coklu dosya transaction + tam rollback.

.DESCRIPTION
    - GERCEK PROJE DOSYALARINA UYGULAMA YASAKTIR. Her hedef
      docs/project/ai-handoff/sandbox/selftest/runtime-<32hex>/ altinda olmak
      zorundadir; runtime disina tek byte yazilmaz.
    - -TestMode zorunludur; verilmeden calismaz (exit 3).
    - Delete/rename/move/chmod desteklenmez; yalnizca create ve replace vardir.
    - OpenCode/model, ag, DB/Docker/Supabase ve git cagrisi YOKTUR;
      Invoke-Expression ve Start-Process KULLANILMAZ.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    [Parameter(Mandatory = $true)]
    [string]$TaskStatePath,

    [Parameter(Mandatory = $true)]
    [string]$ApprovalToken,

    [switch]$TestMode,

    [ValidateRange(0, 20)]
    [int]$InjectFailureAfterWrite = 0
)

$ErrorActionPreference = 'Stop'
$originalLocation = Get-Location

try {
    # --- Proje koku ve yardimcilar ---
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

    function PreFail {
        param([string]$Reason)
        Write-Host "SANDBOX_APPLY_PRECONDITION_FAILED: $Reason"
        exit 3
    }
    function Reject {
        param([string]$Reason)
        Write-Host "SANDBOX_APPLY_REJECTED: $Reason"
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
            return (([System.BitConverter]::ToString($sha.ComputeHash($Bytes))) -replace '-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function ConvertTo-NormalizedRelPath {
        param([string]$RawPath)
        $trimmed = $RawPath.Trim()
        $trimmed = $trimmed.Replace('/', '\')
        while ($trimmed.StartsWith('.\')) { $trimmed = $trimmed.Substring(2) }
        return $trimmed.TrimEnd('\')
    }

    function Test-IsUnsafeRelPath {
        param([string]$NormPath)
        if ([string]::IsNullOrWhiteSpace($NormPath)) { return $true }
        if ([System.IO.Path]::IsPathRooted($NormPath)) { return $true }
        if ($NormPath.StartsWith('\\')) { return $true }
        if ($NormPath.Contains(':')) { return $true }
        if ($NormPath.StartsWith('\')) { return $true }
        if ($NormPath -match '[*?\[\]]') { return $true }
        $segments = @($NormPath.Split('\'))
        if ($segments -contains '..') { return $true }
        if ($segments -contains '') { return $true }
        return $false
    }

    function Test-ReparsePoint {
        param([string]$Path)
        try {
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        catch {
            return $true
        }
        return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    }

    # --- ZORUNLU TESTMODE ---
    if (-not $TestMode) {
        PreFail 'TestMode switch zorunludur; bu kapı yalnizca sandbox selftest icindir.'
    }

    # --- ON KOSULLAR ---
    $validatorScript = Join-Path $projectRoot 'scripts\validate_ai_write_candidate.ps1'
    $canonicalTaskFile = Join-Path $projectRoot 'docs\project\ai-handoff\current-task.json'
    foreach ($mustExist in @($validatorScript, $canonicalTaskFile)) {
        if (-not (Test-Path -LiteralPath $mustExist -PathType Leaf)) {
            PreFail "zorunlu dosya bulunamadi: $mustExist"
        }
    }

    try {
        $canonical = Get-Content -LiteralPath $canonicalTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        PreFail "kanonik current-task.json parse hatasi: $($_.Exception.Message)"
    }
    $awfCanonical = Get-JProp (Get-JProp $canonical 'execution_policy') 'automatic_write_failover'
    if (-not ($awfCanonical -is [bool])) {
        PreFail "automatic_write_failover gercek boolean degil"
    }
    if ($awfCanonical -ne $false) {
        PreFail "automatic_write_failover false olmali (mevcut: $awfCanonical)"
    }

    if ([string]::IsNullOrWhiteSpace($CandidatePath)) { PreFail 'CandidatePath bos olamaz.' }
    if ([string]::IsNullOrWhiteSpace($TaskStatePath)) { PreFail 'TaskStatePath bos olamaz.' }
    foreach ($p in @($CandidatePath, $TaskStatePath)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            PreFail "girdi dosyasi bulunamadi: $p"
        }
    }
    $candidateResolved = (Resolve-Path -LiteralPath $CandidatePath).Path
    $stateResolved = (Resolve-Path -LiteralPath $TaskStatePath).Path

    # --- RUNTIME KLASORU KILIDI ---
    $selftestRootFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'docs\project\ai-handoff\sandbox\selftest'))
    $selftestPrefix = $selftestRootFull.TrimEnd('\', '/') + '\'

    function Get-RuntimeNameForFile {
        param([string]$FullPath)
        $full = [System.IO.Path]::GetFullPath($FullPath)
        if (-not $full.StartsWith($selftestPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
        $rel = $full.Substring($selftestPrefix.Length)
        $firstSegment = @($rel.Split('\'))[0]
        if ($firstSegment -cmatch '^runtime-[0-9a-f]{32}$') { return $firstSegment }
        return $null
    }

    $candidateRuntime = Get-RuntimeNameForFile $candidateResolved
    if ($null -eq $candidateRuntime) {
        PreFail 'Candidate yalnizca selftest/runtime-<32hex> altinda olabilir.'
    }
    $stateRuntime = Get-RuntimeNameForFile $stateResolved
    if ($null -eq $stateRuntime) {
        PreFail 'TaskState yalnizca selftest/runtime-<32hex> altinda olabilir.'
    }
    if ($candidateRuntime -cne $stateRuntime) {
        PreFail 'Candidate ve TaskState ayni runtime klasorunde olmali.'
    }
    $runtimeDir = Join-Path $selftestRootFull $candidateRuntime
    $runtimePrefix = ([System.IO.Path]::GetFullPath($runtimeDir)).TrimEnd('\', '/') + '\'

    # --- FIXTURE STATE YEREL KONTROLLERI (exit 3) ---
    try {
        $fixture = Get-Content -LiteralPath $stateResolved -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        PreFail "fixture state JSON parse hatasi: $($_.Exception.Message)"
    }
    $fxMode = Get-JProp $fixture 'task_mode'
    if ([string]$fxMode -cne 'write') {
        PreFail "fixture task_mode 'write' olmali (mevcut: '$fxMode')"
    }
    $closedStatuses = @('awaiting_human_task', 'completed', 'failed', 'cancelled')
    $fxStatus = [string](Get-JProp $fixture 'status')
    if ($closedStatuses -ccontains $fxStatus) {
        PreFail "fixture aktif olmayan durumda: '$fxStatus'"
    }
    $fxAllowedRaw = Get-JProp (Get-JProp $fixture 'scope') 'allowed_paths'
    if (($null -eq $fxAllowedRaw) -or ($fxAllowedRaw -isnot [System.Array]) -or (@($fxAllowedRaw).Count -lt 1)) {
        PreFail 'fixture scope.allowed_paths en az 1 oge icermeli.'
    }
    foreach ($entry in @($fxAllowedRaw)) {
        if ($entry -isnot [string]) { PreFail 'fixture allowed_paths ogeleri string olmali.' }
        $normEntry = ConvertTo-NormalizedRelPath -RawPath $entry
        if (Test-IsUnsafeRelPath -NormPath $normEntry) {
            PreFail "fixture allowed_paths guvensiz oge iceriyor: '$entry'"
        }
    }

    # --- ADAY DOGRULAMA (validator oncelikle, hicbir sey yazilmadan) ---
    $valOut = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validatorScript -CandidatePath $candidateResolved -TaskStatePath $stateResolved -TestMode 2>&1)
    $valCode = $LASTEXITCODE
    $valText = (($valOut | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join "`n")
    if ([int]$valCode -ne 0 -or -not $valText.Contains('WRITE_CANDIDATE_VALID')) {
        Write-Host 'SANDBOX_APPLY_REJECTED: CANDIDATE_INVALID'
        foreach ($line in ($valText -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host "  validator: $line" }
        }
        exit 2
    }

    try {
        $candidate = Get-Content -LiteralPath $candidateResolved -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Reject 'CANDIDATE_INVALID'
    }

    # --- ONAY TOKEN'I (ordinal tam eslesme) ---
    $candidateFileSha = Get-Sha256HexFromFile $candidateResolved
    $candidateRevision = Get-JProp $candidate 'task_revision'
    $expectedToken = "APPROVE_SANDBOX_CANDIDATE:$candidateRevision`:$candidateFileSha"
    if (-not [string]::Equals($ApprovalToken, $expectedToken, [System.StringComparison]::Ordinal)) {
        Write-Host "APPROVAL_TOKEN_EXPECTED: $expectedToken"
        Reject 'APPROVAL_TOKEN_INVALID'
    }

    # --- HEDEF YOL GUVENLIGI + PREFLIGHT (hicbir yazim yok) ---
    $fxAllowedNormalized = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($fxAllowedRaw)) {
        $normEntry = ConvertTo-NormalizedRelPath -RawPath $entry
        if (-not $fxAllowedNormalized.Contains($normEntry)) { $fxAllowedNormalized.Add($normEntry) }
    }

    $changesRaw = Get-JProp $candidate 'changes'
    if (($null -eq $changesRaw) -or ($changesRaw -isnot [System.Array])) { Reject 'CANDIDATE_INVALID' }
    $chgArr = @($changesRaw)

    $seenTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $plan = New-Object System.Collections.Generic.List[object]
    $runGuidSuffix = [guid]::NewGuid().ToString('N')

    for ($i = 0; $i -lt $chgArr.Count; $i++) {
        $chg = $chgArr[$i]
        $label = "changes[$i]"
        $rawPath = Get-JProp $chg 'path'
        if ($rawPath -isnot [string]) { Reject "$label path string degil" }
        $normWin = ConvertTo-NormalizedRelPath -RawPath $rawPath
        $normFwd = $normWin.Replace('\', '/')
        if (Test-IsUnsafeRelPath -NormPath $normWin) {
            Reject "$label guvensiz yol: '$rawPath'"
        }
        $pathSegments = @($normFwd.Split('/'))
        $leafName = $pathSegments[$pathSegments.Count - 1]
        $isForbiddenTarget =
            (($leafName -ceq '.env') -or $leafName.StartsWith('.env.', [System.StringComparison]::Ordinal) -or
                $leafName.EndsWith('.pem', [System.StringComparison]::OrdinalIgnoreCase) -or
                $leafName.EndsWith('.key', [System.StringComparison]::OrdinalIgnoreCase) -or
                ($pathSegments -ccontains 'secrets'))
        if ($isForbiddenTarget) {
            Reject "$label yasakli hedef: '$normFwd'"
        }
        # fxAllowedNormalized ters-bolu formundadir; uyelik karsilastirmasi
        # ayni normalizasyon formuyla ($normWin) yapilmalidir.
        if (-not $fxAllowedNormalized.Contains($normWin)) {
            Reject "$label allowed_paths icinde birebir yok: '$normFwd'"
        }
        if (-not $seenTargets.Add($normFwd)) {
            Reject "$label ayni hedef iki kez bulunamaz: '$normFwd'"
        }

        # Hedef, allowed_paths gibi PROJE KOKUNE gore cozumlenir; ardindan
        # gercek yolun runtime-<GUID> altinda kaldigi ayrica dogrulanir.
        # Bu, validator'un FS kontrolleriyle ayni semantiği saglar.
        $fullTarget = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $normWin))
        if (-not $fullTarget.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Reject "$label runtime disina cikiyor: '$normFwd'"
        }
        if ($fullTarget.TrimEnd('\', '/') -ieq $runtimeDir.TrimEnd('\', '/')) {
            Reject "$label runtime klasorunun kendisi hedef olamaz"
        }

        $operation = [string](Get-JProp $chg 'operation')
        $contentB64 = [string](Get-JProp $chg 'content_base64')
        $contentSha = [string](Get-JProp $chg 'content_sha256')
        try {
            $bytes = [System.Convert]::FromBase64String($contentB64)
        }
        catch {
            Reject "$label base64 cozumu basarisiz"
        }
        if ((Get-Sha256HexFromBytes $bytes) -cne $contentSha) {
            Reject "$label decoded icerik hash uyusmazligi"
        }

        $oldBytes = $null
        $oldSha = $null
        if ($operation -ceq 'create') {
            if (Test-Path -LiteralPath $fullTarget) {
                Reject "${label} create hedefi zaten mevcut: '$normFwd'"
            }
        }
        elseif ($operation -ceq 'replace') {
            if (-not (Test-Path -LiteralPath $fullTarget -PathType Leaf)) {
                Reject "${label} replace hedefi mevcut normal dosya degil: '$normFwd'"
            }
            if (Test-ReparsePoint -Path $fullTarget) {
                Reject "$label hedef symlink/reparse point"
            }
            $currentSha = Get-Sha256HexFromFile $fullTarget
            $expectedPreimage = [string](Get-JProp $chg 'expected_sha256')
            if (-not [string]::Equals($currentSha, $expectedPreimage, [System.StringComparison]::Ordinal)) {
                Reject "${label} preimage hash eslesmiyor (mevcut: $currentSha)"
            }
            $oldBytes = [System.IO.File]::ReadAllBytes($fullTarget)
            $oldSha = $currentSha
        }
        else {
            Reject "$label operation create veya replace olmali"
        }

        $parentDir = [System.IO.Path]::GetDirectoryName($fullTarget)
        $parentIsRuntimeRoot = $parentDir -ieq $runtimeDir
        $parentIsStrictChildOfRuntime = ($parentDir + '\').StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not ($parentIsRuntimeRoot -or $parentIsStrictChildOfRuntime)) {
            Reject "$label parent dizin runtime disinda"
        }
        $tempName = '.' + [System.IO.Path]::GetFileName($fullTarget) + '.applytmp-' + $runGuidSuffix + '-' + $i + '.part'
        $tempPath = Join-Path $parentDir $tempName

        $plan.Add([pscustomobject]@{
            Index      = $i
            Op         = $operation
            NormWin    = $normWin
            Full       = $fullTarget
            Bytes      = $bytes
            ContentSha = $contentSha
            TempPath   = $tempPath
            OldBytes   = $oldBytes
            OldSha     = $oldSha
            WrittenSha = $null
        })
    }

    # --- PARENT DIZINLER (yalniz runtime altinda; reparse denetimli) ---
    $createdDirs = New-Object System.Collections.Generic.List[string]
    $neededParents = New-Object System.Collections.Generic.List[string]
    foreach ($entryPlan in $plan) {
        $p = [System.IO.Path]::GetDirectoryName($entryPlan.Full)
        if (-not $neededParents.Contains($p)) { $neededParents.Add($p) }
    }
    foreach ($p in $neededParents) {
        $cursor = [System.IO.Path]::GetFullPath($p)
        $missingStack = New-Object System.Collections.Generic.List[string]
        while (-not [System.IO.Directory]::Exists($cursor)) {
            if (-not $cursor.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                Reject "olusturulacak dizin runtime disinda: '$cursor'"
            }
            $missingStack.Insert(0, $cursor)
            $cursor = [System.IO.Path]::GetDirectoryName($cursor)
            if ([string]::IsNullOrEmpty($cursor)) { Reject 'dizin hiyerarsisi koke ulasti' }
        }
        foreach ($missing in $missingStack) {
            if (Test-ReparsePoint -Path $cursor) { Reject "parent symlink/reparse point: '$cursor'" }
            [System.IO.Directory]::CreateDirectory($missing) | Out-Null
            $createdDirs.Insert(0, $missing)
        }
        if (Test-ReparsePoint -Path $cursor) { Reject "parent symlink/reparse point: '$cursor'" }
    }

    # --- TEMIZLIK YARDIMCILARI (yalniz kendi temp/backup dosyalari) ---
    function Remove-TempSafely {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return }
        if (-not $full.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return }
        $leaf = [System.IO.Path]::GetFileName($full)
        if (($leaf -notlike '*.applytmp-*.part') -or ($leaf -notlike ('*.' + $runGuidSuffix + '-*'))) { return }
        try {
            if ([System.IO.File]::Exists($full)) { [System.IO.File]::Delete($full) }
        }
        catch {
        }
    }

    function Invoke-Rollback {
        for ($r = $plan.Count - 1; $r -ge 0; $r--) {
            $e = $plan[$r]
            if ($null -eq $e.WrittenSha) { continue }
            if (-not ([System.IO.Path]::GetFullPath($e.Full)).StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "rollback reddi: hedef runtime disinda: $($e.NormWin)"
            }
            if ($e.Op -ceq 'create') {
                if (-not (Test-Path -LiteralPath $e.Full -PathType Leaf)) { throw "create geri alinamadi (dosya yok): $($e.NormWin)" }
                if (Test-ReparsePoint -Path $e.Full) { throw "rollback reddi: reparse point: $($e.NormWin)" }
                $nowSha = Get-Sha256HexFromFile $e.Full
                if (-not [string]::Equals($nowSha, $e.WrittenSha, [System.StringComparison]::Ordinal)) {
                    throw "create geri alma oncesi hash uyusmazligi: $($e.NormWin)"
                }
                [System.IO.File]::Delete($e.Full)
                if (Test-Path -LiteralPath $e.Full) { throw "create dosyasi silinemedi: $($e.NormWin)" }
            }
            else {
                if (-not (Test-Path -LiteralPath $e.Full -PathType Leaf)) { throw "replace geri alinamadi (dosya yok): $($e.NormWin)" }
                $nowSha = Get-Sha256HexFromFile $e.Full
                if (-not [string]::Equals($nowSha, $e.WrittenSha, [System.StringComparison]::Ordinal)) {
                    throw "replace geri alma oncesi hash uyusmazligi: $($e.NormWin)"
                }
                [System.IO.File]::WriteAllBytes($e.Full, $e.OldBytes)
                $restoredSha = Get-Sha256HexFromFile $e.Full
                if (-not [string]::Equals($restoredSha, $e.OldSha, [System.StringComparison]::Ordinal)) {
                    throw "eski icerik geri yukleme hash uyusmazligi: $($e.NormWin)"
                }
            }
        }
        foreach ($t in $plan) { Remove-TempSafely -Path $t.TempPath }
        foreach ($d in $createdDirs) {
            try {
                $dfull = [System.IO.Path]::GetFullPath($d)
                if ($dfull.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
                    [System.IO.Directory]::Exists($dfull) -and
                    (@(Get-ChildItem -LiteralPath $dfull -Force)).Count -eq 0) {
                    [System.IO.Directory]::Delete($dfull, $false)
                }
            }
            catch {
            }
        }
    }

    # --- TRANSACTION UYGULAMA ---
    $applied = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($e in $plan) {
            [System.IO.File]::WriteAllBytes($e.TempPath, $e.Bytes)
            $tempSha = Get-Sha256HexFromFile $e.TempPath
            if (-not [string]::Equals($tempSha, $e.ContentSha, [System.StringComparison]::Ordinal)) {
                throw "temp hash uyusmazligi: $($e.NormWin)"
            }
            if ($e.Op -ceq 'create') {
                [System.IO.File]::Move($e.TempPath, $e.Full)
            }
            else {
                try {
                    [System.IO.File]::Replace($e.TempPath, $e.Full, $null)
                }
                catch {
                    [System.IO.File]::Delete($e.Full)
                    [System.IO.File]::Move($e.TempPath, $e.Full)
                }
            }
            $postSha = Get-Sha256HexFromFile $e.Full
            if (-not [string]::Equals($postSha, $e.ContentSha, [System.StringComparison]::Ordinal)) {
                throw "hedef yazim sonrasi hash uyusmazligi: $($e.NormWin)"
            }
            $e.WrittenSha = $postSha
            $applied.Add($e)
            if (($InjectFailureAfterWrite -gt 0) -and ($applied.Count -eq $InjectFailureAfterWrite)) {
                throw "INJECTED_FAILURE_AFTER_WRITE_$($applied.Count)"
            }
        }
    }
    catch {
        $triggerReason = $_.Exception.Message
        try {
            Invoke-Rollback
            Write-Host 'SANDBOX_APPLY_ROLLED_BACK'
            Write-Host "SANDBOX_APPLY_ROLLBACK_TRIGGER: $triggerReason"
            exit 4
        }
        catch {
            Write-Host "SANDBOX_APPLY_ROLLBACK_FAILED: $($_.Exception.Message) | tetikleyen: $triggerReason"
            exit 5
        }
    }

    # --- BASARI: temp temizligi, aday/fixture/hedefler korunur ---
    foreach ($e in $plan) { Remove-TempSafely -Path $e.TempPath }
    Write-Host "SANDBOX_CANDIDATE_APPLIED_CHANGES: $($applied.Count)"
    Write-Host 'SANDBOX_CANDIDATE_APPLIED'
    exit 0
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
}
