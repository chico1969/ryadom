param([switch]$Restore)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$app=Join-Path $projectRoot 'flutter'
if($Restore){
    $logs=Join-Path $PSScriptRoot 'build-logs'
    New-Item -ItemType Directory -Force $logs | Out-Null
    $log=Join-Path $logs 'flutter-pub.log'
    Push-Location $app
    try{
        & flutter pub get --enforce-lockfile *> $log
        if($LASTEXITCODE -ne 0){
            $output=Get-Content -Raw -LiteralPath $log
            if(-not($output.Contains('Got dependencies!') -and $output.Contains('Building with plugins requires symlink support.'))){
                throw "Не удалось восстановить закреплённые Flutter-пакеты: $log"
            }
        }
    }finally{Pop-Location}
}
$metadata=Join-Path $app '.flutter-plugins-dependencies'
if(-not(Test-Path -LiteralPath $metadata)){throw 'Сначала выполните flutter pub get --enforce-lockfile в flutter'}
$plugins=(Get-Content -Raw -LiteralPath $metadata | ConvertFrom-Json).plugins
foreach($platform in @('windows','linux')){
    $links=Join-Path $app "$platform/flutter/ephemeral/.plugin_symlinks"
    New-Item -ItemType Directory -Force $links | Out-Null
    foreach($plugin in $plugins.$platform){
        $link=Join-Path $links $plugin.name
        if(-not(Test-Path -LiteralPath $link)){
            if(-not(Test-Path -LiteralPath $plugin.path -PathType Container)){throw "Отсутствует пакет $($plugin.name)"}
            New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null
        }
    }
}
