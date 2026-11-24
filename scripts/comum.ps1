# Funções usadas pelos .bat do iaFit. Não precisa rodar este arquivo direto.

$ErrorActionPreference = 'Continue'
$Raiz  = Split-Path -Parent $PSScriptRoot
$Porta = 5432
$Banco = 'iafit'

function Configurar-Console {
    try { chcp 65001 > $null } catch { }
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    $env:PGCLIENTENCODING = 'UTF8'
}

function Escrever-Titulo([string]$texto) {
    Write-Host ''
    Write-Host ('=' * 64) -ForegroundColor DarkCyan
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host ('=' * 64) -ForegroundColor DarkCyan
}

function Escrever-Passo([string]$texto)  { Write-Host "`n> $texto" -ForegroundColor Yellow }
function Escrever-Ok([string]$texto)     { Write-Host "  OK  $texto" -ForegroundColor Green }
function Escrever-Erro([string]$texto)   { Write-Host "  ERRO  $texto" -ForegroundColor Red }

# Procura o psql.exe: primeiro no PATH, depois nas pastas padrão do instalador (versão mais nova primeiro)
function Encontrar-Psql {
    $cmd = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $bases = @("$env:ProgramFiles\PostgreSQL")
    if (${env:ProgramFiles(x86)}) { $bases += "${env:ProgramFiles(x86)}\PostgreSQL" }

    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        $versoes = Get-ChildItem $base -Directory | Sort-Object {
            $n = 0.0
            [void][double]::TryParse(($_.Name -replace '[^\d.]', ''), [ref]$n)
            $n
        } -Descending
        foreach ($v in $versoes) {
            $p = Join-Path $v.FullName 'bin\psql.exe'
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

function Caminho-Bin([string]$psql, [string]$exe) {
    return Join-Path (Split-Path -Parent $psql) $exe
}

# Espera o servidor aceitar conexões (até $segundos)
function Esperar-Servidor([string]$psql, [int]$segundos = 60) {
    $isready = Caminho-Bin $psql 'pg_isready.exe'
    for ($i = 0; $i -lt $segundos; $i += 2) {
        & $isready -h localhost -p $Porta -q
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# Grava a senha em %APPDATA%\postgresql\pgpass.conf, para o psql não pedir de novo
function Salvar-Senha([string]$senha) {
    $pasta = Join-Path $env:APPDATA 'postgresql'
    if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta | Out-Null }
    $arquivo = Join-Path $pasta 'pgpass.conf'
    $prefixo = "localhost:${Porta}:*:postgres:"
    $linhas = @()
    if (Test-Path $arquivo) {
        $linhas = @(Get-Content $arquivo | Where-Object { -not $_.StartsWith($prefixo) })
    }
    $escapada = $senha.Replace('\', '\\').Replace(':', '\:')
    $linhas += "$prefixo$escapada"
    [System.IO.File]::WriteAllLines($arquivo, [string[]]$linhas)
    return $arquivo
}

# Testa a conexão sem pedir senha (usa PGPASSWORD ou o pgpass.conf)
function Testar-Conexao([string]$psql) {
    $r = & $psql -h localhost -p $Porta -U postgres -d postgres -w -tAc 'SELECT 1' 2>$null
    return ($LASTEXITCODE -eq 0 -and "$r".Trim() -eq '1')
}

# Procura o node.exe: PATH, pasta padrão do instalador ou instalação por usuário
function Encontrar-Node {
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Instalar-Node {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Escrever-Erro 'O winget não está disponível. Instale o Node.js LTS em https://nodejs.org e rode de novo.'
        return $null
    }
    Write-Host '  Vou instalar o Node.js LTS pelo winget (cerca de 30 MB). O Windows pode pedir permissão: clique em Sim.'
    Read-Host '  Aperte Enter para instalar (ou feche esta janela para cancelar)' | Out-Null
    winget install --id OpenJS.NodeJS.LTS --exact --source winget --accept-package-agreements --accept-source-agreements | Out-Host
    return (Encontrar-Node)
}
