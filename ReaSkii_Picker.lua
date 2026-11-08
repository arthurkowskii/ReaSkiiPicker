-- @description ReaSkii Picker: Toggle visual FX browser
-- @version 0.1.1-alpha
-- @author Arthur Croquebois
local root=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local section='ReaSkiiPicker'
reaper.set_action_options(1) -- Re-launch toggles off without REAPER's terminate prompt.
local now=reaper.time_precise()
local heartbeat=tonumber(reaper.GetExtState(section,'heartbeat'))
if heartbeat and now-heartbeat>=0 and now-heartbeat<2 then
  reaper.SetExtState(section,'close','1',false)
  return
end
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Install ReaImGui 0.10 or newer through ReaPack first.','ReaSkii Picker',0)
  return
end
local token=tostring(now)
reaper.SetExtState(section,'owner',token,false)
reaper.SetExtState(section,'close','',false)
local _,_,action_section,command=reaper.get_action_context()
local function toolbar(value)
  if command and command>0 then reaper.SetToggleCommandState(action_section,command,value); reaper.RefreshToolbar2(action_section,command) end
end
reaper.atexit(function()
  if reaper.GetExtState(section,'owner')==token then
    reaper.DeleteExtState(section,'heartbeat',false)
    reaper.DeleteExtState(section,'owner',false)
    reaper.DeleteExtState(section,'close',false)
    toolbar(0)
  end
end)
local U=dofile(root..'src/ui.lua')
local ok,app=pcall(U.new)
if not ok then reaper.MB(tostring(app),'ReaSkii Picker: cannot start',0); return end
toolbar(1)
local function loop()
  if reaper.GetExtState(section,'close')=='1' then return end
  reaper.SetExtState(section,'heartbeat',tostring(reaper.time_precise()),false)
  local success,open=xpcall(function() return U.frame(app) end,debug.traceback)
  if not success then reaper.MB(tostring(open),'ReaSkii Picker: error',0); return end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
