local U=dofile(PICKER_ROOT..'/src/ui.lua')
local S=dofile(PICKER_ROOT..'/src/store.lua')
reaper.InsertTrackAtIndex(0,false)
local track=reaper.GetTrack(0,0); reaper.SetOnlyTrackSelected(track)
reaper.GetSetMediaTrackInfo_String(track,'P_NAME','Picker test track',true)
local function write(data)
  local text=S.json.encode(data)
  local f=assert(io.open(PICKER_STATE..'.tmp','w')); f:write(text); f:close()
  assert(os.rename(PICKER_STATE..'.tmp',PICKER_STATE))
end
local ok,app=pcall(U.new,{source=PICKER_SOURCE,keep_open=true,observe=function(a)
  local thumbs=0; for _,img in pairs(a.images) do if img then thumbs=thumbs+1 end end
  local names={}; for i=1,math.min(10,#a.rows) do names[#names+1]=a.rows[i].name end
  a.observation_frame=(a.observation_frame or 0)+1
  write({frame=a.observation_frame,add_query=a.add_query,add_mode=a.add_mode,pending=a.pending~=nil,view_mode=a.view_mode,new_category=a.new_category,category_name_active=a.category_name_active,query=a.query,search_active=a.search_active,category=a.category,rects=a.rects,results=#a.rows,curated=#a.library.plugins,
    categories=#a.library.categories,thumbs=thumbs,fx=reaper.TrackFX_GetCount(track),names=names,status=a.status})
end})
if not ok then write({error=tostring(app)}); return end
local function loop()
  local success,open=xpcall(function() return U.frame(app) end,debug.traceback)
  if not success then write({error=tostring(open)}); return end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
