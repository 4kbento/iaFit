# iaFit: liga o servidor do app (Node.js) e abre as telas no navegador.
# Chamado pelo ABRIR_APP.bat. Deixe a janela aberta enquanto usa o app.

. (Join-Path $PSScriptRoot 'comum.ps1')
Configurar-Console
Escrever-Titulo 'iaFit: telas do app ligadas ao PostgreSQL'

$psql = Encontrar-Psql
if (-not $psql) { Escrever-Erro 'PostgreSQL não encontrado. Rode o INSTALAR.bat primeiro.'; exit 1 }
if (-not (Esperar-Servidor $psql 20)) {
    Escrever-Erro 'O servidor PostgreSQL está desligado.'
    Write-Host '  Menu Iniciar > Serviços > postgresql > Iniciar. Ou rode o INSTALAR.bat de novo.'
    exit 1
}

$node = Encontrar-Node
if (-not $node) {
    Write-Host '  O Node.js não está instalado.'
    $node = Instalar-Node
    if (-not $node) { exit 1 }
}

Set-Location (Join-Path $Raiz 'app')
$env:PGHOST = 'localhost'
$env:PGPORT = "$Porta"
$env:PGDATABASE = $Banco
$env:PGUSER = 'postgres'
& $node server.js
exit $LASTEXITCODE
