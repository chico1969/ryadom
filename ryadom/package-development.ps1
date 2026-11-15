param([switch]$SkipWeb)
$ErrorActionPreference='Stop'
$ryadomRoot=Split-Path -Parent $PSScriptRoot
$dist=Join-Path $ryadomRoot 'dist/development'
$staging=Join-Path $ryadomRoot ('.tools/source-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $dist,$staging | Out-Null
Push-Location $ryadomRoot
try{
    $files=@(& git ls-files)+@(& git ls-files --others --exclude-standard)
    $ryadomHbbPath=(Join-Path $ryadomRoot 'libs/hbb_common').Replace('\','/')
    $files+=@(& git -c "safe.directory=$ryadomHbbPath" -C $ryadomHbbPath ls-files | ForEach-Object {'libs/hbb_common/'+$_})
    if($LASTEXITCODE -ne 0){throw 'Не получен полный список исходников hbb_common'}
    $files+=@('libs/hbb_common/src/ryadom_dpapi.rs','libs/hbb_common/src/ryadom_network.rs','src/bridge_generated.rs','src/bridge_generated.io.rs','flutter/lib/generated_bridge.dart','flutter/lib/generated_bridge.freezed.dart','flutter/macos/Runner/bridge_generated.h','flutter/ios/Runner/bridge_generated.h')
    foreach($relative in ($files | Sort-Object -Unique)){
        $source=Join-Path $ryadomRoot $relative
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){continue}
        $target=Join-Path $staging $relative
        New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    & tar.exe -a -cf (Join-Path $dist 'Ryadom-Sources-development.zip') -C $staging .
    if($LASTEXITCODE -ne 0){throw 'Архив исходников не создан'}
    if(-not $SkipWeb){
        $web=Join-Path $PSScriptRoot 'ui/build/web'
        if(-not(Test-Path -LiteralPath (Join-Path $web 'index.html'))){throw 'Нет веб-сборки'}
        $sourceOffer=Join-Path $web 'source'
        New-Item -ItemType Directory -Force $sourceOffer | Out-Null
        Copy-Item -LiteralPath (Join-Path $dist 'Ryadom-Sources-development.zip') -Destination $sourceOffer -Force
        & tar.exe -a -cf (Join-Path $dist 'Ryadom-Web-development.zip') -C $web .
        if($LASTEXITCODE -ne 0){throw 'Архив веб-клиента не создан'}
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README_RU.md'),(Join-Path $PSScriptRoot 'P2P_RECOVERY_RU.md'),(Join-Path $PSScriptRoot 'TEST_ON_TWO_PCS_RU.md'),(Join-Path $PSScriptRoot 'NETWORK_SECURITY_RU.md'),(Join-Path $PSScriptRoot 'verification.json'),(Join-Path $ryadomRoot 'LICENCE') -Destination $dist -Force
    $hashes=Get-ChildItem -LiteralPath $dist -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object Name | ForEach-Object {
        $hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
    [IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),$hashes,[Text.UTF8Encoding]::new($false))
}finally{Pop-Location}
