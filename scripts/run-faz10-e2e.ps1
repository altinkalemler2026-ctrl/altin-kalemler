<#
.SYNOPSIS
  LOCAL-ONLY Faz 10 profil/avatar E2E calistiricisi (disposable stack: faz10iso).

.DESCRIPTION
  run-faz8-e2e.ps1 deseninin Faz 10 uyarlamasi:
    - Sabit hedef: supabase_db_faz10iso / supabase_studio_faz10iso,
      API http://127.0.0.1:54341. Ana stack'e dokunulmaz.
    - Faz 10 fixture (local-faz10-e2e-fixture.sql) idempotent uygulanir.
    - Fixture kullanicilari GoTrue signup ile yaratilir (ephemeral
      parolalar; yalnizca process belleklerinde).
    - profile-flows spec'i calistirilir.
  - Key/parola degerleri loga/rapora yazilmaz.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$apiUrl = "http://127.0.0.1:54341"
$specs = @("tests/e2e/profile-flows.spec.ts")

$exitCode = 0

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
  # --- 1. API saglik. ---
  $resp = $null
  try {
    $resp = Invoke-WebRequest -Uri "$apiUrl/auth/v1/health" -UseBasicParsing -TimeoutSec 10
  } catch {
    throw "Disposable Supabase gateway not reachable at $apiUrl."
  }
  if ($resp.StatusCode -ne 200) { throw "Gateway returned $($resp.StatusCode)." }

  # --- 2. LOCAL anahtarlar (yalniz bellek). ---
  $anonKey = Get-ContainerEnvVar "supabase_studio_faz10iso" "SUPABASE_ANON_KEY"
  $svcKey  = Get-ContainerEnvVar "supabase_studio_faz10iso" "SUPABASE_SERVICE_KEY"

  # --- 3. Ephemeral parolalar (yalniz bellek). ---
  $passA = New-EphemeralPassword
  $passLA = New-EphemeralPassword

  $actors = @(
    @{ Email = "e2e10-ogrenci-a@e2e.test"; Password = $passA;  Nickname = "E2E10_Ogrenci_A";   Grade = "7" },
    @{ Email = "e2e10-ogrenci-b@e2e.test"; Password = $passLA; Nickname = "E2E10_Ogrenci_B";   Grade = "7" },
    @{ Email = "e2e10-ogrenci-c@e2e.test"; Password = $passLA; Nickname = "E2E10_GIZLI_SENTINEL"; Grade = "7" },
    @{ Email = "e2e10-sinif6@e2e.test";    Password = $passLA; Nickname = "E2E10_SINIF6_SENTINEL"; Grade = "6" },
    @{ Email = "e2e10-sinif8@e2e.test";    Password = $passLA; Nickname = "E2E10_SINIF8_SENTINEL"; Grade = "8" }
  )

  $anonHeaders = @{ apikey = $anonKey }
  $adminHeaders = @{ apikey = $svcKey; Authorization = "Bearer $svcKey" }

  foreach ($actor in $actors) {
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
      $uid = docker exec supabase_db_faz10iso psql -U postgres -d postgres -t -A -c "SELECT id FROM auth.users WHERE email = '$($actor.Email)';"
      if (-not $uid) { throw "Fixture user missing in local DB: $($actor.Email)" }
      $pwBody = @{ password = $actor.Password } | ConvertTo-Json
      try {
        $null = Invoke-RestMethod -Method Put `
          -Uri "$apiUrl/auth/v1/admin/users/$uid" `
          -Headers $adminHeaders -ContentType "application/json" -Body $pwBody -TimeoutSec 20
      } catch {
        throw "Local password renewal failed ($($_.Exception.Response.StatusCode.value__))."
      }
    }
    if (-not $signedUp) { Write-Output "Fixture user renewed via admin API: $($actor.Email)" }

    $loginBody = @{ email = $actor.Email; password = $actor.Password } | ConvertTo-Json
    try {
      $null = Invoke-RestMethod -Method Post `
        -Uri "$apiUrl/auth/v1/token?grant_type=password" `
        -Headers $anonHeaders -ContentType "application/json" -Body $loginBody -TimeoutSec 20
    } catch {
      throw "Fixture user login verification failed: $($actor.Email)"
    }
  }

  # --- 4. Faz 10 fixture (signup SONRASI; sezon + pp + uyelik). ---
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  Get-Content (Join-Path $repoRoot "scripts\local-faz10-e2e-fixture.sql") -Raw |
    docker exec -i supabase_db_faz10iso psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1 | Out-Null
  $faz10FixtureExit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($faz10FixtureExit -ne 0) { throw "local-faz10-e2e-fixture.sql uygulaması başarısız." }

  # --- 5. Sirlar yalnizca child-process env. ---
  $env:NEXT_PUBLIC_SUPABASE_URL = $apiUrl
  $env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = $anonKey
  $env:E2E_USER_A_EMAIL = "e2e10-ogrenci-a@e2e.test"
  $env:E2E_USER_A_PASSWORD = $passA
  $env:PLAYWRIGHT_BASE_URL = "http://localhost:3000"

  foreach ($spec in $specs) {
    Write-Output "Running local-only E2E spec: $spec ..."
    & (Join-Path $repoRoot "node_modules\.bin\playwright.cmd") test $spec
    $code = $LASTEXITCODE
    Write-Output "Playwright exit code ($spec): $code"
    if ($code -ne 0) { $exitCode = $code }
  }
}
catch {
  Write-Error ("{0} (satir {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
  $exitCode = 1
}
finally {
  Remove-Item Env:NEXT_PUBLIC_SUPABASE_URL -ErrorAction SilentlyContinue
  Remove-Item Env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_A_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_A_PASSWORD -ErrorAction SilentlyContinue
  Remove-Variable anonKey, svcKey, passA, passLA -ErrorAction SilentlyContinue
}

if ($exitCode -eq 0) {
  Write-Output "LOCAL_ONLY_FAZ10_E2E_PASS"
}
exit $exitCode
