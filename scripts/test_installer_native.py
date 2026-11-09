"""Native installer regression test in an isolated Linux REAPER; never connects to Windows."""
from pathlib import Path
import importlib.util
import os
import subprocess
import time
import zipfile
from PIL import ImageGrab

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('runner',ROOT/'tests/run.py')
assert spec and spec.loader
runner=importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
expected=ROOT/'qa/installer-expected'; expected.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(ROOT/'dist/ReaSkiiPicker-0.1.1-alpha-install.zip') as archive:
    for name in archive.namelist():
        path=expected/name.removeprefix('ReaSkiiPicker/')
        path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(archive.read(name))
original_popen=subprocess.Popen
class CaptureBeforeTerminate(original_popen):
    def terminate(self):
        if isinstance(self.args,(list,tuple)) and str(self.args[0]).endswith('/reaper'):
            try: ImageGrab.grab(xdisplay=':187').save(ROOT/'qa/installer-native.png')
            except Exception as error: print('Diagnostic screenshot unavailable:',error)
        return super().terminate()
subprocess.Popen=CaptureBeforeTerminate
work=Path(os.environ['TMPDIR'])/('picker-installer-native-'+str(time.time_ns())); work.mkdir()
print('WORK',work,flush=True)
try:
    runner.native(work,Path.home()/'.hermes/cache/scratch/picker-audit','installer_native.lua')
finally:
    progress=work/'native.tsv.progress'
    if progress.exists(): print(progress.read_text(),flush=True)
