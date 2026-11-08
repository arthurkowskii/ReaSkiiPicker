"""Isolated development tests. Requires lupa, Pillow, python-xlib and Xvfb."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import time
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
TOOLS=Path.home()/'.local/share/reaskii-native-picker'

def units(work, source):
    staging=work/'source'; staging.mkdir(exist_ok=True)
    for name in ('categories.json','plugins.json'):
        shutil.copy2(source/name,staging/name)
    for name in ('core.lua','store.lua'):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().arg=lua.table_from({1:str(ROOT),2:str(work)})
        lua.execute((ROOT/'tests'/name).read_text())
    lua=LuaRuntime()
    for path in ROOT.rglob('*.lua'):
        lua.execute('assert(loadfile(...))',str(path))
    print('SYNTAX all Lua files pass',flush=True)

def native(work, source, suite='native.lua'):
    cfg=work/'config'; cfg.mkdir(exist_ok=True)
    (cfg/'UserPlugins').mkdir(exist_ok=True)
    shutil.copy2(TOOLS/'config/UserPlugins/reaper_imgui-x86_64.so',cfg/'UserPlugins')
    shim=cfg/'Scripts/ReaTeam Extensions/API'; shim.mkdir(parents=True)
    shutil.copy2(TOOLS/'imgui.lua',shim/'imgui.lua')
    picker=cfg/'PluginPicker'; picker.mkdir()
    for name in ('categories.json','plugins.json'): shutil.copy2(source/name,picker/name)
    effects=TOOLS/'reaper_linux_x86_64/REAPER/InstallData/Effects'
    assert effects.exists(),effects
    shutil.copytree(effects,cfg/'Effects',dirs_exist_ok=True)
    (cfg/'reaper.ini').write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\n')
    result=work/'native.tsv'
    wrapper=work/'native-run.lua'
    wrapper.write_text('PICKER_ROOT='+json.dumps(str(ROOT))+'\nPICKER_SOURCE='+json.dumps(str(source))+'\nPICKER_RESULT='+json.dumps(str(result))+'\ndofile('+json.dumps(str(ROOT/'tests'/suite))+')\n')
    display=':187'
    env={**os.environ,'DISPLAY':display}
    xvfb=subprocess.Popen(['Xvfb',display,'-screen','0','1400x1000x24','-nolisten','tcp'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    proc=None
    try:
        time.sleep(1)
        with (work/'reaper.log').open('w') as log:
            proc=subprocess.Popen([str(TOOLS/'reaper_linux_x86_64/REAPER/reaper'),'-newinst','-nosplash','-cfgfile',str(cfg/'reaper.ini'),str(wrapper)],env=env,stdout=log,stderr=log)
            deadline=time.monotonic()+35
            while time.monotonic()<deadline:
                if result.exists():
                    text=result.read_text(); print(text,flush=True)
                    assert 'ERROR\t' not in text,text
                    lines=text.splitlines(); done=[x for x in lines if x.startswith('DONE\t')]
                    assert len(done)==1 and int(done[0].split('\t')[1])==sum(x.startswith('PASS\t') for x in lines)
                    return
                if proc.poll() is not None: raise RuntimeError((work/'reaper.log').read_text())
                time.sleep(.2)
            raise TimeoutError(str(work))
    finally:
        for process in (proc,xvfb):
            if process:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--native',action='store_true'); parser.add_argument('--toggle',action='store_true'); args=parser.parse_args()
    work=Path(os.environ['TMPDIR'])/('picker-tests-'+str(time.time_ns())); work.mkdir()
    source=Path.home()/'.hermes/cache/scratch/picker-audit'
    print('WORK',work,flush=True)
    if args.toggle: native(work,source,'toggle.lua')
    elif args.native: native(work,source)
    else: units(work,source)
