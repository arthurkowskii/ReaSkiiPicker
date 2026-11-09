local r=reaper
local resource=r.GetResourcePath()
local expected=PICKER_ROOT..'/qa/installer-expected'
local installer=PICKER_ROOT..'/dist/ReaSkiiPicker-0.1.1-alpha-setup.lua'
local checks={}; local messages={}; local old_mb=r.MB
local function check(value,name)
 assert(value,name); checks[#checks+1]='PASS\t'..name
 local f=assert(io.open(PICKER_RESULT..'.progress','w')); f:write(table.concat(checks,'\n')); f:close()
end
local function read(path) local f=assert(io.open(path,'rb')); local s=f:read('*a'); f:close(); return s end
local function write(path,data) r.RecursiveCreateDirectory(path:match('^(.*)/'),0); local f=assert(io.open(path,'wb')); f:write(data); f:close() end
local function finish(err)
 r.MB=old_mb
 local f=assert(io.open(PICKER_RESULT,'w'))
 f:write(table.concat(checks,'\n')..'\n')
 f:write(err and 'ERROR\t'..tostring(err)..'\n' or 'DONE\t'..#checks..'\n'); f:close()
end
local ok,err=xpcall(function()
 local flat=resource..'/Scripts/ReaSkii_Picker.lua'
 write(flat,read(expected..'/ReaSkii_Picker.lua'))
 local legacy=r.AddRemoveReaScript(true,0,flat,true); assert(legacy>0)
 local data=resource..'/ReaSkiiPicker/library.json'
 local original='{"version":1,"categories":[],"plugins":[]}'
 write(data,original)
 r.MB=function(text,title,kind) messages[#messages+1]=text; return kind==4 and 7 or 1 end
 local setup=r.AddRemoveReaScript(true,0,installer,true); assert(setup>0)
 -- Execute in this fixture's Lua environment only to answer its success dialog.
 -- The installed browser and repaired legacy shortcut are independent real actions.
 dofile(installer)
 local files={'ReaSkii_Picker.lua','src/host.lua','src/model.lua','src/store.lua','src/ui.lua','vendor/json.lua','vendor/json-LICENSE'}
 for _,name in ipairs(files) do
  local path=resource..'/Scripts/ReaSkiiPicker/'..name
  check(read(path)==read(expected..'/'..name),'installer writes exact verified runtime: '..name)
  if name:match('%.lua$') then assert(loadfile(path)) end
 end
 check(#messages==1 and messages[1]:find('Installation terminee',1,true),'installer reports completion in actual REAPER')
 check(read(data)==original,'installer preserves the separate user library byte-for-byte')
 check(read(flat):find('compatibility launcher',1,true)~=nil,'flat misplaced entry is repaired with a compatibility launcher')
 check(r.AddRemoveReaScript(true,0,flat,true)==legacy,'existing flat action keeps its registration identity')
 local command=r.AddRemoveReaScript(true,0,resource..'/Scripts/ReaSkiiPicker/ReaSkii_Picker.lua',true)
 check(command>0,'canonical installed browser is registered through REAPER API')
 r.Main_OnCommand(legacy,0) -- Exercise user's existing action, not dofile.
 local start=r.time_precise(); local first; local phase='running'
 local function loop()
  local ok,done=xpcall(function()
   assert(r.time_precise()-start<20,'Installer lifecycle timeout: '..table.concat(messages,' | '))
   local heartbeat=tonumber(r.GetExtState('ReaSkiiPicker','heartbeat'))
   if phase=='running' then
    if heartbeat and not first then first=heartbeat end
    if heartbeat and first and heartbeat-first>1 then
     check(r.GetToggleCommandStateEx(0,command)==1,'existing flat shortcut launches the real installed browser with advancing heartbeat')
     phase='stopping'; r.Main_OnCommand(command,0)
    end
   elseif phase=='stopping' and not heartbeat and r.GetExtState('ReaSkiiPicker','owner')=='' then
    phase='reinstall'; dofile(installer)
   elseif phase=='reinstall' and #messages==2 then
    check(messages[2]:find('Installation terminee',1,true)~=nil,'reinstall completes after normal browser shutdown')
    check(read(data)==original,'reinstall still preserves user data')
    check(r.GetExtState('ReaSkiiPicker','owner')=='' and r.GetToggleCommandStateEx(0,command)==0,'no browser instance remains active during reinstall')
    r.Main_OnCommand(legacy,0); first=nil; phase='reopened'
   elseif phase=='reopened' then
    if heartbeat and not first then first=heartbeat end
    if heartbeat and first and heartbeat-first>1 then
     check(r.GetToggleCommandStateEx(0,command)==1,'same user shortcut reopens browser after installer update')
     return true
    end
   end
  end,debug.traceback)
  if not ok then finish(done)
  elseif done then finish()
  else r.defer(loop) end
 end
 r.defer(loop)
end,debug.traceback)
if not ok then finish(err) end
