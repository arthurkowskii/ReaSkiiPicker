-- @description Install or update ReaSkii Picker (self-contained)
-- Runtime version: __VERSION__
-- No downloads, administrator privileges or manual file placement required.
local r=reaper
local version='__VERSION__'
local files={
__PAYLOAD__
}
local function read(path)
 local f=io.open(path,'rb'); if not f then return nil end
 local value=f:read('*a'); f:close(); return value
end
local function mkdir(path) r.RecursiveCreateDirectory(path,0) end
local function parent(path) return assert(path:match('^(.*)[/\\]')) end
local function write(path,value)
 mkdir(parent(path))
 local f=assert(io.open(path,'wb'),'Impossible d ecrire: '..path)
 local ok,why=f:write(value); local closed,close_err=f:close()
 assert(ok and closed,why or close_err)
 assert(read(path)==value,'Verification apres ecriture echouee: '..path)
end
local function error_message(message)
 r.MB('Installation interrompue.\n\n'..tostring(message),'ReaSkii Picker',0)
end
local function install()
 assert(r.ImGui_GetBuiltinPath,'ReaImGui manque. Installer ReaImGui via ReaPack, puis relancer cet installateur.')
 package.path=r.ImGui_GetBuiltinPath()..'/?.lua;'..package.path
 local ok,why=pcall(function() return require('imgui')('0.10') end)
 assert(ok,'ReaImGui 0.10 ou superieur (extension et shim Lua) est requis: '..tostring(why))
 local resource=r.GetResourcePath()
 assert(type(resource)=='string' and resource~='' and not resource:find('\0',1,true),'Dossier REAPER invalide')
 local target=resource..'/Scripts/ReaSkiiPicker'
 local token=r.genGuid():gsub('[^%w]','')
 assert(token~='','Impossible de creer un identifiant de sauvegarde')
 local backup=resource..'/ReaSkiiPicker-backups/installer-'..token
 local stage=backup..'/stage'
 local changes={}; local committed={}; local entry
 for _,file in ipairs(files) do
  assert(not file.name:find('..',1,true) and not file.name:match('^[/\\]'),'Chemin du paquet invalide')
  if file.name:match('%.lua$') then assert(load(file.content,'@'..target..'/'..file.name)) end
  if file.name=='ReaSkii_Picker.lua' then entry=file.content end
  local destination=target..'/'..file.name
  if read(destination)~=file.content then
   changes[#changes+1]={destination=destination,content=file.content,
     staged=stage..'/'..file.name,backup=backup..'/previous/'..file.name}
  end
 end
 assert(entry,'Point d entree absent')
 -- Preserve a shortcut that points to a mistakenly installed flat entry point.
 -- Replace only the exact known entry or an already-generated compatibility launcher.
 local legacy=resource..'/Scripts/ReaSkii_Picker.lua'
 local forward="-- ReaSkii Picker compatibility launcher: preserves existing action shortcuts.\n"..
  "local path=reaper.GetResourcePath()..'/Scripts/ReaSkiiPicker/ReaSkii_Picker.lua'\n"..
  "local command=reaper.AddRemoveReaScript(true,0,path,true)\n"..
  "assert(command>0,'Cannot register ReaSkii Picker')\nreaper.Main_OnCommand(command,0)\n"
 local old=read(legacy); local warning=''
 local function normalized(value)
  return value and value:gsub('^\239\187\191',''):gsub('\r\n','\n')
 end
 if normalized(old)==normalized(entry) then
  changes[#changes+1]={destination=legacy,content=forward,staged=stage..'/compat/ReaSkii_Picker.lua',backup=backup..'/previous-flat/ReaSkii_Picker.lua'}
 elseif old and normalized(old)~=normalized(forward) then
  warning='\n\nUn ancien script different dans Scripts a ete conserve. Utiliser la nouvelle action ReaSkii_Picker.lua.'
 end
 -- Stage and verify the entire payload before replacing any installed file.
 for _,change in ipairs(changes) do write(change.staged,change.content) end
 local success,result=xpcall(function()
  for _,change in ipairs(changes) do
   mkdir(parent(change.destination)); mkdir(parent(change.backup))
   local previous=read(change.destination)
   if previous then
    assert(not read(change.backup),'Une sauvegarde existe deja; relancer pour obtenir un nouvel identifiant')
    assert(os.rename(change.destination,change.backup))
    change.moved=true
   end
   committed[#committed+1]=change
   assert(os.rename(change.staged,change.destination))
   change.installed=true
   assert(read(change.destination)==change.content,'Verification du fichier installe echouee')
  end
  for _,file in ipairs(files) do assert(read(target..'/'..file.name)==file.content,'Paquet installe incomplet: '..file.name) end
  local command=r.AddRemoveReaScript(true,0,target..'/ReaSkii_Picker.lua',true)
  assert(command and command>0,'Impossible d enregistrer l action REAPER')
  return command
 end,debug.traceback)
 if not success then
  local errors={}
  for i=#committed,1,-1 do
   local change=committed[i]
   if change.installed then
    local removed,err=os.remove(change.destination); if not removed then errors[#errors+1]=tostring(err) end
   end
   if change.moved then
    local restored,err=os.rename(change.backup,change.destination); if not restored then errors[#errors+1]=tostring(err) end
   end
  end
  error(tostring(result)..'\nSauvegardes: '..backup..(#errors>0 and '\nRestauration incomplete: '..table.concat(errors,'; ') or '\nAncienne installation restauree.'))
 end
 local message='Installation terminee: ReaSkii Picker '..version..
  '\n\nFichiers places dans Scripts/ReaSkiiPicker.\nAction enregistree: ReaSkii_Picker.lua.\nClassements et images conserves.'..
  (#changes>0 and '\nAncienne version sauvegardee dans ReaSkiiPicker-backups.' or '\nCette version etait deja installee.')..warning..
  '\n\nOuvrir le navigateur maintenant ?'
 if r.MB(message,'ReaSkii Picker',4)==6 then r.Main_OnCommand(result,0) end
end
local function run()
 local ok,err=xpcall(install,debug.traceback)
 if not ok then error_message(err) end
end
-- Never replace the running browser's files or stop the REAPER process.
local section='ReaSkiiPicker'
if r.GetExtState(section,'owner')~='' or r.GetExtState(section,'heartbeat')~='' then
 r.SetExtState(section,'close','1',false)
 local deadline=r.time_precise()+10
 local function wait()
  if r.GetExtState(section,'owner')=='' and r.GetExtState(section,'heartbeat')=='' then run()
  elseif r.time_precise()>deadline then error_message('Fermer uniquement la fenetre ReaSkii Picker, puis relancer l installateur. Aucun fichier remplace.')
  else r.defer(wait) end
 end
 r.defer(wait)
else run() end
