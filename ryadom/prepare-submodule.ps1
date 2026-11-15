$ErrorActionPreference='Stop'
$ryadomRoot=Split-Path -Parent $PSScriptRoot
$dependency=Join-Path $ryadomRoot 'libs/hbb_common'
$patch=Join-Path $PSScriptRoot 'patches/hbb_common.patch'
if(-not(Test-Path -LiteralPath (Join-Path $dependency '.git'))){
    if((Get-Content (Join-Path $dependency 'Cargo.toml') -Raw).Contains('direct-only = []')){return}
    throw 'В архиве отсутствует подготовленная зависимость hbb_common'
}
& git -C $dependency apply --reverse --check $patch 2>$null
if($LASTEXITCODE -eq 0){return}
& git -C $dependency apply --check $patch
if($LASTEXITCODE -ne 0){throw 'Исходники hbb_common не совпадают с закреплённой версией'}
& git -C $dependency apply $patch
if($LASTEXITCODE -ne 0){throw 'Не удалось применить изменения прямого транспорта'}
