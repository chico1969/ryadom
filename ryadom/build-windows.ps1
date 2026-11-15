param([switch]$BundleTestTurn)
$ErrorActionPreference='Stop'
$ryadomRoot=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'prepare-submodule.ps1')
& (Join-Path $PSScriptRoot 'prepare-network.ps1')
$features='flutter,ryadom'
$buildArgs=@('build.py','--flutter','--ryadom')
if($BundleTestTurn){
    $private=Join-Path $ryadomRoot '.tools/turn.express.local.json'
    $generated=Join-Path $ryadomRoot '.tools/turn-bundle.generated.rs'
    & node (Join-Path $PSScriptRoot 'prepare-test-turn.mjs') $private $generated
    if($LASTEXITCODE -ne 0){throw 'Не подготовлен семейный TURN'}
    $env:RYADOM_TURN_BUNDLE_SOURCE=$generated
    $features='flutter,ryadom-bundled-turn'
    $buildArgs+='--ryadom-test-turn'
}
if(-not(Test-Path (Join-Path $ryadomRoot 'src/bridge_generated.rs'))){
    throw 'Нужен артефакт bridge-artifact из закреплённого workflow .github/workflows/bridge.yml. Локальный codegen не запускается согласно AGENTS.md.'
}
Push-Location $ryadomRoot
try {
    $env:PIP_CONSTRAINT=([Uri](Join-Path $PSScriptRoot 'python-constraints.txt')).AbsoluteUri
    $env:PIP_DISABLE_PIP_VERSION_CHECK='1'
    & (Join-Path $PSScriptRoot 'prepare-flutter-plugins.ps1') -Restore
    & cargo test --locked --lib --features $features ryadom
    if($LASTEXITCODE -ne 0){throw 'Тесты Windows-ядра не прошли'}
    & python @buildArgs
    if($LASTEXITCODE -ne 0){throw 'Сборка Windows не завершилась'}
    & python (Join-Path $PSScriptRoot 'check-windows-package.py')
    if($LASTEXITCODE -ne 0){throw 'Имя приложения в пакете не соответствует службе'}
    $portable=Join-Path $ryadomRoot 'rustdesk-1.5.3-install.exe'
    if(-not(Test-Path -LiteralPath $portable)){throw 'Упаковщик не создал переносной EXE'}
    $dist=Join-Path $ryadomRoot 'dist/development'
    New-Item -ItemType Directory -Force $dist | Out-Null
    Copy-Item -LiteralPath $portable -Destination (Join-Path $dist 'Ryadom.exe') -Force
    Copy-Item -LiteralPath $portable -Destination (Join-Path $dist 'Ryadom-Setup.exe') -Force
} finally {Pop-Location}
