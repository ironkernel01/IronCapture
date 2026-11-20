param([string]$RtlNet, [switch]$Offline)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$pin = Get-Content -Raw -LiteralPath (Join-Path $root 'rtlnet-common.lock.json') | ConvertFrom-Json
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
$tree = & git -C $RtlNet rev-parse "HEAD:$($pin.core)"
if ($LASTEXITCODE -or $tree -ne $pin.tree) { throw 'RTLNet common primitives differ from the IronCapture pin.' }
$url = & git -C $RtlNet remote get-url origin
if ($LASTEXITCODE -or ($url -replace '^https://[^/@]+@github\.com/','https://github.com/') -ne $pin.repository) {
    throw 'RTLNet origin differs from rtlnet-common.lock.json.'
}
$changes = & git -C $RtlNet status --porcelain -- $pin.core
if ($LASTEXITCODE -or $changes) { throw 'The common primitives have local changes.' }
(Resolve-Path -LiteralPath $RtlNet).Path
