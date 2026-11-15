param(
    [Parameter(Mandatory)][ValidateSet('stage-inner','repack','verify-release')][string]$Stage,
    [Parameter(Mandatory)][string]$Version,
    [string]$CertificateThumbprint
)
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
   @($Version.Split('.') | Where-Object {[int64]$_ -gt 65535}).Count){throw 'Expected four 16-bit version numbers'}
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work=Join-Path $projectRoot '.tools/signpath'
$runtime=Join-Path $projectRoot 'flutter/build/windows/x64/runner/Release'
$ownFiles=@('Ryadom.exe','librustdesk.dll')
function Assert-Metadata([string]$File,[string]$OriginalName){
    $info=(Get-Item -LiteralPath $File).VersionInfo
    if($info.ProductName -cne 'Рядом' -or $info.ProductVersion -cne $Version -or
       $info.FileVersion -cne $Version -or $info.OriginalFilename -cne $OriginalName){
        throw "Unexpected signing metadata: $File"
    }
}
function Assert-Signature([string]$File){
    if($CertificateThumbprint -notmatch '^[a-fA-F0-9]{40}$'){throw 'Expected the approved production certificate SHA-1 thumbprint'}
    $signature=Get-AuthenticodeSignature -LiteralPath $File
    if($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate -or
       $signature.SignerCertificate.Thumbprint -ine $CertificateThumbprint){
        throw "Trusted timestamped production signature not verified: $File"
    }
}
New-Item -ItemType Directory -Force -Path $work | Out-Null
if($Stage -eq 'stage-inner'){
    $output=Join-Path $work 'unsigned-inner'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    foreach($name in $ownFiles){
        $source=Join-Path $runtime $name
        Assert-Metadata $source $name
        Copy-Item -LiteralPath $source -Destination (Join-Path $output $name) -Force
    }
    $manifest=@(Get-ChildItem -LiteralPath $runtime -File -Recurse | ForEach-Object {
        [pscustomobject]@{path=[IO.Path]::GetRelativePath($runtime,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'runtime-before.json') -Encoding utf8
    Write-Output 'Inner signing inputs staged; no signature claimed.'
    return
}
if($Stage -eq 'repack'){
    foreach($name in $ownFiles){
        $signed=Join-Path $work "signed-inner/$name"
        Assert-Metadata $signed $name
        Assert-Signature $signed
    }
    $manifest=Get-Content -LiteralPath (Join-Path $work 'runtime-before.json') -Raw | ConvertFrom-Json
    foreach($entry in $manifest){
        $source=Join-Path $runtime $entry.path
        if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256){
            throw "Runtime changed after staging: $($entry.path)"
        }
    }
    foreach($name in $ownFiles){
        Copy-Item -LiteralPath (Join-Path $work "signed-inner/$name") -Destination (Join-Path $runtime $name) -Force
    }
    if($env:RYADOM_SIGNING_VERSION -cne $Version -or $env:RYADOM_BUILD -cne '1'){
        throw 'Signing build environment is not configured'
    }
    $packer=Join-Path $projectRoot 'libs/portable'
    Push-Location $packer
    try{
        & python ./generate.py -f $runtime -o . -e (Join-Path $runtime 'Ryadom.exe')
        if($LASTEXITCODE -ne 0){throw 'Packaging signed runtime failed'}
    }finally{Pop-Location}
    $outer=Join-Path $projectRoot 'target/release/rustdesk-portable-packer.exe'
    Assert-Metadata $outer 'Ryadom.exe'
    $output=Join-Path $work 'unsigned-outer'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    foreach($name in @('Ryadom.exe','Ryadom-Setup.exe')){
        Copy-Item -LiteralPath $outer -Destination (Join-Path $output $name) -Force
    }
    Write-Output 'Verified signed inner files packaged; outer executables await signing.'
    return
}
$signedOutput=Join-Path $work 'signed-outer'
$release=Join-Path $projectRoot 'dist/signpath'
foreach($name in @('Ryadom.exe','Ryadom-Setup.exe')){
    Assert-Metadata (Join-Path $signedOutput $name) 'Ryadom.exe'
    Assert-Signature (Join-Path $signedOutput $name)
}
New-Item -ItemType Directory -Force -Path $release | Out-Null
foreach($name in @('Ryadom.exe','Ryadom-Setup.exe')){
    Copy-Item -LiteralPath (Join-Path $signedOutput $name) -Destination (Join-Path $release $name) -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'dist/development/Ryadom-Sources-development.zip'),
    (Join-Path $projectRoot 'LICENCE'),(Join-Path $projectRoot 'CODE_SIGNING.md'),
    (Join-Path $projectRoot 'PRIVACY.md') -Destination $release -Force
$sums=foreach($file in (Get-ChildItem -LiteralPath $release -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object Name)){
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($file.Name)"
}
[IO.File]::WriteAllLines((Join-Path $release 'SHA256SUMS.txt'),$sums,[Text.UTF8Encoding]::new($false))
Write-Output 'Production signatures, timestamps and expected certificate verified; ready for maintainer review.'
