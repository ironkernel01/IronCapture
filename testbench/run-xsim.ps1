param(
    [Parameter(Mandatory)][string]$VivadoBin,
    [Parameter(Mandatory)][string]$RtlNet,
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference = 'Stop'
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$RtlNet = (Resolve-Path -LiteralPath $RtlNet).Path
$source = Split-Path -Parent $PSScriptRoot

function Resolve-Source([string]$File) {
    if ($File.StartsWith('ip/rtlnet_csi2_rx/')) { return Join-Path $source $File }
    if ($File.StartsWith('cores/rtlnet_common/')) { return Join-Path $RtlNet $File }
    throw "Unknown capture source $File"
}
function Get-RtlNetArguments([string]$File) {
    foreach ($line in Get-Content -LiteralPath (Resolve-Source $File)) {
        $entry = $line.Trim()
        if (!$entry -or $entry.StartsWith('#')) { continue }
        if ($entry -match '^-f\s+(.+)$') {
            Get-RtlNetArguments $Matches[1]
        } elseif ($entry -match '^\+incdir\+(.+)$') {
            '-i'
            Resolve-Source $Matches[1]
        } elseif ($entry -match '^\w') {
            Resolve-Source $entry
        } else {
            throw "Unsupported RTLNet source-list entry $entry"
        }
    }
}

function Invoke-XsimTool([string]$Tool, [string[]]$Arguments) {
    & (Join-Path $VivadoBin "$Tool.bat") @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

function Test-Snapshot([string]$Top, [string]$Name, [string[]]$RequiredPass) {
    Invoke-XsimTool xelab @($Top, '-s', $Name, '-log', "elaborate-$Name.log")
    Invoke-XsimTool xsim @($Name, '-runall', '-log', "simulate-$Name.log")
    $log = Get-Content -Raw -LiteralPath "simulate-$Name.log"
    foreach ($pass in $RequiredPass) {
        if (!$log.Contains($pass)) { throw "Missing simulation pass: $pass" }
    }
    if ($log -match '(?im)^\s*(fatal|error):') { throw "Simulator reported an error for $Name" }
}

$null = New-Item -ItemType Directory -Path $Output -Force
Push-Location -LiteralPath (Resolve-Path -LiteralPath $Output)
try {
    $writer = Join-Path $source 'hdl/ironcapture_writer.sv'
    Invoke-XsimTool xvlog @('-sv', $writer, (Join-Path $PSScriptRoot 'tb_ironcapture_writer.sv'),
                            '-log', 'compile-writer.log')
    Test-Snapshot tb_ironcapture_writer writer @('PASS IronCapture AXI32 packing',
        'PASS IronCapture AXI64 packing', 'PASS IronCapture AXI128 packing')
    $patternSources = @(Get-RtlNetArguments 'ip/rtlnet_csi2_rx/hdl/rtlnet_csi2_rx.f')
    $patternSources += $writer, (Join-Path $source 'hdl/ironcapture_control.sv'),
                       (Join-Path $source 'hdl/ironcapture_top.v'),
                       (Join-Path $PSScriptRoot 'tb_ironcapture_pattern.sv')
    Invoke-XsimTool xvlog (@('-sv') + $patternSources + @('-log', 'compile-pattern.log'))
    Test-Snapshot tb_ironcapture_pattern pattern720 @('PASS IronCapture AXI-Lite -> RTLNet static bars -> DDR 1843200 YUYV bytes')
    Test-Snapshot tb_ironcapture_pattern1080 pattern1080 @('PASS IronCapture AXI-Lite -> RTLNet static bars -> DDR 4147200 YUYV bytes')
} finally {
    Pop-Location
}
