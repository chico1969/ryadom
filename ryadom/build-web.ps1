$ErrorActionPreference='Stop'
$ryadomRoot=Split-Path -Parent $PSScriptRoot
$env:RYADOM_TURN_CONFIG=''
$engine=Join-Path $ryadomRoot 'flutter/web/js'
Push-Location $engine
try {
    & npm ci --ignore-scripts --no-fund
    if($LASTEXITCODE -ne 0){throw 'Не установлены зависимости TypeScript'}
    & npm test
    if($LASTEXITCODE -ne 0){throw 'Тесты браузерного движка не прошли'}
    & npm run build
    if($LASTEXITCODE -ne 0){throw 'Браузерный движок не собран'}
} finally {Pop-Location}
$ui=Join-Path $PSScriptRoot 'ui'
Copy-Item -LiteralPath (Join-Path $ryadomRoot 'flutter/web/ryadom.js'),(Join-Path $ryadomRoot 'flutter/web/ryadom.css'),(Join-Path $ryadomRoot 'flutter/web/THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $ui 'web') -Force
Push-Location $ui
try {
    & flutter pub get
    if($LASTEXITCODE -ne 0){throw 'Не установлены зависимости Flutter'}
    & dart analyze lib
    if($LASTEXITCODE -ne 0){throw 'Ошибки Flutter-интерфейса'}
    & flutter build web --release --no-web-resources-cdn
    if($LASTEXITCODE -ne 0){throw 'Веб-интерфейс не собран'}
} finally {Pop-Location}
