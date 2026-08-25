#requires -Version 5.1
<#
.SYNOPSIS
    Write aday paketi salt-okunur deterministik dogrulayicisi.
.DESCRIPTION
    docs/project/ai-handoff/write-candidate.schema.json sozlesmesini sabit
    kurallarla dogrular. Script HICBIR dosya olusturmaz, degistirmez, silmez
    veya tasimaz; decoded icerigi diske YAZMAZ; aday paketleri gercek proje
    dosyalarina uygulayan hicbir kod icermez.
    Otomatik merge, patch uygulama, rename, move, delete veya promotion YAPILMAZ.
    Invoke-Expression, Start-Process, git, DB, Docker, Supabase, ag erisimi ve
    .env/secret okumasi KULLANILMAZ. execution_policy.automatic_write_failover
    degeri yalnizca okunur; HICBIR kosulda degistirilmez.
.NOTES
    Exit kodlari: 0 = WRITE_CANDIDATE_VALID, 2 = dogrulama hatalari
    (her hata ayri satirda WRITE_CANDIDATE_ERROR), 3 = on kosul hatasi
    (WRITE_CANDIDATE_PRECONDITION_FAILED).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    # Istege bagli: gorev durumu dosyasi. YALNIZCA -TestMode ile ve YALNIZCA
    # docs/project/ai-handoff/sandbox/selftest/ altinda kullanilabilir.
    # -TestMode olmadan verilirse on kosul hatasindan reddedilir.
    [string]$TaskStatePath,

    # Istege bagli: self-test modu. Hicbir guvenlik kontrolunu KAPATMAZ veya
    # gevsetmez; yalnizca alternatif fixture gorev durumuna izin verir.
    [switch]$TestMode
)

$ErrorActionPreference = 'Stop'

$originalLocation = Get-Location
$script:CandidateErrors = New-Object System.Collections.Generic.List[string]

function Add-CandidateError {
    param([string]$Message)
    $script:CandidateErrors.Add("WRITE_CANDIDATE_ERROR: $Message") | Out-Null
}

