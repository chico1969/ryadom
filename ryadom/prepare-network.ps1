$ErrorActionPreference='Stop'
$ryadomRoot=Split-Path -Parent $PSScriptRoot
$turnFile=Join-Path $ryadomRoot '.tools/turn.local.json'
$env:RYADOM_TURN_CONFIG=''
if(-not(Test-Path -LiteralPath $turnFile)){return}
$raw=Get-Content -LiteralPath $turnFile -Raw
if($raw.Length -gt 16384){throw 'Конфигурация TURN слишком велика'}
$servers=ConvertFrom-Json -InputObject $raw -NoEnumerate
if($servers -isnot [array] -or $servers.Count -gt 8){throw 'Ожидается список серверов TURN'}
foreach($server in $servers){
    $unknown=@($server.PSObject.Properties.Name | Where-Object {$_ -notin 'urls','username','credential'})
    if($unknown.Count -or $server.urls -isnot [array] -or $server.urls.Count -eq 0 -or $server.urls.Count -gt 8 -or
        $server.username -isnot [string] -or $server.username.Length -notin 1..256 -or
        $server.credential -isnot [string] -or $server.credential.Length -notin 1..1024){
        throw 'Нужны только urls, username и credential; API-ключи здесь не используются'
    }
    foreach($url in $server.urls){
        if($url -isnot [string] -or $url.Length -gt 1024 -or $url -notmatch '^turns?:[^\s/?#@]+(?:\?transport=(?:udp|tcp))?$'){
            throw 'Некорректный адрес TURN'
        }
    }
}
Write-Host 'Локальные TURN-данные оставлены для испытаний. Стандартная сборка их не включает; семейный режим выбирается отдельно.'
