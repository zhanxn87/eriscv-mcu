# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

param(
  [ValidateSet("gui", "synth", "impl")]
  [string]$Flow = "impl"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TclScript = Join-Path $ScriptDir "scripts\${Flow}_vcu108.tcl"
Set-Location $ScriptDir
$VivadoCmd = (Get-Command vivado -ErrorAction SilentlyContinue).Source
if (-not $VivadoCmd -and $env:XILINX_VIVADO) {
  $Candidate = Join-Path $env:XILINX_VIVADO "bin\vivado.bat"
  if (Test-Path $Candidate) { $VivadoCmd = $Candidate }
}
if (-not $VivadoCmd) {
  $VivadoCmd = Get-ChildItem -Path `
      "C:\Xilinx\Vivado\*\bin\vivado.bat", `
      "D:\Xilinx\Vivado\*\bin\vivado.bat", `
      "C:\AMDDesignTools\*\Vivado\bin\vivado.bat", `
      "D:\AMDDesignTools\*\Vivado\bin\vivado.bat" `
      -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $VivadoCmd) { throw "Vivado not found. Add it to PATH or set XILINX_VIVADO." }

# Vivado's generated runme.bat invokes `cscript` without an extension.  A
# PowerShell process entered from WSL can inherit an incomplete PATHEXT (for
# example, only .CPL), which prevents the child synthesis/implementation run
# from resolving cscript.exe even though it is present in System32.
if ($env:SystemRoot) {
  $env:PATH = (Join-Path $env:SystemRoot "System32") + ";" + $env:PATH
}
$env:PATHEXT = ".COM;.EXE;.BAT;.CMD"

& $VivadoCmd -mode $(if ($Flow -eq "gui") { "gui" } else { "batch" }) -source $TclScript
