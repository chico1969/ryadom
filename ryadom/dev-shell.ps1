$ErrorActionPreference = 'Stop'
$ryadomRoot = Split-Path -Parent $PSScriptRoot
$env:RUSTUP_HOME = Join-Path $ryadomRoot '.tools/rustup'
$env:CARGO_HOME = Join-Path $ryadomRoot '.tools/cargo'
$env:PUB_CACHE = Join-Path $ryadomRoot '.tools/pub-cache'
$env:npm_config_cache = Join-Path $ryadomRoot '.tools/npm-cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
$env:GIT_CONFIG_COUNT = '2'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $ryadomRoot.Replace('\','/')
$env:GIT_CONFIG_KEY_1 = 'safe.directory'
$env:GIT_CONFIG_VALUE_1 = (Join-Path $ryadomRoot '.tools/flutter').Replace('\','/')
$env:PATH = (Join-Path $env:CARGO_HOME 'bin') + ';' + (Join-Path $ryadomRoot '.tools/flutter/bin') + ';' + $env:PATH
if(Test-Path (Join-Path $ryadomRoot '.tools/llvm/bin/libclang.dll')){
    $env:LIBCLANG_PATH=Join-Path $ryadomRoot '.tools/llvm/bin'
    $env:PATH=$env:LIBCLANG_PATH+';'+$env:PATH
}
if(Test-Path (Join-Path $ryadomRoot '.tools/python/python.exe')){
    $env:PATH=(Join-Path $ryadomRoot '.tools/python')+';'+(Join-Path $ryadomRoot '.tools/python/Scripts')+';'+$env:PATH
}
if(Test-Path (Join-Path $ryadomRoot '.tools/vcpkg/vcpkg.exe')){
    $env:VCPKG_ROOT=Join-Path $ryadomRoot '.tools/vcpkg'
    $env:VCPKG_DEFAULT_HOST_TRIPLET='x64-windows-static'
    $env:VCPKG_DEFAULT_TRIPLET='x64-windows-static'
    $env:VCPKG_DISABLE_METRICS='1'
}
if(Test-Path (Join-Path $ryadomRoot '.tools/npm/package/bin/npm-cli.js')){
    $toolBin=Join-Path $ryadomRoot '.tools/tool-bin'
    New-Item -ItemType Directory -Force $toolBin | Out-Null
    [IO.File]::WriteAllText((Join-Path $toolBin 'npm.cmd'),
        "@echo off`r`nnode `"%~dp0..\npm\package\bin\npm-cli.js`" %*`r`n",[Text.Encoding]::ASCII)
    $env:PATH=$toolBin+';'+$env:PATH
}
