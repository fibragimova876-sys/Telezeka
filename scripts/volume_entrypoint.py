"""Initialize the mounted SQLite directory, then run both servers unprivileged."""
import os
import stat
import sys
from pathlib import Path

uid = gid = 10001
db = Path(os.environ.get("CHAT_DB", "/data/chat.db"))
if not db.is_absolute() or db.parent != Path("/data"):
    raise SystemExit("CHAT_DB must be inside /data")
if os.geteuid() == 0:
    directory = db.parent
    os.chown(directory, uid, gid)
    os.chmod(directory, 0o700)
    for path in (db, Path(str(db)+"-wal"), Path(str(db)+"-shm"), Path(str(db)+"-journal")):
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError:
            continue
        if not stat.S_ISREG(mode):
            raise SystemExit("Unexpected database file type")
        os.chown(path, uid, gid, follow_symlinks=False)
        os.chmod(path, 0o600)
    os.setgroups([])
    os.setgid(gid)
    os.setuid(uid)
os.umask(0o077)
if not os.access(db.parent, os.W_OK | os.X_OK):
    raise SystemExit("Database directory is not writable")
os.execv(sys.executable, [sys.executable, "/app/run_hybrid.py"])
