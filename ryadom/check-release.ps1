$ErrorActionPreference='Stop'
$matrix=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'acceptance.json') -Raw | ConvertFrom-Json
$pending=@($matrix.required | Where-Object { $_.status -ne 'passed' -or -not $_.evidence })
if($pending.Count -gt 0){
    $names=($pending | ForEach-Object id) -join ', '
    throw "Выпуск не готов: $names. Нужны результаты испытаний, а не только наличие кода."
}
foreach($case in $matrix.required){
    if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $case.evidence))){throw "Нет протокола испытаний: $($case.id)"}
}
Write-Output 'Все обязательные проверки имеют результаты.'
