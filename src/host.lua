local H={}
function H.catalog()
  local out,index={},0
  while true do
    local ok,name,ident=reaper.EnumInstalledFX(index)
    if not ok then break end
    out[#out+1]={name=name,ident=ident}; index=index+1
  end
  return out
end
function H.insert(fx)
  if not fx or type(fx.name)~='string' then return nil,'FX unavailable in this REAPER installation' end
  local project=reaper.EnumProjects(-1,'')
  local track=reaper.GetSelectedTrack(project,0)
  if not track or not reaper.ValidatePtr2(project,track,'MediaTrack*') then
    return nil,'Select a track before inserting an FX'
  end
  -- AddByName documents display-name lookup, not EnumInstalledFX identifier lookup.
  -- Refuse ambiguous names rather than silently inserting a different plugin.
  local matches=0
  for _,candidate in ipairs(H.catalog()) do if candidate.name==fx.name then matches=matches+1 end end
  if matches~=1 then return nil,'FX name is missing or ambiguous; rescan the catalog' end
  reaper.Undo_BeginBlock2(project)
  local ok,index=pcall(reaper.TrackFX_AddByName,track,fx.name,false,-1)
  reaper.Undo_EndBlock2(project,ok and index>=0 and 'ReaSkii Picker: '..fx.name or 'ReaSkii Picker: insertion failed',2)
  if not ok then return nil,tostring(index) end
  if index<0 then return nil,'REAPER could not load '..fx.name end
  reaper.TrackFX_Show(track,index,3)
  return true,index
end
return H
