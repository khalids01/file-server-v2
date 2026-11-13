"""Own the native worker's process group, including on BEAM job death (stdin EOF)."""
import os
import signal
import subprocess
import sys
import threading

child = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, start_new_session=True)

def terminate():
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass

def owner_watch():
    while os.read(0, 1):
        pass
    terminate()
    child.wait()
    os._exit(1)

threading.Thread(target=owner_watch, daemon=True).start()
timer = threading.Timer(int(sys.argv[1]) / 1000, terminate)
timer.start()
try:
    output = child.stdout.read(65537)
    if len(output) > 65536:
        terminate()
        child.wait()
        sys.exit(1)
    status = child.wait()
    sys.stdout.buffer.write(output)
    sys.stdout.buffer.flush()
    sys.exit(status if status >= 0 else 124)
finally:
    timer.cancel()
    terminate()
    child.wait()
