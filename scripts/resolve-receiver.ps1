param([string]$RtlNet, [switch]$Offline)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$pin = Get-Content -Raw -LiteralPath (Join-Path $root 'receiver.lock.json') | ConvertFrom-Json
$shared = Join-Path (Split-Path $root) 'rtlnet/sources/RTLNet'
if (-not $RtlNet) {
    if ((Test-Path -LiteralPath $shared) -or
        (Test-Path -LiteralPath (Join-Path (Split-Path (Split-Path $root)) 'IRONFORGE.md'))) {
        $RtlNet = $shared
    } else {
        $RtlNet = Join-Path $root '.deps/RTLNet'
    }
}
if (-not (Test-Path -LiteralPath $RtlNet)) {
    if ($Offline) { throw 'Pinned RTLNet checkout is unavailable offline.' }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($RtlNet)))
    & git clone --no-checkout --config core.autocrlf=false $pin.repository $RtlNet
    if ($LASTEXITCODE) { throw 'Unable to acquire RTLNet.' }
    & git -C $RtlNet checkout --detach $pin.commit
    if ($LASTEXITCODE) { throw 'Unable to select the receiver revision.' }
}
$head = & git -C $RtlNet rev-parse HEAD
if ($LASTEXITCODE -or $head -ne $pin.commit) { throw 'RTLNet revision differs from receiver.lock.json.' }
$url = & git -C $RtlNet remote get-url origin
if ($LASTEXITCODE -or ($url -replace '^https://[^/@]+@github\.com/','https://github.com/') -ne $pin.repository) {
    throw 'RTLNet origin differs from receiver.lock.json.'
}
$changes = & git -C $RtlNet status --porcelain --untracked-files=no -- cores/rtlnet_common $pin.core
if ($LASTEXITCODE -or $changes) { throw 'The checked-out receiver or its shared primitives have local changes.' }
(Resolve-Path -LiteralPath $RtlNet).Path