try {
    # --- Proje kokunu bul ve gec ---
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    Set-Location -LiteralPath $projectRoot

    function Get-JProp {
        # Dikkat: fonksiyon donusleri pipeline'da enumerate edilir; bu,
        # TEK OGELI dizileri skalar'a indirger. Unary virgul ile donus,
        # dizinin tipini (ve tek ogeli dizileri) korur.
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -eq $prop) { return $null }
        $value = $prop.Value
        return , $value
    }

    function Test-KnownProperties {
        param($Object, [string[]]$Allowed, [string]$Label)
        if ($null -eq $Object) { return }
        foreach ($name in $Object.PSObject.Properties.Name) {
            if ($Allowed -notcontains $name) {
                Add-CandidateError "$Label nesnesinde izin verilmeyen alan: '$name'"
            }
        }
    }

    function Get-Sha256HexFromBytes {
        param([byte[]]$Bytes)
        $sha = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
        try { $hashBytes = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
        return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }

    function Get-Sha256HexFromFile {
        param([string]$FileFullPath)
        $h = Get-FileHash -LiteralPath $FileFullPath -Algorithm SHA256
        return $h.Hash.ToLowerInvariant()
    }

    # Goreceli yollar tek bicime getirilir: trim -> ayraclar ters bolu -> bastaki nokta-bolu temizligi.
    function ConvertTo-NormalizedRelPath {
        param([string]$RawPath)
        if ($null -eq $RawPath) { return $null }
        $t = $RawPath.Trim()
        if ($t -eq '') { return $null }
        $t = $t.Replace('/', '\')
        while ($t.StartsWith('.\')) { $t = $t.Substring(2) }
        return $t
    }

    # Ilk surumde yalnizca kesin dosya yollari kabul edilir:
    # absolute, UNC, kokten yol, '..' segmenti, wildcard ve bos segment YASAK.
    function Test-IsUnsafeRelPath {
        param([string]$NormPath)
        if ([string]::IsNullOrEmpty($NormPath)) { return $true }
        if ($NormPath.IndexOf(':') -ge 0) { return $true }
        if ($NormPath.StartsWith('\')) { return $true }
        if ($NormPath -match '[*?\[\]]') { return $true }
        $segments = @($NormPath.Split('\'))
        if ($segments -contains '..') { return $true }
        if ($segments -contains '') { return $true }
        return $false
    }

    function Test-UnderAllowedRoot {
        param([string]$FullPath, [string]$RootDir)
        $sep = [System.IO.Path]::DirectorySeparatorChar
        $f = [System.IO.Path]::GetFullPath($FullPath).TrimEnd('\', '/')
        $r = [System.IO.Path]::GetFullPath($RootDir).TrimEnd('\', '/')
        return (($f + $sep).StartsWith(($r + $sep), [System.StringComparison]::OrdinalIgnoreCase))
    }

    # --- ON KOSULLAR (exit 3) ---
    if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
        Write-Host 'WRITE_CANDIDATE_PRECONDITION_FAILED: CandidatePath bos olamaz.'
        exit 3
    }
    if (-not (Test-Path -LiteralPath $CandidatePath -PathType Leaf)) {
        Write-Host "WRITE_CANDIDATE_PRECONDITION_FAILED: aday dosya bulunamadi: $CandidatePath"
        exit 3
    }
    $candidateFull = (Resolve-Path -LiteralPath $CandidatePath).Path

    # Aday dosyasi yalnizca bu iki dizinin altinda olabilir; Resolve-Path
    # sonrasindaki GERCEK yol uzerinden dogrulanir.
    $allowedRoots = @(
        (Join-Path $projectRoot 'docs\project\ai-handoff\candidates'),
        (Join-Path $projectRoot 'docs\project\ai-handoff\sandbox')
    )
    $underAllowed = $false
    foreach ($rootDir in $allowedRoots) {
        if (Test-UnderAllowedRoot -FullPath $candidateFull -RootDir $rootDir) {
            $underAllowed = $true
            break
        }
    }
    if (-not $underAllowed) {
        Write-Host 'WRITE_CANDIDATE_PRECONDITION_FAILED: aday dosya yalnizca candidates veya sandbox dizinleri altinda olabilir.'
        exit 3
    }

    # --- Gorev durumu dosyasinin cozumlenmesi (geriye uyumlu) ---
    # Varsayilan kanonik kaynak docs/project/ai-handoff/current-task.json'dir.
    # Alternatif bir yol YALNIZCA -TestMode ile ve YALNIZCA Resolve-Path
    # sonrasinda sandbox/selftest dizini altinda kaliyorsa kabul edilir.
    # -TestMode hicbir guvenlik kontrolunu kapatmaz veya gevsetmez.
    $selftestRoot = Join-Path $projectRoot 'docs\project\ai-handoff\sandbox\selftest'
    if ([string]::IsNullOrWhiteSpace($TaskStatePath)) {
        $currentTaskPath = Join-Path $projectRoot 'docs\project\ai-handoff\current-task.json'
    }
    elseif (-not $TestMode) {
        Write-Host 'WRITE_CANDIDATE_PRECONDITION_FAILED: TaskStatePath yalnizca -TestMode ile kullanilabilir.'
        exit 3
    }
    else {
        if (-not (Test-Path -LiteralPath $TaskStatePath -PathType Leaf)) {
            Write-Host "WRITE_CANDIDATE_PRECONDITION_FAILED: gorev durumu dosyasi bulunamadi: $TaskStatePath"
            exit 3
        }
        $resolvedState = (Resolve-Path -LiteralPath $TaskStatePath).Path
        if (-not (Test-UnderAllowedRoot -FullPath $resolvedState -RootDir $selftestRoot)) {
            Write-Host 'WRITE_CANDIDATE_PRECONDITION_FAILED: -TestMode gorev durumu dosyasi yalnizca sandbox/selftest dizini altinda olabilir.'
            exit 3
        }
        $currentTaskPath = $resolvedState
    }

    if (-not (Test-Path -LiteralPath $currentTaskPath)) {
        Write-Host "WRITE_CANDIDATE_PRECONDITION_FAILED: gorev durumu dosyasi bulunamadi: $currentTaskPath"
        exit 3
    }
    try {
        $currentTask = Get-Content -LiteralPath $currentTaskPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "WRITE_CANDIDATE_PRECONDITION_FAILED: gorev durumu JSON parse hatasi: $($_.Exception.Message)"
        exit 3
    }
    try {
        $candidate = Get-Content -LiteralPath $candidateFull -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "WRITE_CANDIDATE_PRECONDITION_FAILED: aday JSON parse hatasi: $($_.Exception.Message)"
        exit 3
    }

    # --- SABIT ALAN LISTELERI (sema disi alan reddi) ---
    $rootAllowedFields = @('schema_version','task_revision','canonical_report','producer','status','changes','acceptance_criteria','safety')
    $producerFields    = @('role','model')
    $changeFields      = @('path','operation','expected_sha256','content_base64','content_sha256')
    $safetyFields      = @('production_accessed','db_command_ran','git_write_ran','secret_accessed','delete_requested','real_project_files_changed')
    $hex64Pattern      = '^[0-9a-f]{64}$'

    # --- CURRENT-TASK KAPISI ---
    $ctTaskMode  = Get-JProp -Object $currentTask -Name 'task_mode'
    $ctStatus    = Get-JProp -Object $currentTask -Name 'status'
    $ctRevision  = Get-JProp -Object $currentTask -Name 'revision'
    $ctCanonical = Get-JProp -Object $currentTask -Name 'canonical_report'
    $ctScope     = Get-JProp -Object $currentTask -Name 'scope'
    $ctTask      = Get-JProp -Object $currentTask -Name 'task'
    $execPolicy  = Get-JProp -Object $currentTask -Name 'execution_policy'

    # automatic_write_failover YALNIZ okunur; hicbir kosulda degistirilmez.
    $autoWriteFailover = Get-JProp -Object $execPolicy -Name 'automatic_write_failover'

    if ($ctTaskMode -cne 'write') {
        Add-CandidateError "current-task task_mode 'write' olmali (mevcut: '$ctTaskMode')"
    }
    if (@('awaiting_human_task','completed','failed','cancelled') -ccontains $ctStatus) {
        Add-CandidateError "current-task status '$ctStatus' iken aday paket reddedilir"
    }

    $allowedRaw = Get-JProp -Object $ctScope -Name 'allowed_paths'
    $allowedCount = 0
    if (($null -ne $allowedRaw) -and ($allowedRaw -is [System.Array])) { $allowedCount = @($allowedRaw).Count }
    if ($allowedCount -lt 1) {
        Add-CandidateError 'current-task scope.allowed_paths en az 1 oge icermeli'
    }

    $criteriaRaw = Get-JProp -Object $ctTask -Name 'acceptance_criteria'
    $criteriaCount = 0
    if (($null -ne $criteriaRaw) -and ($criteriaRaw -is [System.Array])) { $criteriaCount = @($criteriaRaw).Count }
    if ($criteriaCount -lt 1) {
        Add-CandidateError 'current-task task.acceptance_criteria en az 1 oge icermeli'
    }

    # --- allowed_paths sekli: yalnizca kesin dosya yollari ---
    $normalizedAllowed = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($allowedRaw)) {
        if ($entry -isnot [string]) {
            Add-CandidateError "scope.allowed_paths ogeleri string olmali: '$entry'"
            continue
        }
        $normEntry = ConvertTo-NormalizedRelPath -RawPath $entry
        if (Test-IsUnsafeRelPath -NormPath $normEntry) {
            Add-CandidateError "scope.allowed_paths gecersiz oge (wildcard/absolute/UNC/../bos): '$entry'"
            continue
        }
        if (-not $normalizedAllowed.Contains($normEntry)) { $normalizedAllowed.Add($normEntry) }
    }

    $deniedPatterns = @()
    $deniedRaw = Get-JProp -Object $ctScope -Name 'denied_paths'
    if (($null -ne $deniedRaw) -and ($deniedRaw -is [System.Array])) {
        $deniedPatterns = @($deniedRaw | ForEach-Object { [string]$_ })
    }

    # --- ADAY KOK SEVIYESI ---
    Test-KnownProperties -Object $candidate -Allowed $rootAllowedFields -Label 'kok'

    $schemaVersion = Get-JProp -Object $candidate -Name 'schema_version'
    if ($schemaVersion -ne 1) {
        Add-CandidateError "schema_version tam olarak 1 olmali (mevcut: $schemaVersion)"
    }

    $taskRevision = Get-JProp -Object $candidate -Name 'task_revision'
    if (-not (($taskRevision -is [int]) -or ($taskRevision -is [long]))) {
        Add-CandidateError 'task_revision integer olmali'
    }
    else {
        if ($taskRevision -lt 1) { Add-CandidateError "task_revision en az 1 olmali (mevcut: $taskRevision)" }
        if (($null -ne $ctRevision) -and ($taskRevision -ne $ctRevision)) {
            Add-CandidateError "task_revision current-task.revision ile ayni olmali (aday: $taskRevision, gorev: $ctRevision)"
        }
    }

    $candidateCanonical = Get-JProp -Object $candidate -Name 'canonical_report'
    if ($candidateCanonical -cne $ctCanonical) {
        Add-CandidateError "canonical_report current-task ile ayni olmali (aday: '$candidateCanonical', gorev: '$ctCanonical')"
    }

    $candidateStatus = Get-JProp -Object $candidate -Name 'status'
    if ($candidateStatus -cne 'READY_FOR_VALIDATION') {
        Add-CandidateError "status 'READY_FOR_VALIDATION' olmali (mevcut: '$candidateStatus')"
    }

    # --- producer ---
    $producer = Get-JProp -Object $candidate -Name 'producer'
    Test-KnownProperties -Object $producer -Allowed $producerFields -Label 'producer'
    $producerRole = Get-JProp -Object $producer -Name 'role'
    if (@('primary','fallback') -cnotcontains $producerRole) {
        Add-CandidateError "producer.role 'primary' veya 'fallback' olmali (mevcut: '$producerRole')"
    }
    $producerModel = Get-JProp -Object $producer -Name 'model'
    if (-not ($producerModel -is [string]) -or [string]::IsNullOrWhiteSpace($producerModel)) {
        Add-CandidateError 'producer.model bos olmayan string olmali'
    }

    # --- safety: tamami gercek boolean false ---
    $safetyObj = Get-JProp -Object $candidate -Name 'safety'
    Test-KnownProperties -Object $safetyObj -Allowed $safetyFields -Label 'safety'
    foreach ($sf in $safetyFields) {
        $sv = Get-JProp -Object $safetyObj -Name $sf
        if (($sv -isnot [bool]) -or ($sv -ne $false)) {
            Add-CandidateError "safety.$sf gercek boolean false olmali"
        }
    }

    # --- acceptance_criteria: current-task ile sirasiyla birebir ayni ---
    $candCriteria = Get-JProp -Object $candidate -Name 'acceptance_criteria'
    if (($null -eq $candCriteria) -or ($candCriteria -isnot [System.Array])) {
        Add-CandidateError 'acceptance_criteria dizi olmali'
    }
    else {
        $ccArr = @($candCriteria)
        if ($ccArr.Count -lt 1) { Add-CandidateError 'acceptance_criteria en az 1 oge icermeli' }
        foreach ($item in $ccArr) {
            if (($item -isnot [string]) -or [string]::IsNullOrWhiteSpace($item)) {
                Add-CandidateError 'acceptance_criteria ogeleri bos olmayan string olmali'
                break
            }
        }
        if ((@($ccArr | Select-Object -Unique)).Count -ne $ccArr.Count) {
            Add-CandidateError 'acceptance_criteria benzersiz olmali (tekrar eden oge var)'
        }
        if (($criteriaCount -ge 1) -and ($ccArr.Count -ge 1) -and ($ccArr.Count -eq @($criteriaRaw).Count)) {
            $ctArr = @($criteriaRaw)
            for ($idx = 0; $idx -lt $ccArr.Count; $idx++) {
                if ([string]$ccArr[$idx] -cne [string]$ctArr[$idx]) {
                    Add-CandidateError "acceptance_criteria[$idx] current-task ile ayni degil"
                }
            }
        }
        elseif (($ccArr.Count -gt 0) -and ($criteriaCount -ge 1)) {
            Add-CandidateError "acceptance_criteria current-task ile birebir ayni olmali (sayi farki: aday=$($ccArr.Count), gorev=$criteriaCount)"
        }
    }

    # --- changes ---
    $perFileLimitBytes = [long]2097152   # 2 MiB
    $totalLimitBytes   = [long]5242880   # 5 MiB
    $base64CapChars    = [long]2796210   # 2 MiB decoded icin ust sinir (+ tolerans)
    $script:TotalLimitReported = $false

    $changesRaw = Get-JProp -Object $candidate -Name 'changes'
    $decodedTotalBytes = [long]0
    if (($null -eq $changesRaw) -or ($changesRaw -isnot [System.Array])) {
        Add-CandidateError 'changes dizi olmali'
    }
    else {
        $chgArr = @($changesRaw)
        if ($chgArr.Count -lt 1) { Add-CandidateError 'changes en az 1 oge icermeli' }
        if ($chgArr.Count -gt 20) { Add-CandidateError "changes en fazla 20 oge icerebilir (mevcut: $($chgArr.Count))" }

        for ($ci = 0; $ci -lt $chgArr.Count; $ci++) {
            $chg = $chgArr[$ci]
            $label = "changes[$ci]"
            $pathAuthorized = $false
            if (($null -eq $chg) -or ($chg -isnot [pscustomobject])) {
                Add-CandidateError "$label nesne olmali"
                continue
            }
            Test-KnownProperties -Object $chg -Allowed $changeFields -Label $label

            $rawPath     = Get-JProp -Object $chg -Name 'path'
            $operation   = Get-JProp -Object $chg -Name 'operation'
            $expectedSha = Get-JProp -Object $chg -Name 'expected_sha256'
            $contentB64  = Get-JProp -Object $chg -Name 'content_base64'
            $contentSha  = Get-JProp -Object $chg -Name 'content_sha256'

            $normWin = $null
            $normFwd = $null
            if (($rawPath -isnot [string]) -or [string]::IsNullOrWhiteSpace($rawPath)) {
                Add-CandidateError "$label.path bos olmayan string olmali"
            }
            else {
                $normWin = ConvertTo-NormalizedRelPath -RawPath $rawPath
                if (Test-IsUnsafeRelPath -NormPath $normWin) {
                    Add-CandidateError "$label.path guvensiz yol (absolute/UNC/leading-slash/../wildcard): '$rawPath'"
                }
                else {
                    $normFwd = $normWin.Replace('\', '/')

                    if (-not ($normalizedAllowed.Contains($normWin))) {
                        Add-CandidateError "$label.path allowed_paths icinde birebir bulunamadi: '$normFwd'"
                    }
                    else {
                        $pathAuthorized = $true
                    }

                    $matchedDenied = $null
                    foreach ($dp in $deniedPatterns) {
                        if ($normFwd -like $dp) { $matchedDenied = $dp; break }
                    }
                    if ($null -ne $matchedDenied) {
                        Add-CandidateError "$label.path denied_paths kalibiyla eslesti ('$matchedDenied'): '$normFwd'"
                        $pathAuthorized = $false
                    }

                    $segments = @($normFwd.Split('/'))
                    $fileName = $segments[$segments.Count - 1]
                    if ($fileName -match '^\.env(\..+)?$') {
                        Add-CandidateError "$label.path .env dosyasi kesinlikle reddedilir: '$normFwd'"
                        $pathAuthorized = $false
                    }
                    if ($fileName -match '\.(pem|key)$') {
                        Add-CandidateError "$label.path pem/key dosyasi kesinlikle reddedilir: '$normFwd'"
                        $pathAuthorized = $false
                    }
                    if ($segments -contains 'secrets') {
                        Add-CandidateError "$label.path secrets klasoru kesinlikle reddedilir: '$normFwd'"
                        $pathAuthorized = $false
                    }
                }
            }

            $opOk = $true
            if (($operation -isnot [string]) -or (@('create','replace') -cnotcontains $operation)) {
                Add-CandidateError "$label.operation 'create' veya 'replace' olmali (mevcut: '$operation')"
                $opOk = $false
            }

            $expectedShaOk = $true
            if ($opOk) {
                if ($operation -ceq 'create') {
                    if ($null -ne $expectedSha) {
                        Add-CandidateError "$label.expected_sha256 create isleminde null olmali"
                        $expectedShaOk = $false
                    }
                }
                else {
                    if (($expectedSha -isnot [string]) -or ($expectedSha -cnotmatch $hex64Pattern)) {
                        Add-CandidateError "$label.expected_sha256 replace isleminde 64 karakter lowercase hex olmali"
                        $expectedShaOk = $false
                    }
                }
            }

            $contentShaOk = $true
            if (($contentSha -isnot [string]) -or ($contentSha -cnotmatch $hex64Pattern)) {
                Add-CandidateError "$label.content_sha256 64 karakter lowercase hex olmali"
                $contentShaOk = $false
            }

            $decodeOk = $false
            $decodedBytes = $null
            if (($contentB64 -is [string]) -and (-not [string]::IsNullOrWhiteSpace($contentB64))) {
                if ($contentB64.Length -gt $base64CapChars) {
                    Add-CandidateError "$label.content_base64 cok buyuk (dosya basina 2 MiB decoded siniri)"
                }
                else {
                    try {
                        $decodedBytes = [Convert]::FromBase64String($contentB64)
                        $decodeOk = $true
                    }
                    catch {
                        Add-CandidateError "$label.content_base64 gecerli Base64 degil"
                    }
                }
            }
            else {
                Add-CandidateError "$label.content_base64 bos olmayan string olmali"
            }

            if ($decodeOk) {
                if ($decodedBytes.Length -gt $perFileLimitBytes) {
                    Add-CandidateError "$label decoded icerik 2 MiB sinirini asiyor ($($decodedBytes.Length) byte)"
                    $decodeOk = $false
                }
                else {
                    $decodedTotalBytes += $decodedBytes.Length
                    if (($decodedTotalBytes -gt $totalLimitBytes) -and (-not $script:TotalLimitReported)) {
                        Add-CandidateError "toplam decoded icerik 5 MiB sinirini asti ($decodedTotalBytes byte)"
                        $script:TotalLimitReported = $true
                    }
                }
            }

            if ($decodeOk -and $contentShaOk) {
                $actualHex = Get-Sha256HexFromBytes -Bytes $decodedBytes
                if ($actualHex -cne $contentSha) {
                    Add-CandidateError "$label.content_sha256 decode edilmis icerikle eslesmiyor"
                }
            }

            # Dosya sistemi kontrolleri YALNIZCA yetkili ve gecerli islem icin yapilir.
            if ($pathAuthorized -and $opOk) {
                $targetFull = Join-Path $projectRoot $normWin
                if ($operation -ceq 'create') {
                    if (Test-Path -LiteralPath $targetFull) {
                        Add-CandidateError "$label create hedefi zaten mevcut: '$normFwd'"
                    }
                }
                else {
                    if (-not (Test-Path -LiteralPath $targetFull -PathType Leaf)) {
                        Add-CandidateError "$label replace hedefi mevcut normal dosya degil: '$normFwd'"
                    }
                    elseif ($expectedShaOk) {
                        $actualFileHex = Get-Sha256HexFromFile -FileFullPath $targetFull
                        if ($actualFileHex -cne $expectedSha) {
                            Add-CandidateError "$label.expected_sha256 mevcut dosyanin hash'iyle eslesmiyor: '$normFwd'"
                        }
                    }
                }
            }
        }
    }

    # --- SONUC ---
    if ($script:CandidateErrors.Count -gt 0) {
        foreach ($errLine in $script:CandidateErrors) {
            Write-Host $errLine
        }
        exit 2
    }

    Write-Host 'WRITE_CANDIDATE_VALID'
    exit 0
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
}
