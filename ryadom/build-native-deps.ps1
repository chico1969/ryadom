$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$vcpkgRoot=$env:VCPKG_ROOT
if(-not $vcpkgRoot){$vcpkgRoot=Join-Path $projectRoot '.tools/vcpkg'}
if(-not(Test-Path -LiteralPath (Join-Path $vcpkgRoot 'vcpkg.exe'))){throw 'Сначала подготовьте закреплённый vcpkg из toolchain.lock.json'}
$mappedDrive=$null
$buildRoot=$projectRoot
if($projectRoot.Contains(' ')){
    foreach($letter in @('R','S','T','U','V','W','X','Y','Z')){
        if(-not(Get-PSDrive -Name $letter -ErrorAction SilentlyContinue) -and -not(Test-Path "${letter}:\")){
            $mappedDrive="${letter}:"
            break
        }
    }
    if(-not $mappedDrive){throw 'Для FFmpeg нужен временный свободный диск SUBST: исходный путь содержит пробел'}
    & subst.exe $mappedDrive $projectRoot
    if($LASTEXITCODE -ne 0){throw 'Не удалось создать временный путь сборки без пробелов'}
    $buildRoot=$mappedDrive+'\'
}
try{
    if($vcpkgRoot.StartsWith($projectRoot+'\',[StringComparison]::OrdinalIgnoreCase)){
        $vcpkgRoot=Join-Path $buildRoot $vcpkgRoot.Substring($projectRoot.Length+1)
    }
    $env:VCPKG_DEFAULT_HOST_TRIPLET='x64-windows-static'
    $env:VCPKG_DISABLE_METRICS='1'
    Push-Location $buildRoot
    try{
        & (Join-Path $vcpkgRoot 'vcpkg.exe') install --triplet x64-windows-static "--vcpkg-root=$vcpkgRoot" "--x-install-root=$vcpkgRoot/installed"
        if($LASTEXITCODE -ne 0){throw 'Нативные библиотеки не собраны; см. журнал vcpkg'}
    }finally{Pop-Location}
}finally{
    if($mappedDrive){
        & subst.exe $mappedDrive /D
        if($LASTEXITCODE -ne 0){Write-Warning "Не удалось убрать временный диск $mappedDrive"}
    }
}
