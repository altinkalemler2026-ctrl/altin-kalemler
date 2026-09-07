<#
.SYNOPSIS
  LOCAL-ONLY Faz 7 yarisma E2E akis calistiricisi.

.DESCRIPTION
  run-local-e2e.ps1 deseninin Faz 7 uyarlamasi. Farklar:
    - Local Supabase API portu config.toml yerine CALISAN stack'ten
      (docker port supabase_kong_yarisma-programi) cozulur; bu stack
      ozel portlarla calistigi icin config'ye bagli kalmak hatali port
      verir. Config port'u yalnizca docker cozumlemesi basarisizsa
      yedek olarak denenir ve health-check ile dogrulanir.
    - Yarisma fixture'lari (local-auth-e2e-fixture.sql +
      local-faz7-e2e-fixture.sql) idempotent olarak uygulanir.
  - LOCAL anon + service key'leri yalnizca process belleklerinde okunur.
  - Iki fixture kullanicisinin ephemeral parolalari yalnizca LOCAL GoTrue
    Admin API ile set edilir; kaynak koda/terminal raporuna yazilmaz.
  - Remote Supabase'e asla baglanilmaz; .env.local okunmaz/degistirilmez.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$appUrl = "http://localhost:3000"
$spec = "tests/e2e/competition-flows.spec.ts"

$success = $false
$exitCode = 1

# --- Local API portunu CALISAN stack'ten coz. ---
function Resolve-LocalApiUrl {
  $mapped = (docker port supabase_kong_yarisma-programi 8000 2>$null) -join " "
  $port = $null
  if ($mapped -match ':(\d+)') { $port = [int]$matches[1] }

  if ($null -eq $port) {
    # Yedek: config.toml [api] portu (yalniz health-check ile dogrulanir).
    $configToml = Join-Path $repoRoot "supabase\config.toml"
    foreach ($line in Get-Content -LiteralPath $configToml) {
      if ($line -match '^\[api\]\s*$') { $inApi = $true; continue }
      if ($inApi -and $line -match '^port\s*=\s*(\d+)\s*$') { $port = [int]$matches[1]; break }
      if ($inApi -and $line -match '^\[') { $inApi = $false }
    }
  }

  if ($null -eq $port -or $port -lt 1 -or $port -gt 65535) {
    throw "Local Supabase API portu cozulemedi (docker/config). Aborting (no remote allowed)."
  }

  $apiUrl = "http://127.0.0.1:$port"
  $resp = $null
  try {
    $resp = Invoke-WebRequest -Uri "$apiUrl/auth/v1/health" -UseBasicParsing -TimeoutSec 10
  } catch {
    throw "Local Supabase gateway not reachable at $apiUrl."
  }
  if ($resp.StatusCode -ne 200) { throw "Local Supabase gateway returned $($resp.StatusCode)." }
  return $apiUrl
}

$apiUrl = Resolve-LocalApiUrl

function Get-ContainerEnvVar {
  param([string]$Container, [string]$Name)
  $val = $null
  (docker exec $Container env) | ForEach-Object {
    if ($_ -match "^$Name=(.*)$") { $val = $matches[1] }
  }
  if ($null -eq $val -or $val -eq "") { throw "Missing env var '$Name' in container '$Container'." }
  return $val
}

function New-EphemeralPassword {
  $bytes = New-Object byte[] 24
  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  $b64 = [Convert]::ToBase64String($bytes)
  return ($b64 -replace '[+/=]', 'A')
}

