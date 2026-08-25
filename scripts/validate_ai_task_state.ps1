#requires -Version 5.1
<#
.SYNOPSIS
    AI gorev durumu deterministik dogrulayici (salt okunur).
.DESCRIPTION
    docs/project/ai-handoff/task-state.schema.json ve current-task.json
    dosyalarini sabit kurallarla dogrular. Hicbir dosya olusturmaz,
    degistirmez, silmez; ag, DB, Docker, Supabase ve git kullanmaz.
.NOTES
    Exit kodlari: 0 = TASK_STATE_VALID, 2 = dogrulama hatalari,
    3 = on kosul eksikligi (dosya yok / JSON parse hatasi).
#>

$ErrorActionPreference = 'Stop'

$originalLocation = Get-Location
$script:TaskStateErrors = New-Object System.Collections.Generic.List[string]

function Add-TaskStateError {
    param([string]$Message)
    $script:TaskStateErrors.Add("TASK_STATE_ERROR: $Message") | Out-Null
}

function Get-PropValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Test-KnownProperties {
    param($Object, [string[]]$Allowed, [string]$Label)
    if ($null -eq $Object) { return }
    foreach ($name in $Object.PSObject.Properties.Name) {
        if ($Allowed -notcontains $name) {
            Add-TaskStateError "$Label nesnesinde izin verilmeyen alan: '$name'"
        }
    }
}

function Test-RequiredString {
    param($Container, [string]$Name, [string]$Label)
    $value = Get-PropValue -Object $Container -Name $Name
    if ($null -eq $value) {
        Add-TaskStateError "$Label eksik"
        return
    }
    if (-not ($value -is [string])) {
        Add-TaskStateError "$Label string olmali"
        return
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        Add-TaskStateError "$Label bos olamaz"
    }
}

