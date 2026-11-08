"""Actual mouse/keyboard tests in a private Xvfb/REAPER process."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import time
from Xlib import X, XK, display
from Xlib.ext import xtest
from PIL import ImageGrab
from run import ROOT, TOOLS

work=Path(os.environ['TMPDIR'])/('picker-gui-'+str(time.time_ns())); work.mkdir()
source=Path.home()/'.hermes/cache/scratch/picker-audit'
cfg=work/'config'; cfg.mkdir(); (cfg/'UserPlugins').mkdir()
shutil.copy2(TOOLS/'config/UserPlugins/reaper_imgui-x86_64.so',cfg/'UserPlugins')
shim=cfg/'Scripts/ReaTeam Extensions/API'; shim.mkdir(parents=True)
shutil.copy2(TOOLS/'imgui.lua',shim/'imgui.lua')
shutil.copytree(TOOLS/'reaper_linux_x86_64/REAPER/InstallData/Effects',cfg/'Effects')
(cfg/'reaper.ini').write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\n')
state=work/'state.json'; wrapper=work/'run.lua'
wrapper.write_text('PICKER_ROOT='+json.dumps(str(ROOT))+'\nPICKER_SOURCE='+json.dumps(str(source))+'\nPICKER_STATE='+json.dumps(str(state))+'\ndofile('+json.dumps(str(ROOT/'tests/gui.lua'))+')\n')
checks=[]; d=None; proc=None
xvfb=subprocess.Popen(['Xvfb',':188','-screen','0','1400x1000x24','-nolisten','tcp'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
os.environ['DISPLAY']=':188'
qa=ROOT/'qa'; qa.mkdir(exist_ok=True)
def snapshot():
    try:
        s=json.loads(state.read_text())
        if s.get('error'): raise RuntimeError(s['error'])
        return s
    except (OSError,json.JSONDecodeError): return {}
def wait(fn,label,seconds=20):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        value=fn()
        if value: return value
        time.sleep(.12)
    capture('picker-timeout.png')
    raise AssertionError(label+' '+str(snapshot())[:1500]+' process='+str(proc.poll() if proc else None))
def expect(fn,label):
    wait(lambda:fn(snapshot()),label); checks.append(label); print('PASS',label,flush=True)
def rendered_frames(count=1):
    frame=snapshot().get('frame',0)
    wait(lambda:snapshot().get('frame',0)>=frame+count,'host did not consume the input frame')
def key(name,down=None):
    code=d.keysym_to_keycode(XK.string_to_keysym(name))
    assert code,name
    for kind in ([X.KeyPress,X.KeyRelease] if down is None else [X.KeyPress if down else X.KeyRelease]):
        xtest.fake_input(d,kind,code); d.sync(); rendered_frames()
def click_rect(name,button=1):
    r=wait(lambda:snapshot().get('rects',{}).get(name),'missing control '+name)
    xtest.fake_input(d,X.MotionNotify,x=int(r['x']+r['w']/2),y=int(r['y']+r['h']/2)); d.sync(); rendered_frames(2)
    xtest.fake_input(d,X.ButtonPress,button); d.sync(); rendered_frames(2)
    xtest.fake_input(d,X.ButtonRelease,button); d.sync(); rendered_frames(2)
def capture(name): ImageGrab.grab(xdisplay=':188').save(qa/name)
try:
    time.sleep(1); d=display.Display(':188')
    # Frame synchronization may hold keys during slow image decode. Prevent X11 autorepeat in this isolated display only.
    d.change_keyboard_control(auto_repeat_mode=X.AutoRepeatModeOff); d.sync()
    with (work/'reaper.log').open('w') as log:
        proc=subprocess.Popen([str(TOOLS/'reaper_linux_x86_64/REAPER/reaper'),'-newinst','-nosplash','-cfgfile',str(cfg/'reaper.ini'),str(wrapper)],stdout=log,stderr=log)
        expect(lambda s:s.get('curated')==121,'real UI imports 121 curated FX')
        expect(lambda s:s.get('thumbs',0)>0,'actual Picker PNGs loaded by ReaImGui')
        # Focus the actual top-level window without clicking the search field.
        def picker_window():
            for w in d.screen().root.query_tree().children:
                if 'ReaSkii Picker' in (w.get_wm_name() or ''): return w
        w=wait(picker_window,'native Picker window')
        w.set_input_focus(X.RevertToParent,X.CurrentTime); w.configure(stack_mode=X.Above); d.sync(); time.sleep(.3)
        capture('picker-collection.png')
        wait(lambda:snapshot().get('search_active'),'search focus readiness')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('query')=='volume','typing immediately after open reaches search')
        expect(lambda s:s.get('results',0)>0 and all('volume' in n.lower() for n in s['names']),'global search returns real uncategorized JSFX')
        expect(lambda s:s.get('view_mode')=='list' and 'row:1' in s.get('rects',{}) and 'card:1' not in s.get('rects',{}),'global search renders compact rows instead of empty screenshot cards')
        capture('picker-global-search.png')
        click_rect('cat:31a982d0b967dee5')
        expect(lambda s:s.get('category')=='31a982d0b967dee5' and s.get('query')=='','category click returns to curated EQ grid')
        capture('picker-eq.png')
        wait(lambda:snapshot().get('search_active'),'search focus readiness')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('query')=='volume' and s.get('results',0)>0,'global search works even with EQ category selected')
        click_rect('collection')
        expect(lambda s:s.get('query')=='' and s.get('category')=='' and s.get('results')==121,'Collection restores manual library without catalog inflation')
        capture('picker-final.png')
        expect(lambda s:'cat:25cfa2596aa6b61d' not in s.get('rects',{}),'subfolders are hidden outside their parent dropdown')
        click_rect('cat:198dbd616fb01068')
        expect(lambda s:'cat:25cfa2596aa6b61d' in s.get('rects',{}),'Dynamics opens actual nested folder menu')
        capture('picker-folders.png')
        click_rect('cat:25cfa2596aa6b61d')
        expect(lambda s:s.get('category')=='25cfa2596aa6b61d' and s.get('results',0)>0 and s.get('view_mode')=='grid','Compressor submenu filters the curated screenshot grid')
        click_rect('collection')
        click_rect('all')
        expect(lambda s:s.get('view_mode')=='list' and s.get('results',0)>200 and len([k for k in s.get('rects',{}) if k.startswith('row:')])<35,'All FX is a virtualized list, not a grid of 249 placeholders')
        click_rect('collection')
        click_rect('add-plugin')
        expect(lambda s:s.get('view_mode')=='add' and s.get('fx')==0,'header Add Plugin opens a separate non-inserting catalog')
        wait(lambda:snapshot().get('search_active'),'add search focus')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('add_query')=='volume' and s.get('results',0)>1,'Add Plugin catalog has live list search')
        click_rect('row:2')
        expect(lambda s:s.get('pending') and s.get('fx')==0,'choosing Add Plugin result opens classification without inserting')
        click_rect('cancel-add')
        expect(lambda s:not s.get('pending') and s.get('curated')==121 and s.get('fx')==0,'Cancel Add Plugin preserves collection and FX chain')
        click_rect('back')
        click_rect('settings')
        click_rect('new-category')
        click_rect('category-name')
        wait(lambda:snapshot().get('category_name_active'),'category name focus readiness')
        for letter in 'test': key(letter)
        expect(lambda s:s.get('new_category')=='test','category name accepts keyboard input')
        key('Return')
        expect(lambda s:s.get('fx')==0,'Enter in category popup never inserts a plugin')
        click_rect('create-category')
        expect(lambda s:s.get('categories')==26,'new category created by actual UI clicks')
        wait(lambda:snapshot().get('search_active'),'search focus readiness')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('query')=='volume','search refocuses after returning to collection')
        click_rect('row:1',3)
        click_rect('assign-menu')
        click_rect('assign:cat-1')
        expect(lambda s:s.get('curated')==122,'right-click assignment explicitly adds FX to manual library')
        persisted=json.loads((cfg/'ReaSkiiPicker/library.json').read_text())
        assert any('cat-1' in p.get('categoryIds',[]) for p in persisted['plugins'])
        checks.append('category assignment persisted to independent library')
        click_rect('cat:cat-1')
        expect(lambda s:s.get('results')==1 and s.get('query')=='','new manual category displays assigned FX')
        capture('picker-assigned.png')
        wait(lambda:snapshot().get('search_active'),'search focus readiness')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('query')=='volume','global search remains accessible after assignment')
        click_rect('collection')
        wait(lambda:snapshot().get('search_active'),'collection focus before background menu')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('query')=='volume','background menu fixture keeps selected category empty')
        click_rect('background',3)
        click_rect('context-add')
        expect(lambda s:s.get('add_mode') and s.get('view_mode')=='add','right-click empty browser space offers Add Plugin')
        wait(lambda:snapshot().get('search_active'),'context Add Plugin focus')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('add_query')=='volume','context Add Plugin searches the installed catalog')
        click_rect('row:2')
        expect(lambda s:s.get('pending') and s.get('fx')==0,'Add Plugin opens classification and never inserts on track')
        capture('picker-add-plugin.png')
        click_rect('assign-check:31a982d0b967dee5')
        click_rect('confirm-add')
        expect(lambda s:not s.get('pending') and not s.get('add_mode') and s.get('curated')==123 and s.get('fx')==0,'confirm Add Plugin saves one new curated plugin without insertion')
        persisted=json.loads((cfg/'ReaSkiiPicker/library.json').read_text())
        assert any(p['name'].startswith('JS: Volume Adjustment') and '31a982d0b967dee5' in p.get('categoryIds',[]) for p in persisted['plugins'])
        checks.append('Add Plugin category assignment persists in independent state')
        wait(lambda:snapshot().get('search_active'),'post-add global search focus')
        for letter in 'volume': key(letter)
        expect(lambda s:s.get('query')=='volume' and s.get('view_mode')=='list','return from Add Plugin restores global list search')
        key('Return')
        expect(lambda s:s.get('fx')==1,'Enter inserts first search result on real track')
        expect(lambda s:s.get('curated')==123,'Enter does not add plugin to manual collection')
        proc.terminate(); proc.wait(timeout=5); state.unlink(missing_ok=True)
        proc=subprocess.Popen([str(TOOLS/'reaper_linux_x86_64/REAPER/reaper'),'-newinst','-nosplash','-cfgfile',str(cfg/'reaper.ini'),str(wrapper)],stdout=log,stderr=log)
        expect(lambda s:s.get('curated')==123 and s.get('categories')==26,'category and library edits survive real REAPER restart')
        w=wait(picker_window,'reopened native Picker window')
        w.set_input_focus(X.RevertToParent,X.CurrentTime); w.configure(stack_mode=X.Above); d.sync(); time.sleep(.3)
        click_rect('cat:cat-1')
        expect(lambda s:s.get('results')==1,'persisted manual category works after restart')
finally:
    if d: d.close()
    for p in (proc,xvfb):
        if p:
            p.terminate()
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
    (qa/'gui-report.json').write_text(json.dumps({'work':str(work),'checks':checks,'count':len(checks),'runtime_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'ReaSkii_Picker.lua',*sorted((ROOT/'src').glob('*.lua'))]}},indent=2))
print('DONE',len(checks),flush=True)
