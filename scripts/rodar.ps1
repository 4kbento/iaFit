# iaFit: roda um arquivo .sql no banco (ou abre o psql se nenhum arquivo for passado).
# Chamado pelos .bat DEMONSTRAR, TESTAR, CONSULTAS e ABRIR_PSQL.

param([string]$Sql = '')

. (Join-Path $PSScriptRoot 'comum.ps1')
Configurar-Console

$psql = Encontrar-Psql
if (-not $psql) {
    Escrever-Erro 'PostgreSQL não encontrado. Rode o INSTALAR.bat primeiro.'
    exit 1
}
if (-not (Esperar-Servidor $psql 20)) {
    Escrever-Erro 'O servidor PostgreSQL está desligado.'
    Write-Host '  Menu Iniciar > Serviços > postgresql > Iniciar. Ou rode o INSTALAR.bat de novo.'
    exit 1
}

Set-Location $Raiz
$base = @('-h', 'localhost', '-p', $Porta, '-U', 'postgres', '-d', $Banco, '-P', 'pager=off')

if ($Sql) {
    & $psql @base -v ON_ERROR_STOP=1 -f $Sql
} else {
    Escrever-Titulo 'iaFit: terminal SQL (digite \q para sair)'
    Write-Host '  Exemplos:  SELECT * FROM vw_dashboard;    \dt    \dv    \df fn_*'
    Write-Host ''
    # No modo interativo o psql do Windows avisa quando o console não usa a página de código do Windows.
    # Usar a mesma página (ex.: 1252) tira o aviso e mantém os acentos certos no que se digita e no que aparece.
    $cp = (Get-Culture).TextInfo.ANSICodePage
    if (@(866, 874, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258) -contains $cp) {
        chcp $cp > $null
        try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding($cp) } catch { }
        try { [Console]::InputEncoding = [System.Text.Encoding]::GetEncoding($cp) } catch { }
        $env:PGCLIENTENCODING = "WIN$cp"
    }
    & $psql @base
}
exit $LASTEXITCODE
