# iaFit: instala o PostgreSQL (se precisar), cria o banco iafit, carrega os dados e roda os testes.
# Chamado pelo INSTALAR.bat. Pode rodar de novo quantas vezes quiser: recria o banco do zero.

. (Join-Path $PSScriptRoot 'comum.ps1')
Configurar-Console

$SenhaPadrao = 'iafit2026'
$senha = $null

Escrever-Titulo 'iaFit: instalação do banco de dados'

# ---------------------------------------------------------------------
# 1. PostgreSQL instalado?
# ---------------------------------------------------------------------
Escrever-Passo 'Procurando o PostgreSQL neste computador'
$psql = Encontrar-Psql

if ($psql) {
    Escrever-Ok "Encontrado: $psql"
} else {
    Write-Host '  O PostgreSQL não está instalado.'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Escrever-Erro 'O winget (instalador do Windows) não está disponível neste computador.'
        Write-Host '  Instale o PostgreSQL 17 manualmente:'
        Write-Host '    1. Baixe em https://www.enterprisedb.com/downloads/postgres-postgresql-downloads (Windows x86-64)'
        Write-Host "    2. Na instalação, use a senha $SenhaPadrao e a porta 5432"
        Write-Host '    3. Rode o INSTALAR.bat de novo'
        exit 1
    }

    Write-Host ''
    Write-Host '  Vou instalar o PostgreSQL 17 com o pgAdmin 4 pelo winget (fonte oficial, cerca de 350 MB).'
    Write-Host "  Usuário: postgres | Senha: $SenhaPadrao | Porta: 5432"
    Write-Host '  O Windows vai pedir permissão de administrador: clique em Sim.'
    Write-Host '  A instalação leva de 3 a 8 minutos.'
    Write-Host ''
    Read-Host '  Aperte Enter para instalar (ou feche esta janela para cancelar)' | Out-Null

    $override = "--mode unattended --unattendedmodeui minimal --superpassword $SenhaPadrao --serverport $Porta --disable-components stackbuilder"
    winget install --id PostgreSQL.PostgreSQL.17 --exact --source winget `
        --accept-package-agreements --accept-source-agreements --override $override
    $codigoWinget = $LASTEXITCODE

    $psql = Encontrar-Psql
    if (-not $psql) {
        Escrever-Erro "A instalação não terminou (código $codigoWinget)."
        Write-Host '  Se você clicou em Não na permissão de administrador, rode o INSTALAR.bat de novo e clique em Sim.'
        exit 1
    }
    Escrever-Ok "PostgreSQL instalado: $psql"
    $senha = $SenhaPadrao
}

# ---------------------------------------------------------------------
# 2. Servidor rodando?
# ---------------------------------------------------------------------
Escrever-Passo 'Conferindo se o servidor está ligado'
if (-not (Esperar-Servidor $psql 10)) {
    Write-Host '  O servidor está parado. Tentando iniciar o serviço...'
    Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Running' } | ForEach-Object {
        try { Start-Service $_.Name -ErrorAction Stop; Write-Host "  Serviço $($_.Name) iniciado." }
        catch { Write-Host "  Não consegui iniciar $($_.Name) sem permissão de administrador." }
    }
    if (-not (Esperar-Servidor $psql 60)) {
        Escrever-Erro 'O servidor não respondeu na porta 5432.'
        Write-Host '  Abra o menu Iniciar, digite "Serviços", procure "postgresql", clique com o botão direito e escolha Iniciar.'
        Write-Host '  Depois rode o INSTALAR.bat de novo.'
        exit 1
    }
}
Escrever-Ok 'Servidor respondendo em localhost:5432'

# ---------------------------------------------------------------------
# 3. Senha do usuário postgres
# ---------------------------------------------------------------------
Escrever-Passo 'Conectando como usuário postgres'
if ($senha) { $env:PGPASSWORD = $senha }

if (-not (Testar-Conexao $psql)) {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Write-Host '  Digite a senha do usuário postgres (a que você escolheu quando instalou o PostgreSQL).'
    for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
        $segura = Read-Host '  Senha' -AsSecureString
        $senha = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
        $env:PGPASSWORD = $senha
        if (Testar-Conexao $psql) { break }
        Escrever-Erro 'Senha não confere.'
        $senha = $null
    }
    if (-not $senha) {
        Escrever-Erro 'Não consegui conectar. Rode o INSTALAR.bat de novo quando lembrar a senha.'
        exit 1
    }
}
Escrever-Ok 'Conectado'

if ($senha) {
    $arquivoSenha = Salvar-Senha $senha
    Escrever-Ok "Senha salva em $arquivoSenha (os outros .bat não vão pedir)"
}

# ---------------------------------------------------------------------
# 4. Banco iafit
# ---------------------------------------------------------------------
Escrever-Passo 'Criando o banco iafit'
$existe = & $psql -h localhost -p $Porta -U postgres -d postgres -w -tAc "SELECT 1 FROM pg_database WHERE datname = '$Banco'"
if ("$existe".Trim() -eq '1') {
    Write-Host '  O banco já existe: o schema será recriado do zero.'
} else {
    & $psql -h localhost -p $Porta -U postgres -d postgres -w -q -c "CREATE DATABASE $Banco ENCODING 'UTF8' TEMPLATE template0"
    if ($LASTEXITCODE -ne 0) { Escrever-Erro 'Não consegui criar o banco.'; exit 1 }
}
& $psql -h localhost -p $Porta -U postgres -d postgres -w -q -c "ALTER DATABASE $Banco SET search_path = iafit, public"
Escrever-Ok 'Banco iafit pronto'

Set-Location $Raiz
$conexao = @('-h', 'localhost', '-p', $Porta, '-U', 'postgres', '-d', $Banco, '-w', '-q', '-P', 'pager=off', '-v', 'ON_ERROR_STOP=1')

Escrever-Passo 'Criando tabelas, views, funções e triggers (banco\01_schema.sql)'
& $psql @conexao -f 'banco\01_schema.sql'
if ($LASTEXITCODE -ne 0) { Escrever-Erro 'Falha no 01_schema.sql (veja a mensagem acima).'; exit 1 }
Escrever-Ok '21 tabelas, 6 views, 9 funções e 7 triggers'

Escrever-Passo 'Carregando dados de exemplo (banco\02_seed.sql)'
& $psql @conexao -f 'banco\02_seed.sql'
if ($LASTEXITCODE -ne 0) { Escrever-Erro 'Falha no 02_seed.sql (veja a mensagem acima).'; exit 1 }
Escrever-Ok '3 usuários, 28 alimentos, 24 exercícios, planos, treinos, progresso e conversas'

Escrever-Passo 'Rodando os testes automáticos (banco\04_testes.sql)'
& $psql @conexao -f 'banco\04_testes.sql'
if ($LASTEXITCODE -ne 0) { Escrever-Erro 'Algum teste falhou (veja a mensagem acima).'; exit 1 }

# ---------------------------------------------------------------------
# 5. Node.js (para o ABRIR_APP.bat, que mostra as telas do app usando o banco)
# ---------------------------------------------------------------------
Escrever-Passo 'Conferindo o Node.js (usado pelas telas do app)'
$node = Encontrar-Node
if (-not $node) {
    Write-Host '  O Node.js não está instalado.'
    $node = Instalar-Node
}
if ($node) {
    $versao = & $node --version
    Escrever-Ok "Node.js $versao em $node"
} else {
    Escrever-Erro 'Sem Node.js o ABRIR_APP.bat não funciona. O banco e os outros atalhos funcionam normalmente.'
}

# ---------------------------------------------------------------------
Escrever-Titulo 'Pronto: o banco iafit está funcionando'
Write-Host '  Servidor: localhost  |  Porta: 5432  |  Banco: iafit  |  Usuário: postgres'
if ($senha -eq $SenhaPadrao) { Write-Host "  Senha: $SenhaPadrao" }
Write-Host ''
Write-Host '  Próximos passos:'
Write-Host '    ABRIR_APP.bat   abre as telas do iaFit no navegador, gravando neste banco'
Write-Host '    DEMONSTRAR.bat  demonstração guiada do banco no terminal (10 etapas)'
Write-Host '    TESTAR.bat      roda os 14 testes de novo'
Write-Host '    CONSULTAS.bat   roda a consulta de cada tela do app'
Write-Host '    ABRIR_PSQL.bat  terminal SQL para consultas livres'
Write-Host '    pgAdmin 4       menu Iniciar > pgAdmin 4 > Servers > PostgreSQL > Databases > iafit'
exit 0