try {
  # --- 1. Fixture (idempotent; e2e.test kullanicilari temizlenir). ---
  # NOT: psql NOTICE ciktilari stderr'a gider; EAP=Stop bunu hataya
  # cevirmesin diye gecici olarak 'Continue' kullanilir.
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  Get-Content (Join-Path $repoRoot "scripts\local-faz7-e2e-fixture.sql") -Raw |
    docker exec -i supabase_db_yarisma-programi psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1 | Out-Null
  $faz7FixtureExit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($faz7FixtureExit -ne 0) { throw "local-faz7-e2e-fixture.sql uygulaması başarısız." }

  # --- 2. LOCAL anahtarlar (yalniz bellek). ---
  $anonKey = Get-ContainerEnvVar "supabase_studio_yarisma-programi" "SUPABASE_ANON_KEY"
  $svcKey  = Get-ContainerEnvVar "supabase_studio_yarisma-programi" "SUPABASE_SERVICE_KEY"

  # --- 3. Ephemeral parolalar (yalniz bellek). ---
  $passA = New-EphemeralPassword
  $passB = New-EphemeralPassword

  # --- 4. Fixture kullanicilarini LOCAL GoTrue signup ile yarat.
  #        (083 trigger raw_user_meta_data'dan student_profiles uretir.)
  #        Zaten kayitliysa (onceki kosu) admin API ile parola yenilenir.
  $anonHeaders = @{ apikey = $anonKey }
  $adminHeaders = @{ apikey = $svcKey; Authorization = "Bearer $svcKey" }

  foreach ($actor in @(
    @{ Email = "e2e-ogrenci-a@e2e.test"; Password = $passA; Nickname = "E2E_Ogrenci_A"; Grade = "12" },
    @{ Email = "e2e-ogrenci-b@e2e.test"; Password = $passB; Nickname = "E2E_Ogrenci_B"; Grade = "12" }
  )) {
    $signupBody = @{
      email    = $actor.Email
      password = $actor.Password
      data     = @{ nickname = $actor.Nickname; grade_level = $actor.Grade }
    } | ConvertTo-Json
    $signedUp = $false
    try {
      $null = Invoke-RestMethod -Method Post `
        -Uri "$apiUrl/auth/v1/signup" `
        -Headers $anonHeaders -ContentType "application/json" -Body $signupBody -TimeoutSec 20
      $signedUp = $true
    } catch {
      # Zaten kayitli: admin PUT ile parola yenilenir (yalnizca
      # GoTrue tarafindan yaratilmis bu fixture kullaniciya dokunulur).
      $uid = docker exec supabase_db_yarisma-programi psql -U postgres -d postgres -t -A -c "SELECT id FROM auth.users WHERE email = '$($actor.Email)';"
      if (-not $uid) { throw "Fixture user missing in local DB: $($actor.Email)" }
      $pwBody = @{ password = $actor.Password } | ConvertTo-Json
      try {
        $null = Invoke-RestMethod -Method Put `
          -Uri "$apiUrl/auth/v1/admin/users/$uid" `
          -Headers $adminHeaders -ContentType "application/json" -Body $pwBody -TimeoutSec 20
      } catch {
        throw "Local password renewal failed for fixture user ($($_.Exception.Response.StatusCode.value__))."
      }
    }
    if (-not $signedUp) { Write-Output "Fixture user renewed via admin API: $($actor.Email)" }

    # Parola set oldugunu dogrula (login token kontrolu; token basilmaz).
    $loginBody = @{ email = $actor.Email; password = $actor.Password } | ConvertTo-Json
    try {
      $null = Invoke-RestMethod -Method Post `
        -Uri "$apiUrl/auth/v1/token?grant_type=password" `
        -Headers $anonHeaders -ContentType "application/json" -Body $loginBody -TimeoutSec 20
    } catch {
      throw "Fixture user login verification failed: $($actor.Email)"
    }
  }

  # --- 6. Sirlar yalnizca child-process env. ---
  $env:NEXT_PUBLIC_SUPABASE_URL = $apiUrl
  $env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = $anonKey
  $env:E2E_USER_A_EMAIL = "e2e-ogrenci-a@e2e.test"
  $env:E2E_USER_A_PASSWORD = $passA
  $env:E2E_USER_B_EMAIL = "e2e-ogrenci-b@e2e.test"
  $env:E2E_USER_B_PASSWORD = $passB
  $env:PLAYWRIGHT_BASE_URL = $appUrl

  Write-Output "Running local-only Faz 7 competition E2E (target: $appUrl, api: $apiUrl) ..."
  & (Join-Path $repoRoot "node_modules\.bin\playwright.cmd") test $spec
  $exitCode = $LASTEXITCODE
  Write-Output "Playwright exit code: $exitCode"

  if (-not $success -and $exitCode -eq 0) { $success = $true }
}
catch {
  Write-Error ("{0} (satir {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
  $exitCode = 1
}
finally {
  # --- 7. Hassas env temizligi. ---
  Remove-Item Env:NEXT_PUBLIC_SUPABASE_URL -ErrorAction SilentlyContinue
  Remove-Item Env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_A_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_A_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_B_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_B_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:PLAYWRIGHT_BASE_URL -ErrorAction SilentlyContinue
  Remove-Variable anonKey, svcKey, passA, passB -ErrorAction SilentlyContinue
}

if ($success) {
  Write-Output "LOCAL_ONLY_FAZ7_COMPETITION_E2E_PASS"
}
exit $exitCode
