# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

<#
.SYNOPSIS
  eRISCV-M0 VCU108 UART boot loader and interactive serial terminal.

.DESCRIPTION
  Uses the VCU108 CP2105 Standard UART (COM4 in the recorded board session).
  Boot mode sends the private IMEM loader protocol. Terminal mode is a raw
  runtime UART console: received bytes are printed immediately and typed keys
  are sent to the FPGA; Enter transmits carriage return (0x0d).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("Boot", "Terminal", "BootTerminal")]
  [string]$Mode,

  [Parameter(Mandatory = $true)]
  [string]$Port,

  [string]$Image,

  [ValidateRange(1200, 1000000)]
  [int]$BaudRate = 115200,

  [ValidateRange(0, 10000)]
  [int]$ReceiveMilliseconds = 500,

  [ValidateRange(0, 86400)]
  [int]$TerminalSeconds = 0,

  [string]$LogPath,

  [switch]$NoInput,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OPC_SET_ADDR = [byte]0x01
$OPC_WRITE32 = [byte]0x02
$OPC_HOLD = [byte]0x03
$OPC_RELEASE = [byte]0x04
$OPC_AUTO_INC = [byte]0x05
$OPC_RESET_ADDR = [byte]0x06

function Add-UInt32LE {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.Generic.List[byte]]$Bytes,

    [Parameter(Mandatory = $true)]
    [uint32]$Value
  )

  foreach ($shift in @(0, 8, 16, 24)) {
    [void]$Bytes.Add([byte](($Value -shr $shift) -band 0xff))
  }
}

function Get-BootTransaction {
  param(
    [Parameter(Mandatory = $true)]
    [string]$MemImage
  )

  if (-not (Test-Path -LiteralPath $MemImage -PathType Leaf)) {
    throw "Instruction image not found: $MemImage"
  }

  $bytes = [System.Collections.Generic.List[byte]]::new()
  [void]$bytes.Add($OPC_HOLD)
  [void]$bytes.Add($OPC_RESET_ADDR)
  [void]$bytes.Add($OPC_AUTO_INC)
  [void]$bytes.Add([byte]0x01)

  [uint32]$index = 0
  [uint32]$nextIndex = 0
  [int]$wordCount = 0
  foreach ($rawLine in Get-Content -LiteralPath $MemImage) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
      continue
    }
    if ($line.StartsWith("@")) {
      $index = [Convert]::ToUInt32($line.Substring(1), 16)
      continue
    }

    [uint32]$word = [Convert]::ToUInt32($line, 16)
    if ($index -ne $nextIndex) {
      [void]$bytes.Add($OPC_SET_ADDR)
      Add-UInt32LE -Bytes $bytes -Value $index
    }
    [void]$bytes.Add($OPC_WRITE32)
    Add-UInt32LE -Bytes $bytes -Value $word
    $nextIndex = $index + 1
    $index = $nextIndex
    $wordCount++
  }

  [void]$bytes.Add($OPC_RELEASE)
  return [PSCustomObject]@{
    Bytes = $bytes.ToArray()
    WordCount = $wordCount
  }
}

function New-UartPort {
  $serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    $BaudRate,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
  )
  $serial.Handshake = [System.IO.Ports.Handshake]::None
  $serial.WriteTimeout = 10000
  return $serial
}

function Receive-UartText {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.Ports.SerialPort]$Serial,

    [System.IO.StreamWriter]$LogWriter
  )

  $text = $Serial.ReadExisting()
  if ($text.Length -gt 0) {
    [Console]::Out.Write($text)
    if ($null -ne $LogWriter) {
      $LogWriter.Write($text)
      $LogWriter.Flush()
    }
  }
}

function Send-TerminalKey {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.Ports.SerialPort]$Serial,

    [Parameter(Mandatory = $true)]
    [ConsoleKeyInfo]$Key
  )

  if ($Key.Key -eq [ConsoleKey]::Enter) {
    $serial.Write([byte[]]@(0x0d), 0, 1)
    return
  }
  if ($Key.Key -eq [ConsoleKey]::Backspace) {
    $serial.Write([byte[]]@(0x08), 0, 1)
    return
  }
  if ($Key.KeyChar -ne [char]0) {
    $data = [System.Text.Encoding]::ASCII.GetBytes([string]$Key.KeyChar)
    $serial.Write($data, 0, $data.Length)
  }
}

if (($Mode -eq "Boot" -or $Mode -eq "BootTerminal") -and [string]::IsNullOrWhiteSpace($Image)) {
  throw "-Image is required for Mode Boot or BootTerminal."
}
if ($DryRun -and $Mode -ne "Boot") {
  throw "-DryRun is only valid with Mode Boot."
}

$bootTransaction = $null
if ($Mode -eq "Boot" -or $Mode -eq "BootTerminal") {
  $bootTransaction = Get-BootTransaction -MemImage $Image
  $wireTimeMs = [Math]::Ceiling(($bootTransaction.Bytes.Length * 10.0 * 1000.0) / $BaudRate)
  Write-Host "M0 UART boot: $($bootTransaction.WordCount) words, $($bootTransaction.Bytes.Length) bytes, $BaudRate baud"
  if ($DryRun) {
    Write-Host "Dry run: no bytes sent."
    exit 0
  }
}

$serial = New-UartPort
$logWriter = $null
try {
  if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $logFullPath = [System.IO.Path]::GetFullPath($LogPath)
    $logDirectory = [System.IO.Path]::GetDirectoryName($logFullPath)
    if (-not [string]::IsNullOrEmpty($logDirectory)) {
      [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    }
    $logWriter = [System.IO.StreamWriter]::new($logFullPath, $false, [System.Text.UTF8Encoding]::new($false))
    Write-Host "UART log: $logFullPath"
  }

  $serial.Open()

  if ($null -ne $bootTransaction) {
    $serial.Write($bootTransaction.Bytes, 0, $bootTransaction.Bytes.Length)
    Start-Sleep -Milliseconds $wireTimeMs
    Write-Host "M0 UART boot: transfer complete; instruction fetch released."
  }

  if ($Mode -eq "Boot") {
    if ($ReceiveMilliseconds -gt 0) {
      Start-Sleep -Milliseconds $ReceiveMilliseconds
      $received = $serial.ReadExisting()
      if ($received.Length -gt 0) {
        Write-Host "M0 UART runtime output:"
        [Console]::Out.WriteLine($received)
      } else {
        Write-Host "M0 UART runtime output: <none within $ReceiveMilliseconds ms>"
      }
    }
    exit 0
  }

  if ($TerminalSeconds -gt 0) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TerminalSeconds)
    Write-Host "M0 UART terminal: $Port at $BaudRate baud for $TerminalSeconds second(s)."
  } else {
    $deadline = $null
    Write-Host "M0 UART terminal: $Port at $BaudRate baud. Press Ctrl+C to exit."
  }
  if (-not $NoInput) {
    Write-Host "Typed keys are sent immediately; Enter sends CR (0x0d)."
  }

  while (($null -eq $deadline) -or ([DateTime]::UtcNow -lt $deadline)) {
    Receive-UartText -Serial $serial -LogWriter $logWriter
    if (-not $NoInput -and [Console]::KeyAvailable) {
      $key = [Console]::ReadKey($true)
      Send-TerminalKey -Serial $serial -Key $key
    }
    Start-Sleep -Milliseconds 5
  }
  Receive-UartText -Serial $serial -LogWriter $logWriter
} finally {
  if ($null -ne $logWriter) {
    $logWriter.Dispose()
  }
  if ($serial.IsOpen) {
    $serial.Close()
  }
  $serial.Dispose()
}
