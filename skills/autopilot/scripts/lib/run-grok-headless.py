#!/usr/bin/env python3
"""Run grok with a private controlling pty.

Positional grok starts an interactive session and opens /dev/tty. Backgrounded
under bash job control that is SIGTTOU-stopped; setsid without a pty fails with
ENXIO. This wrapper gives grok a slave pty as stdin/controlling tty, keeps the
inherited stdout/stderr pipes, and copies pty bytes onto stdout so TUI-routed
JSON still reaches the Autopilot event fifo.
"""

from __future__ import annotations

import os
import select
import signal
import sys

signal.signal(signal.SIGTTOU, signal.SIG_IGN)
signal.signal(signal.SIGTTIN, signal.SIG_IGN)

if len(sys.argv) < 2:
    sys.stderr.write("usage: run-grok-headless.py <grok> [args...]\n")
    sys.exit(2)

grok_argv = sys.argv[1:]
out_fd = os.dup(1)
err_fd = os.dup(2)

pid, master_fd = os.forkpty()
if pid == 0:
    os.dup2(out_fd, 1)
    os.dup2(err_fd, 2)
    os.close(out_fd)
    os.close(err_fd)
    os.execvp(grok_argv[0], grok_argv)
    os._exit(127)

while True:
    try:
        waited, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        sys.exit(1)
    if waited == pid:
        while True:
            ready, _, _ = select.select([master_fd], [], [], 0)
            if master_fd not in ready:
                break
            try:
                chunk = os.read(master_fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            os.write(out_fd, chunk)
        if os.WIFEXITED(status):
            sys.exit(os.WEXITSTATUS(status))
        if os.WIFSIGNALED(status):
            sys.exit(128 + os.WTERMSIG(status))
        sys.exit(1)
    ready, _, _ = select.select([master_fd], [], [], 0.2)
    if master_fd in ready:
        try:
            chunk = os.read(master_fd, 65536)
        except OSError:
            chunk = b""
        if chunk:
            os.write(out_fd, chunk)