function Test-PropertyExists {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

# Zorunlu dizi alani: property yoksa 'eksik'; var ama dizi degilse 'dizi olmali';
# mevcut bos dizi GECERLI kabul edilir (benzersizlik ve oge tipi kontrolleri bos dizide hata uretmez).
function Test-RequiredArrayField {
    param($Container, [string]$Name, [string]$Label)
    if (-not (Test-PropertyExists -Object $Container -Name $Name)) {
        Add-TaskStateError "$Label eksik"
        return $false
    }
    $raw = $Container.PSObject.Properties[$Name].Value
    if ($null -eq $raw) {
        Add-TaskStateError "$Label null olamaz"
        return $false
    }
    if ($raw -isnot [System.Array]) {
        Add-TaskStateError "$Label dizi olmali"
        return $false
    }
    $arr = @($raw)
    foreach ($item in $arr) {
        if ($item -isnot [string]) {
            Add-TaskStateError "$Label ogeleri string olmali"
            return $false
        }
    }
    if ((@($arr | Select-Object -Unique)).Count -ne $arr.Count) {
        Add-TaskStateError "$Label benzersiz olmali (tekrar eden oge var)"
        return $false
    }
    return $true
}

try {
    # --- Proje kokunu bul ve gec ---
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    Set-Location -LiteralPath $projectRoot

    $schemaPath = Join-Path $projectRoot 'docs\project\ai-handoff\task-state.schema.json'
    $statePath  = Join-Path $projectRoot 'docs\project\ai-handoff\current-task.json'

    # --- On kosullar: varlik ve JSON parse ---
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        Write-Host "TASK_STATE_PRECONDITION_FAILED: schema dosyasi bulunamadi: $schemaPath"
        exit 3
    }
    if (-not (Test-Path -LiteralPath $statePath)) {
        Write-Host "TASK_STATE_PRECONDITION_FAILED: current-task dosyasi bulunamadi: $statePath"
        exit 3
    }
    try {
        $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "TASK_STATE_PRECONDITION_FAILED: schema JSON parse hatasi: $($_.Exception.Message)"
        exit 3
    }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "TASK_STATE_PRECONDITION_FAILED: current-task JSON parse hatasi: $($_.Exception.Message)"
        exit 3
    }

    # --- Izin verilen alan sabit listeleri ---
    $rootAllowed       = @('schema_version','revision','project','task_id','task_mode','status','canonical_report','models','execution_policy','scope','task','checkpoint','safety')
    $modelsAllowed     = @('primary','fallbacks')
    $policyAllowed     = @('automatic_readonly_failover','automatic_write_failover','max_attempts_per_model','resume_from_checkpoint_only','require_acceptance_before_complete')
    $scopeAllowed      = @('allowed_paths','denied_paths')
    $taskAllowed       = @('objective','acceptance_criteria')
    $checkpointAllowed = @('last_completed_step','next_action','files_changed','verification_evidence')
    $safetyAllowed     = @('forbidden_actions','human_approval_required_for')

    # --- 4) Schema disi alan kontrolu ---
    Test-KnownProperties -Object $state          -Allowed $rootAllowed       -Label 'kok'
    $models           = Get-PropValue -Object $state -Name 'models'
    $executionPolicy  = Get-PropValue -Object $state -Name 'execution_policy'
    $scope            = Get-PropValue -Object $state -Name 'scope'
    $task             = Get-PropValue -Object $state -Name 'task'
    $checkpoint       = Get-PropValue -Object $state -Name 'checkpoint'
    $safety           = Get-PropValue -Object $state -Name 'safety'
    Test-KnownProperties -Object $models          -Allowed $modelsAllowed     -Label 'models'
    Test-KnownProperties -Object $executionPolicy -Allowed $policyAllowed     -Label 'execution_policy'
    Test-KnownProperties -Object $scope           -Allowed $scopeAllowed      -Label 'scope'
    Test-KnownProperties -Object $task            -Allowed $taskAllowed       -Label 'task'
    Test-KnownProperties -Object $checkpoint      -Allowed $checkpointAllowed -Label 'checkpoint'
    Test-KnownProperties -Object $safety          -Allowed $safetyAllowed     -Label 'safety'

    # --- Kok seviyesi alanlar ---
    foreach ($field in $rootAllowed) {
        if ($null -eq (Get-PropValue -Object $state -Name $field)) {
            Add-TaskStateError "kok alan eksik veya null: '$field'"
        }
    }

    $schemaVersion = Get-PropValue -Object $state -Name 'schema_version'
    if ($null -ne $schemaVersion) {
        if (-not (($schemaVersion -is [int]) -or ($schemaVersion -is [long]))) {
            Add-TaskStateError 'schema_version integer olmali'
        }
        elseif ($schemaVersion -ne 1) {
            Add-TaskStateError "schema_version tam olarak 1 olmali (mevcut: $schemaVersion)"
        }
    }

    $revision = Get-PropValue -Object $state -Name 'revision'
    if ($null -ne $revision) {
        if (-not (($revision -is [int]) -or ($revision -is [long]))) {
            Add-TaskStateError 'revision integer olmali'
        }
        elseif ($revision -lt 1) {
            Add-TaskStateError "revision en az 1 olmali (mevcut: $revision)"
        }
    }

    Test-RequiredString -Container $state -Name 'project'         -Label 'project'
    Test-RequiredString -Container $state -Name 'task_id'         -Label 'task_id'
    Test-RequiredString -Container $state -Name 'canonical_report' -Label 'canonical_report'

    $canonicalReportExpected = 'docs/reports/latest-faz5-security-validation.md'
    $canonicalReport = Get-PropValue -Object $state -Name 'canonical_report'
    if (($null -ne $canonicalReport) -and ($canonicalReport -is [string]) -and ($canonicalReport -ne $canonicalReportExpected)) {
        Add-TaskStateError "canonical_report tam olarak '$canonicalReportExpected' olmali (mevcut: '$canonicalReport')"
    }

    $taskMode = Get-PropValue -Object $state -Name 'task_mode'
    if ($null -ne $taskMode) {
        if (@('readonly','write') -notcontains $taskMode) {
            Add-TaskStateError "task_mode readonly veya write olmali (mevcut: '$taskMode')"
        }
    }

    $status = Get-PropValue -Object $state -Name 'status'
    if ($null -ne $status) {
        $statusEnum = @('awaiting_human_task','ready','in_progress','blocked','review_required','completed')
        if ($statusEnum -notcontains $status) {
            Add-TaskStateError "status gecersiz (mevcut: '$status')"
        }
    }

    # --- models ---
    if ($null -ne $models) {
        Test-RequiredString -Container $models -Name 'primary' -Label 'models.primary'
        $fallbacksOk = Test-RequiredArrayField -Container $models -Name 'fallbacks' -Label 'models.fallbacks'
        if ($fallbacksOk) {
            $fbArr = @($models.PSObject.Properties['fallbacks'].Value)
            if ($fbArr.Count -eq 0) {
                Add-TaskStateError 'models.fallbacks bos olamaz (en az bir yedek model gerekli)'
            }
            $primaryValue = Get-PropValue -Object $models -Name 'primary'
            foreach ($fb in $fbArr) {
                if ($primaryValue -and ($fb -eq $primaryValue)) {
                    Add-TaskStateError "fallback model primary ile ayni olamaz: '$fb'"
                }
            }
        }
    }

    # --- execution_policy ---
    if ($null -ne $executionPolicy) {
        $boolPolicyFields = @('automatic_readonly_failover','automatic_write_failover','resume_from_checkpoint_only','require_acceptance_before_complete')
        foreach ($bf in $boolPolicyFields) {
            $bv = Get-PropValue -Object $executionPolicy -Name $bf
            if ($null -eq $bv) {
                Add-TaskStateError "execution_policy.$bf eksik"
            }
            elseif ($bv -isnot [bool]) {
                Add-TaskStateError "execution_policy.$bf boolean olmali"
            }
        }
        $maxAttempts = Get-PropValue -Object $executionPolicy -Name 'max_attempts_per_model'
        if ($null -eq $maxAttempts) {
            Add-TaskStateError 'execution_policy.max_attempts_per_model eksik'
        }
        else {
            if (-not (($maxAttempts -is [int]) -or ($maxAttempts -is [long]))) {
                Add-TaskStateError 'execution_policy.max_attempts_per_model integer olmali'
            }
            elseif (($maxAttempts -lt 1) -or ($maxAttempts -gt 3)) {
                Add-TaskStateError "execution_policy.max_attempts_per_model 1-3 araliginda olmali (mevcut: $maxAttempts)"
            }
        }
    }

    # --- scope ---
    if ($null -ne $scope) {
        foreach ($sf in $scopeAllowed) {
            if (-not (Test-PropertyExists -Object $scope -Name $sf)) {
                Add-TaskStateError "scope.$sf eksik"
            }
        }
        $allowedOk = Test-RequiredArrayField -Container $scope -Name 'allowed_paths' -Label 'scope.allowed_paths'
        $deniedOk  = Test-RequiredArrayField -Container $scope -Name 'denied_paths'  -Label 'scope.denied_paths'

        if ($allowedOk) {
            $allowedPaths = @($scope.PSObject.Properties['allowed_paths'].Value)
            foreach ($path in $allowedPaths) {
                if ($path -match '^([A-Za-z]:[\\/]|\\\\|\/)') {
                    Add-TaskStateError "scope.allowed_paths mutlak yol icermez: '$path'"
                    continue
                }
                $segments = @($path -split '[\\/]')
                if ($segments -contains '..') {
                    Add-TaskStateError "scope.allowed_paths '..' icermez: '$path'"
                    continue
                }
                if ($path -match '(^|[\\/])\.env($|\.)([^\\/]*)') {
                    Add-TaskStateError "scope.allowed_paths .env yolu icermez: '$path'"
                    continue
                }
                if ($path -match '\.(pem|key)$') {
                    Add-TaskStateError "scope.allowed_paths pem/key yolu icermez: '$path'"
                    continue
                }
                if ($segments -contains 'secrets') {
                    Add-TaskStateError "scope.allowed_paths secrets yolu icermez: '$path'"
                    continue
                }
            }
            if ($deniedOk) {
                $deniedList = @($scope.PSObject.Properties['denied_paths'].Value)
                foreach ($ap in $allowedPaths) {
                    foreach ($dp in $deniedList) {
                        if ($ap -like $dp) {
                            Add-TaskStateError "scope cakisma: allowed '$ap' denied deseniyle carpisiyor ('$dp')"
                        }
                    }
                }
            }
        }
    }

    # --- task ---
    if ($null -ne $task) {
        Test-RequiredString -Container $task -Name 'objective' -Label 'task.objective'
        $null = Test-RequiredArrayField -Container $task -Name 'acceptance_criteria' -Label 'task.acceptance_criteria'
    }

    # --- checkpoint ---
    if ($null -ne $checkpoint) {
        Test-RequiredString -Container $checkpoint -Name 'last_completed_step' -Label 'checkpoint.last_completed_step'
        Test-RequiredString -Container $checkpoint -Name 'next_action'         -Label 'checkpoint.next_action'
        $null = Test-RequiredArrayField -Container $checkpoint -Name 'files_changed'         -Label 'checkpoint.files_changed'
        $null = Test-RequiredArrayField -Container $checkpoint -Name 'verification_evidence' -Label 'checkpoint.verification_evidence'
    }

    # --- safety ---
    if ($null -ne $safety) {
        foreach ($sf in $safetyAllowed) {
            $null = Test-RequiredArrayField -Container $safety -Name $sf -Label "safety.$sf"
        }
    }

    # --- 7) Kritik write failover kapisi ---
    $autoReadonlyFailover = $true
    $autoWriteFailover    = $false
    if ($null -ne $executionPolicy) {
        $roVal = Get-PropValue -Object $executionPolicy -Name 'automatic_readonly_failover'
        $wrVal = Get-PropValue -Object $executionPolicy -Name 'automatic_write_failover'
        if ($roVal -is [bool]) { $autoReadonlyFailover = $roVal }
        if ($wrVal -is [bool]) { $autoWriteFailover = $wrVal }
    }

    if ($autoWriteFailover) {
        $nextAction = Get-PropValue -Object $checkpoint -Name 'next_action'

        # Bos dizi sayimi property-presence uzerinden yapilir; bos dizi 0 olarak sayilir.
        $allowedCount = 0
        if ((Test-PropertyExists -Object $scope -Name 'allowed_paths') -and
            ($scope.PSObject.Properties['allowed_paths'].Value -is [System.Array])) {
            $allowedCount = @($scope.PSObject.Properties['allowed_paths'].Value).Count
        }

        $criteriaCount = 0
        if ((Test-PropertyExists -Object $task -Name 'acceptance_criteria') -and
            ($task.PSObject.Properties['acceptance_criteria'].Value -is [System.Array])) {
            $criteriaCount = @($task.PSObject.Properties['acceptance_criteria'].Value).Count
        }

        if ($taskMode -ne 'write') {
            Add-TaskStateError "write failover acikken task_mode 'write' olmali (mevcut: '$taskMode')"
        }
        if (@('ready','in_progress') -notcontains $status) {
            Add-TaskStateError "write failover acikken status ready veya in_progress olmali (mevcut: '$status')"
        }
        if ($allowedCount -eq 0) {
            Add-TaskStateError 'write failover acikken scope.allowed_paths bos olamaz'
        }
        if ($criteriaCount -eq 0) {
            Add-TaskStateError 'write failover acikken task.acceptance_criteria bos olamaz'
        }
        if ($nextAction -and ($nextAction -eq 'AWAIT_HUMAN_TASK')) {
            Add-TaskStateError "write failover acikken next_action 'AWAIT_HUMAN_TASK' olamaz"
        }
        $resumeOnly = Get-PropValue -Object $executionPolicy -Name 'resume_from_checkpoint_only'
        if ($resumeOnly -isnot [bool] -or -not $resumeOnly) {
            Add-TaskStateError 'write failover acikken execution_policy.resume_from_checkpoint_only=true olmali'
        }
        $requireAcceptance = Get-PropValue -Object $executionPolicy -Name 'require_acceptance_before_complete'
        if ($requireAcceptance -isnot [bool] -or -not $requireAcceptance) {
            Add-TaskStateError 'write failover acikken execution_policy.require_acceptance_before_complete=true olmali'
        }
    }

    # --- Sonuc ---
    if ($script:TaskStateErrors.Count -gt 0) {
        foreach ($errLine in $script:TaskStateErrors) {
            Write-Host $errLine
        }
        exit 2
    }

    Write-Host 'TASK_STATE_VALID'
    exit 0
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
}
