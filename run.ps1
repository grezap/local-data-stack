<#
.SYNOPSIS
    NexusPlatform :: local-data-stack :: PowerShell task runner
    (Windows-native equivalent of the POSIX Makefile)

.DESCRIPTION
    Provides the same developer contract as `make` without requiring WSL2,
    bash, jq, awk, or column. Every verb dispatches to `docker compose`
    with the correct project directory and profile.

    This file is pure ASCII so it parses correctly under both Windows
    PowerShell 5.1 (ANSI-default) and PowerShell 7+ (UTF-8 default).

.PARAMETER Task
    One of: help | up | down | nuke | restart | pull | ps | logs | health
            urls | validate | smoke | fmt

.PARAMETER Profile
    Compose profile to activate: minimal | streaming | analytics |
    observability | full   (default: full)

.PARAMETER Service
    For `logs`: limit log tail to a single service name.

.EXAMPLE
    .\run.ps1 up
    .\run.ps1 up -Profile minimal
    .\run.ps1 logs -Service kafka
    .\run.ps1 smoke

.NOTES
    Requires: PowerShell 5.1+ (PS 7+ recommended) and Docker Desktop
    with WSL2 backend enabled. Run from the repository root.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help','up','down','nuke','restart','pull','ps','logs',
                 'health','urls','validate','smoke','fmt')]
    [string]$Task = 'help',

    [ValidateSet('minimal','streaming','analytics','observability','full')]
    [string]$Profile = 'full',

    [string]$Service = ''
)

$ErrorActionPreference = 'Stop'
# PS 7.2+ only; harmless no-op on earlier versions.
try { $PSNativeCommandUseErrorActionPreference = $true } catch { }

# --- Paths & constants ------------------------------------------------------

$RepoRoot    = $PSScriptRoot
$ComposeDir  = Join-Path $RepoRoot 'compose'
$ComposeFile = Join-Path $ComposeDir 'docker-compose.yml'

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
    & docker compose --project-directory $ComposeDir -f $ComposeFile @Args
    if ($LASTEXITCODE -ne 0) { throw "docker compose exited with $LASTEXITCODE" }
}

function Assert-Prereqs {
    foreach ($cmd in @('docker')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "Required command '$cmd' not found on PATH. Install Docker Desktop and retry."
        }
    }
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Warning "PowerShell 7+ recommended. Detected: $($PSVersionTable.PSVersion)."
    }
}

# --- Task implementations ---------------------------------------------------

function Show-Help {
@"

NexusPlatform :: local-data-stack :: PowerShell runner
------------------------------------------------------

  .\run.ps1 <task> [-Profile <p>] [-Service <s>]

Tasks
  help         Show this help
  up           Bring the stack up            (default profile: full)
  down         Stop, keep volumes
  nuke         DESTRUCTIVE: stop + wipe all named volumes
  restart      down then up
  pull         Pull latest pinned images
  ps           List running services
  logs         Tail logs (-Service <name> to target one)
  health       Print health state of each container
  urls         Print local UI URLs
  validate     docker compose config (lint + render)
  smoke        End-to-end smoke test (scripts\smoke.ps1)
  fmt          Format YAML/JSON with Prettier (via npx)

Examples
  .\run.ps1 up
  .\run.ps1 up -Profile minimal
  .\run.ps1 logs -Service kafka
  .\run.ps1 smoke

"@ | Write-Host
}

function Show-Urls {
    Write-Host ""
    Write-Host "  NexusPlatform :: local-data-stack" -ForegroundColor Cyan
    Write-Host "  ---------------------------------"
    Write-Host "  Grafana           http://127.0.0.1:3000      (admin / admin)"
    Write-Host "  Prometheus        http://127.0.0.1:9090"
    Write-Host "  Jaeger            http://127.0.0.1:16686"
    Write-Host "  Seq               http://127.0.0.1:5341"
    Write-Host "  ClickHouse HTTP   http://127.0.0.1:8123      (nexus / nexus-dev)"
    Write-Host "  Schema Registry   http://127.0.0.1:8081"
    Write-Host "  Kafka (external)  127.0.0.1:9094"
    Write-Host "  OTLP gRPC         127.0.0.1:4317"
    Write-Host "  OTLP HTTP         127.0.0.1:4318"
    Write-Host ""
}

function Invoke-Up {
    Invoke-Compose --profile $Profile up -d --remove-orphans
    Show-Urls
}

function Invoke-Down    { Invoke-Compose --profile full down --remove-orphans }
function Invoke-Nuke    {
    Write-Warning "This will DELETE all named volumes (Kafka, ClickHouse, Prometheus, Grafana, Seq, Jaeger, Redis data)."
    $confirm = Read-Host "Type 'yes' to proceed"
    if ($confirm -ne 'yes') { Write-Host "Aborted."; return }
    Invoke-Compose --profile full down --remove-orphans --volumes
}
function Invoke-Restart { Invoke-Down; Invoke-Up }
function Invoke-Pull    { Invoke-Compose --profile full pull }
function Invoke-Ps      { Invoke-Compose ps }

function Invoke-Logs {
    if ([string]::IsNullOrEmpty($Service)) {
        Invoke-Compose logs -f --tail=200
    } else {
        Invoke-Compose logs -f --tail=200 $Service
    }
}

function Invoke-Health {
    $rows = docker ps --format '{{json .}}' |
            ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object   { $_.Names -like 'nexus-*' } |
            Select-Object  @{n='Name';   e={$_.Names}},
                           @{n='State';  e={$_.State}},
                           @{n='Status'; e={$_.Status}}
    if (-not $rows) { Write-Host "No nexus-* containers running."; return }
    $rows | Format-Table -AutoSize
}

function Invoke-Validate {
    Invoke-Compose --profile full config -q
    Write-Host "OK: compose file is valid." -ForegroundColor Green
}

function Invoke-Smoke {
    $smoke = Join-Path $RepoRoot 'scripts\smoke.ps1'
    if (-not (Test-Path $smoke)) { throw "Missing $smoke" }
    & $smoke
    if ($LASTEXITCODE -ne 0) { throw "smoke test failed ($LASTEXITCODE)" }
}

function Invoke-Fmt {
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw "npx not found. Install Node.js, then re-run."
    }
    # Quote the glob so PowerShell does not try to expand it.
    $pattern = 'compose/**/*.{yml,yaml,json}'
    npx --yes prettier --write $pattern
}

# --- Dispatch ---------------------------------------------------------------

Assert-Prereqs

switch ($Task) {
    'help'     { Show-Help }
    'up'       { Invoke-Up }
    'down'     { Invoke-Down }
    'nuke'     { Invoke-Nuke }
    'restart'  { Invoke-Restart }
    'pull'     { Invoke-Pull }
    'ps'       { Invoke-Ps }
    'logs'     { Invoke-Logs }
    'health'   { Invoke-Health }
    'urls'     { Show-Urls }
    'validate' { Invoke-Validate }
    'smoke'    { Invoke-Smoke }
    'fmt'      { Invoke-Fmt }
}
