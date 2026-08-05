# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

param(
  [Parameter(Mandatory = $true)]
  [string]$Port,

  [Parameter(Mandatory = $true)]
  [string]$Image,

  [ValidateRange(1200, 1000000)]
  [int]$BaudRate = 115200,

  [ValidateRange(0, 10000)]
  [int]$ReceiveMilliseconds = 500,

  [switch]$DryRun
)

$forward = @{
  Mode = "Boot"
  Port = $Port
  Image = $Image
  BaudRate = $BaudRate
  ReceiveMilliseconds = $ReceiveMilliseconds
}
if ($DryRun) {
  $forward.DryRun = $true
}

& (Join-Path $PSScriptRoot "m0_uart.ps1") @forward
exit $LASTEXITCODE
