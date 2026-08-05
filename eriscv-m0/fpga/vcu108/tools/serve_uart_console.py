#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Serve the local M0 Web Serial console and open it in the default browser."""

from __future__ import annotations

import http.server
import os
import subprocess
import threading
import webbrowser
from pathlib import Path


HOST = "127.0.0.1"
PORT = 8765
URL = f"http://{HOST}:{PORT}/uart_console.html"


def open_console() -> None:
    chrome = Path(os.environ.get("PROGRAMFILES", "")) / "Google" / "Chrome" / "Application" / "chrome.exe"
    if chrome.is_file():
        subprocess.Popen([str(chrome), URL])
    else:
        webbrowser.open(URL)


def main() -> None:
    directory = Path(__file__).resolve().parent
    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(*args, directory=directory, **kwargs)
    server = http.server.ThreadingHTTPServer((HOST, PORT), handler)
    print(f"eRISCV-M0 UART console: {URL}")
    print("Close this window to stop the local server.")
    threading.Timer(0.25, open_console).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
