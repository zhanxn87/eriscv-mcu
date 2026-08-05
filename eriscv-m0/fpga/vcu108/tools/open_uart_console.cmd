@echo off
setlocal
cd /d "%~dp0"
py -3 serve_uart_console.py
if errorlevel 1 (
  echo Python 3 is required to host the local UART console.
  pause
)
