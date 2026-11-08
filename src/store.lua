local dir=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local json=dofile(dir..'../vendor/json.lua')
local Model=dofile(dir..'model.lua')
local S={json=json}
local function read(path)
  local f,err=io.open(path,'rb'); if not f then return nil,err end
  local text=f:read('*a'); f:close(); return text
end
local function decode(path)
  local text,err=read(path); if not text then return nil,err end
  local ok,value=pcall(json.decode,text); if not ok then return nil,value end
  return value
end
function S.load(path)
  local data,err=decode(path); if not data then return nil,err end
  local ok,result=pcall(Model.validate,data); if not ok then return nil,result end
  return result
end
function S.load_picker(folder)
  local categories,err=decode(folder..'/categories.json'); if not categories then return nil,err end
  local plugins; plugins,err=decode(folder..'/plugins.json'); if not plugins then return nil,err end
  local library={version=1,categories=categories,plugins=plugins.plugins,previewRoot=folder..'/previews'}
  local ok,result=pcall(Model.validate,library); if not ok then return nil,result end
  return result
end
function S.save(path,library)
  local ok,text=pcall(function() Model.validate(library); return json.encode(library) end)
  if not ok then return nil,text end
  local temp=path..'.tmp'
  local f,err=io.open(temp,'wb'); if not f then return nil,err end
  local written,write_err=f:write(text); local closed,close_err=f:close()
  if not written or not closed then os.remove(temp); return nil,write_err or close_err end
  local verify; verify,err=S.load(temp)
  if not verify then os.remove(temp); return nil,err end
  local old=io.open(path,'rb')
  if old then
    old:close()
    local backup=io.open(path..'.bak','rb')
    if backup then backup:close(); local removed; removed,err=os.remove(path..'.bak'); if not removed then return nil,err end end
    local moved; moved,err=os.rename(path,path..'.bak'); if not moved then return nil,err end
  end
  local moved; moved,err=os.rename(temp,path)
  if not moved then
    if old then
      local restored,restore_err=os.rename(path..'.bak',path)
      if not restored then return nil,tostring(err)..'; restore failed: '..tostring(restore_err) end
    end
    return nil,err
  end
  return true
end
return S
