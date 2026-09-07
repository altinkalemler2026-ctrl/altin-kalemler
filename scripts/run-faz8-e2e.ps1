<#
.SYNOPSIS
  LOCAL-ONLY Faz 8 lig E2E calistiricisi (disposable stack: faz8iso).

.DESCRIPTION
  run-faz7-e2e.ps1 deseninin disposable-stack uyarlamasi:
    - Sabit hedef: supabase_db_faz8iso / supabase_studio_faz8iso,
      API http://127.0.0.1:58321. Ana stack'e dokunulmaz.
    - Faz 7 fixture (local-faz7-e2e-fixture.sql) idempotent uygulanir
      (tum e2e.test kullanicilari temizlenir).
    - 7 fixture kullanicisi GoTrue signup ile yaratilir (ephemeral
      parolalar; sadece process belleklerinde).
    - Faz 8 lig fixture'i (local-faz8-e2e-fixture.sql) signup sonrasi
      uygulanir (sezon + uyelik + entry).
    - League spec + Faz 7 yarisma regresyon spec'i calistirilir.
  - Key/parola degerleri loga/rapora yazilmaz.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$apiUrl = "http://127.0.0.1:58321"
$specs = @("tests/e2e/league-flows.spec.ts", "tests/e2e/competition-flows.spec.ts")

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
  $anonKey = Get-ContainerEnvVar "supabase_studio_faz8iso" "SUPABASE_ANON_KEY"
  $svcKey  = Get-ContainerEnvVar "supabase_studio_faz8iso" "SUPABASE_SERVICE_KEY"

  # --- 3. Faz 7 fixture (idempotent temizlik + kasa/soru hazirlik). ---
  # psql NOTICE ciktilari stderr'a gider; EAP=Stop bunu hataya
  # cevirmesin diye gecici olarak 'Continue' kullanilir (faz7 deseni).
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  Get-Content (Join-Path $repoRoot "scripts\local-faz7-e2e-fixture.sql") -Raw |
    docker exec -i supabase_db_faz8iso psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1 | Out-Null
  $faz7FixtureExit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($faz7FixtureExit -ne 0) { throw "local-faz7-e2e-fixture.sql uygulaması başarısız." }

  # --- 4. Ephemeral parolalar (yalniz bellek). ---
  $passA = New-EphemeralPassword
  $passB = New-EphemeralPassword
  $passLA = New-EphemeralPassword

  $actors = @(
    @{ Email = "e2e-ogrenci-a@e2e.test"; Password = $passA;  Nickname = "E2E_Ogrenci_A";   Grade = "12" },
    @{ Email = "e2e-ogrenci-b@e2e.test"; Password = $passB;  Nickname = "E2E_Ogrenci_B";   Grade = "12" },
    @{ Email = "e2e8-ogrenci-a@e2e.test"; Password = $passLA; Nickname = "E2E8_Ogrenci_A"; Grade = "7" },
    @{ Email = "e2e8-ogrenci-b@e2e.test"; Password = $passLA; Nickname = "E2E8_Ogrenci_B"; Grade = "7" },
    @{ Email = "e2e8-ogrenci-c@e2e.test"; Password = $passLA; Nickname = "E2E8_GIZLI_SENTINEL"; Grade = "7" },
    @{ Email = "e2e8-ogrenci-d@e2e.test"; Password = $passLA; Nickname = "E2E8_SINIF6_SENTINEL"; Grade = "6" },
    @{ Email = "e2e8-ogrenci-e@e2e.test"; Password = $passLA; Nickname = "E2E8_SINIF8_SENTINEL"; Grade = "8" }
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
      $uid = docker exec supabase_db_faz8iso psql -U postgres -d postgres -t -A -c "SELECT id FROM auth.users WHERE email = '$($actor.Email)';"
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

  # --- 5. Faz 8 lig fixture (signup SONRASI; sezon + uyelik + entry). ---
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  Get-Content (Join-Path $repoRoot "scripts\local-faz8-e2e-fixture.sql") -Raw |
    docker exec -i supabase_db_faz8iso psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1 | Out-Null
  $faz8FixtureExit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($faz8FixtureExit -ne 0) { throw "local-faz8-e2e-fixture.sql uygulaması başarısız." }

  # --- 6. Sirlar yalnizca child-process env. ---
  $env:NEXT_PUBLIC_SUPABASE_URL = $apiUrl
  $env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = $anonKey
  $env:E2E_USER_A_EMAIL = "e2e-ogrenci-a@e2e.test"
  $env:E2E_USER_A_PASSWORD = $passA
  $env:E2E_USER_B_EMAIL = "e2e-ogrenci-b@e2e.test"
  $env:E2E_USER_B_PASSWORD = $passB
  $env:E2E_LEAGUE_A_EMAIL = "e2e8-ogrenci-a@e2e.test"
  $env:E2E_LEAGUE_A_PASSWORD = $passLA
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
  Remove-Item Env:E2E_USER_B_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_USER_B_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_LEAGUE_A_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:E2E_LEAGUE_A_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:PLAYWRIGHT_BASE_URL -ErrorAction SilentlyContinue
  Remove-Variable anonKey, svcKey, passA, passB, passLA -ErrorAction SilentlyContinue
}

if ($exitCode -eq 0) {
  Write-Output "LOCAL_ONLY_FAZ8_E2E_PASS"
}
exit $exitCode
