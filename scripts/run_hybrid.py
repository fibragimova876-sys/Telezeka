"""Run compatibility backend on loopback and public Rust core; terminate both on failure."""
import os, signal, subprocess, sys, time, urllib.request
from pathlib import Path
root=Path(__file__).resolve().parent
server=root/'server.py' if (root/'server.py').exists() else root.parent/'server/server.py'
env=dict(os.environ,CHAT_HOST='127.0.0.1',CHAT_PORT='8081')
children=[]
def stop(*args):
    for child in children:
        if child.poll() is None: child.terminate()
    for child in children:
        try: child.wait(timeout=5)
        except subprocess.TimeoutExpired: child.kill(); child.wait()
    sys.exit(0 if args else 1)
signal.signal(signal.SIGTERM,stop)
signal.signal(signal.SIGINT,stop)
try:
    children.append(subprocess.Popen([sys.executable,str(server)],env=env))
    for _ in range(100):
        if children[0].poll() is not None: raise RuntimeError('Backend exited')
        try:
            with urllib.request.urlopen('http://127.0.0.1:8081/health',timeout=1) as r:
                if r.status==200: break
        except OSError: time.sleep(.2)
    else: raise RuntimeError('Backend health check timed out')
    children.append(subprocess.Popen([os.environ.get('TELEZEKA_RUST_BIN','/usr/local/bin/telezeka-core')]))
    while all(c.poll() is None for c in children): time.sleep(.5)
finally:
    stop()
