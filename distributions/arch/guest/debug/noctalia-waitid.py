#!/usr/bin/env python3
"""Run the real noctalia binary and report how the child died.

Debug tool for the shell's unexplained SIGKILL restarts: the supervisor only
sees status 137 and the shell's own log ends mid-sentence, so waitid() is used
as the witness. It reports whether the child exited or was killed, the signal
name, and the siginfo fields (si_code / si_pid). Note that on this kernel a
SIGKILL reports CLD_KILLED with si_pid set to the *child's* pid, so the sender
stays unnamed; what the report does prove is which side of the namespace the
kill came from (a kernel OOM would bump the host's oom_kill counter, an
Android-side kill would appear in logcat).

Activate on a running instance (rootfs change, survives sessions until the
bundle is reinstalled):

    mv /usr/bin/noctalia /usr/bin/noctalia.real
    printf '#!/bin/bash\nexec python3 /usr/local/lib/arlinux/noctalia-waitid.py "$@"\n' > /usr/bin/noctalia
    chmod 755 /usr/bin/noctalia

Deaths then land in /tmp/noctalia-waitid.log and in the supervisor's log tail
(`desktop-diag.log`). Revert with `mv /usr/bin/noctalia.real /usr/bin/noctalia`.
"""
import os
import signal
import sys
import time

REAL = "/usr/bin/noctalia.real"
CODES = {-1: "SI_USER", -2: "SI_QUEUE", -6: "SI_TKILL", 0: "SI_ASYNCNL",
         128: "SI_KERNEL"}

pid = os.fork()
if pid == 0:
    os.execv(REAL, [REAL] + sys.argv[1:])
    os._exit(127)

started = time.time()
info = os.waitid(os.P_PID, pid, os.WEXITED)
killed = info.si_code == os.CLD_KILLED
kind = {os.CLD_EXITED: "exited", os.CLD_KILLED: "killed",
        os.CLD_DUMPED: "dumped"}.get(info.si_code, info.si_code)
sig = ""
if killed:
    try:
        sig = " signal=%s" % signal.Signals(info.si_status).name
    except ValueError:
        sig = " signal=%s" % info.si_status
report = ("[arlinux] noctalia pid %s died after %.0fs: %s status=%s%s "
          "si_code=%s(%s) si_pid=%s si_uid=%s"
          % (pid, time.time() - started, kind, info.si_status, sig,
             info.si_code, CODES.get(info.si_code, "?"),
             getattr(info, "si_pid", None), getattr(info, "si_uid", None)))
sys.stderr.write(report + "\n")
sys.stderr.flush()
try:
    with open("/tmp/noctalia-waitid.log", "a") as fh:
        fh.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S%z"), report))
except OSError:
    pass
sys.exit(info.si_status if not killed else 128 + info.si_status)
