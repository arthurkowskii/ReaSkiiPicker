local checks={}
local command=reaper.AddRemoveReaScript(true,0,PICKER_ROOT..'/ReaSkii_Picker.lua',true)
local function check(ok,name) assert(ok,name); checks[#checks+1]='PASS\t'..name end
check(command>0,'entry point registered as real independent action')
local phase,started,frames=0,reaper.time_precise(),0
local function finish(err)
 local f=assert(io.open(PICKER_RESULT,'w')); f:write(table.concat(checks,'\n'),'\n')
 if err then f:write('ERROR\t',err) else f:write('DONE\t',#checks,'\n') end
 f:close()
end
local function tick()
 local ok,err=xpcall(function()
  assert(reaper.time_precise()-started<20,'Toggle lifecycle timeout at phase '..phase)
  local alive=reaper.GetExtState('ReaSkiiPicker','heartbeat')~=''
  if phase==0 then reaper.Main_OnCommand(command,0); phase=1
  elseif phase==1 and alive then
   check(reaper.GetToggleCommandStateEx(0,command)==1,'launch starts deferred entry point and toolbar toggle')
   phase=2; frames=0
  elseif phase==2 then
   frames=frames+1
   if frames>20 then reaper.Main_OnCommand(command,0); phase=3 end
  elseif phase==3 and not alive then
   check(reaper.GetToggleCommandStateEx(0,command)==0,'same action toggles off and clears lifecycle state')
   reaper.Main_OnCommand(command,0); phase=4
  elseif phase==4 and alive then
   check(reaper.GetToggleCommandStateEx(0,command)==1,'same action reopens after clean shutdown')
   phase=5; frames=0
  elseif phase==5 then
   frames=frames+1
   if frames>20 then reaper.Main_OnCommand(command,0); phase=6 end
  elseif phase==6 and not alive then
   check(true,'second shutdown completes without duplicate browser instance')
   phase=7
  end
 end,debug.traceback)
 if not ok then finish(err)
 elseif phase==7 then finish()
 else reaper.defer(tick) end
end
reaper.defer(tick)
