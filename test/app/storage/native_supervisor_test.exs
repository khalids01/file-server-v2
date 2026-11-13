defmodule App.Storage.NativeSupervisorTest do
  use ExUnit.Case, async: true

  test "native child is killed and reaped on deadline and owner EOF" do
    supervisor = Path.expand("priv/native_supervisor.py")

    script = """
    import os, subprocess, sys, tempfile, time
    supervisor=sys.argv[1]
    with tempfile.TemporaryDirectory(prefix='serve-native-test-') as root:
      for mode in ('timeout','owner_exit'):
        pidfile=os.path.join(root,mode)
        code='import os,time;open('+repr(pidfile)+',"w").write(str(os.getpid()));time.sleep(60)'
        worker=subprocess.Popen([sys.executable,supervisor,'400' if mode=='timeout' else '60000',sys.executable,'-c',code],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
        deadline=time.monotonic()+5
        while not os.path.exists(pidfile):
          assert time.monotonic()<deadline
          time.sleep(.01)
        pid=int(open(pidfile).read())
        if mode=='owner_exit': worker.stdin.close()
        assert worker.wait(timeout=5)!=0
        try: os.kill(pid,0)
        except ProcessLookupError: pass
        else: raise AssertionError('native child survived '+mode)
    print('deadline and owner EOF: children reaped')
    """

    assert {"deadline and owner EOF: children reaped\n", 0} =
             System.cmd("python3", ["-c", script, supervisor], stderr_to_stdout: true)
  end
end
