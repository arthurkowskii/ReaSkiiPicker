"""Exercise the real generated installer against isolated files, with only REAPER APIs simulated."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from lupa.lua54 import LuaRuntime, LuaError

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('build_installer',ROOT/'scripts/build_installer.py')
assert spec and spec.loader
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'])
        self.base=Path(self.temp.name); self.resource=self.base/'profile arthu é'/ 'REAPER'
        self.resource.mkdir(parents=True)
        self.built=module.build(ROOT,'v0.1.1-alpha',self.base/'dist')
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.messages=[]; self.actions=[]; self.queue=[]
        def mkdir(path,flags): Path(path).mkdir(parents=True,exist_ok=True); return 1
        def register(add,section,path,commit):
            self.actions.append((add,section,path,commit)); return 1234
        self.lua.globals()['reaper']=self.lua.table_from({
            'GetResourcePath':lambda:str(self.resource),'RecursiveCreateDirectory':mkdir,
            'ImGui_GetBuiltinPath':lambda:str(self.resource/'shim'),
            'GetExtState':lambda *a:'','SetExtState':lambda *a:None,
            'time_precise':lambda:0,'genGuid':lambda:'{INSTALL-TEST-1}',
            'AddRemoveReaScript':register,'Main_OnCommand':lambda *a:None,
            'MB':lambda text,title,kind:(self.messages.append(text) or 7),
            'defer':lambda callback:self.queue.append(callback),
        })
        self.lua.execute("package.preload['imgui']=function() return function() return {} end end")
    def tearDown(self): self.temp.cleanup()
    def run_installer(self):
        self.lua.execute(Path(self.built['installer']).read_text())
        while self.queue: self.queue.pop(0)()
    def test_reproduces_flat_entry_point_failure(self):
        bad=self.resource/'Scripts/ReaSkii_Picker.lua'; bad.parent.mkdir()
        bad.write_bytes(module.runtime.git(ROOT,'show','v0.1.1-alpha:ReaSkii_Picker.lua'))
        self.lua.execute("reaper.set_action_options=function() end; reaper.atexit=function() end; reaper.get_action_context=function() return nil,nil,0,1 end")
        with self.assertRaisesRegex(LuaError,'src/ui.lua'):
            self.lua.execute('dofile(...)',str(bad))
    def test_installs_exact_runtime_and_registers_entry(self):
        data=self.resource/'ReaSkiiPicker/library.json'; data.parent.mkdir(); data.write_text('user-data-preserved')
        self.run_installer()
        for name,value in self.built['payload'].items():
            self.assertEqual((self.resource/'Scripts/ReaSkiiPicker'/name).read_bytes(),value)
        self.assertEqual(data.read_text(),'user-data-preserved')
        self.assertTrue(self.actions[0][2].endswith('/Scripts/ReaSkiiPicker/ReaSkii_Picker.lua'))
        self.assertTrue(any('Installation terminee' in m for m in self.messages),self.messages)
    def test_repairs_flat_entry_without_changing_shortcut_id(self):
        bad=self.resource/'Scripts/ReaSkii_Picker.lua'; bad.parent.mkdir()
        original=self.built['payload']['ReaSkii_Picker.lua']; bad.write_bytes(original)
        self.run_installer()
        self.assertIn('Main_OnCommand',bad.read_text())
        self.assertIn('/Scripts/ReaSkiiPicker/ReaSkii_Picker.lua',bad.read_text())
        self.assertTrue(any(p.read_bytes()==original for p in (self.resource/'ReaSkiiPicker-backups').rglob('*.lua')))
    def test_missing_dependency_does_not_install_anything(self):
        self.lua.execute("reaper.ImGui_GetBuiltinPath=nil")
        self.run_installer()
        self.assertFalse((self.resource/'Scripts/ReaSkiiPicker').exists())
        self.assertEqual(self.actions,[])
        self.assertTrue(any('ReaImGui' in m for m in self.messages))
    def test_flat_entry_with_windows_line_endings_is_repaired(self):
        bad=self.resource/'Scripts/ReaSkii_Picker.lua'; bad.parent.mkdir()
        bad.write_bytes(b'\xef\xbb\xbf'+self.built['payload']['ReaSkii_Picker.lua'].replace(b'\n',b'\r\n'))
        self.run_installer()
        self.assertIn('compatibility launcher',bad.read_text())
    def test_second_install_is_idempotent(self):
        self.run_installer(); self.run_installer()
        self.assertEqual(len(self.actions),2)
        self.assertTrue(all('Installation terminee' in m for m in self.messages),self.messages)
    def test_running_browser_is_asked_to_close_before_any_write(self):
        states={'owner':'active','heartbeat':'1'}
        self.lua.globals()['reaper']['GetExtState']=lambda section,key:states.get(key,'')
        self.lua.globals()['reaper']['SetExtState']=lambda section,key,value,persist:states.__setitem__(key,value)
        self.lua.execute(Path(self.built['installer']).read_text())
        self.assertEqual(states['close'],'1')
        self.assertFalse((self.resource/'Scripts/ReaSkiiPicker').exists())
        states['owner']=''; states['heartbeat']=''
        while self.queue: self.queue.pop(0)()
        self.assertTrue(self.actions)
    def test_commit_failure_restores_previous_files(self):
        target=self.resource/'Scripts/ReaSkiiPicker'; old={}
        for name,value in self.built['payload'].items():
            path=target/name; path.parent.mkdir(parents=True,exist_ok=True)
            old[name]=b'-- old version\n'+value; path.write_bytes(old[name])
        self.lua.execute("local rename=os.rename; os.rename=function(a,b) if a:find('/stage/src/store.lua',1,true) then return nil,'injected rename failure' end return rename(a,b) end")
        self.run_installer()
        for name,value in old.items(): self.assertEqual((target/name).read_bytes(),value)
        self.assertEqual(self.actions,[])
        self.assertTrue(any('injected rename failure' in m for m in self.messages),self.messages)

if __name__=='__main__': unittest.main()
