local dir=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local M=dofile(dir..'model.lua')
local S=dofile(dir..'store.lua')
local H=dofile(dir..'host.lua')
local U={}
function U.new(options)
  options=options or {}
  local resource=options.resource or reaper.GetResourcePath()
  local folder=resource..'/ReaSkiiPicker'
  reaper.RecursiveCreateDirectory(folder,0)
  local path=folder..'/library.json'
  local state,err
  if reaper.file_exists(path) then
    state,err=S.load(path); assert(state,'Cannot read own library (preserved): '..tostring(err))
  else
    local source=options.source or resource..'/PluginPicker'
    if reaper.file_exists(source..'/categories.json') then
      state,err=S.load_picker(source); assert(state,'Picker import refused: '..tostring(err))
    else state={version=1,categories={},plugins={}} end
    local ok; ok,err=S.save(path,state); assert(ok,err)
  end
  package.path=reaper.ImGui_GetBuiltinPath()..'/?.lua;'..package.path
  local I=require('imgui')('0.10')
  local app={I=I,ctx=I.CreateContext('ReaSkii Picker'),library=state,path=path,
    catalog=H.catalog(),query='',category='',show_all=false,selection=1,rows={},images={},
    status='',focus=true,open=true,rects={},options=options,new_category='',revision=0,
    add_mode=false,add_query='',pending_categories={}}
  function app:edit(fn)
    local copy=S.json.decode(S.json.encode(self.library))
    local ok,result=pcall(fn,copy)
    if not ok then self.status=tostring(result); return false end
    local saved,save_err=S.save(self.path,copy)
    if not saved then self.status='Not saved: '..tostring(save_err); return false end
    self.library=copy; self.revision=self.revision+1; self.status='Saved'; return true
  end
  function app:insert(row)
    local ok,index=H.insert(row and row.catalog)
    self.status=ok and 'Inserted: '..row.name or tostring(index)
    if ok and not self.options.keep_open then self.open=false end
    return ok
  end
  function app:select_category(id,all)
    self.category=id or ''; self.show_all=all or false; self.query=''; self.selection=1
    self.add_mode=false; self.focus=true; self.keyboard_selection=false
  end
  function app:open_add()
    self.add_mode=true; self.add_query=''; self.selection=1; self.focus=true
  end
  function app:choose(row)
    if not self.add_mode then return self:insert(row) end
    self.pending=row; self.pending_categories={}
    for _,field in ipairs({'categoryIds','subcategoryIds'}) do
      for _,id in ipairs((row.saved or {})[field] or {}) do self.pending_categories[id]=true end
    end
    if self.category~='' then self.pending_categories[self.category]=true end
    self.open_assign=true
  end
  return app
end
local function record(a,key)
  if not a.options.observe then return end
  local x,y=a.I.GetItemRectMin(a.ctx); local xx,yy=a.I.GetItemRectMax(a.ctx)
  a.rects[key]={x=x,y=y,w=xx-x,h=yy-y}
end
local function button(a,key,label,w,h)
  local clicked=a.I.Button(a.ctx,label,w,h); record(a,key); return clicked
end
local function item(a,key,label,selected)
  local clicked=a.I.MenuItem(a.ctx,label,nil,selected or false); record(a,key); return clicked
end
local function image(a,p)
  if not p then return end
  local path=p.previewPath
  if not path and a.library.previewRoot and p.id:match('^[%w_-]+$') then path=a.library.previewRoot..'/'..p.id..'.png' end
  if not path then return end
  if a.images[path]==nil then
    if reaper.file_exists(path) then
      local ok,img=pcall(a.I.CreateImage,path)
      if ok then a.I.Attach(a.ctx,img); a.images[path]=img else a.images[path]=false end
    else a.images[path]=false end
  end
  return a.images[path] or nil
end
local function common_menu(a)
  if item(a,'context-add','Add Plugin...') then a:open_add() end
  if item(a,'context-new-category','New category...') then a.open_new_category=true end
end
local function context(a,row)
  local I,ctx=a.I,a.ctx
  if not I.BeginPopupContextItem(ctx) then return end
  common_menu(a); I.Separator(ctx); I.TextDisabled(ctx,row.name)
  local menu=I.BeginMenu(ctx,'Add to category'); record(a,'assign-menu')
  if menu then
    for _,entry in ipairs(M.categories(a.library)) do
      local c=entry.category
      if item(a,'assign:'..c.id,M.category_path(a.library,c.id)..'##'..c.id) then
        a:edit(function(state) M.assign(state,row.saved or row.catalog,c.id) end)
      end
    end
    I.EndMenu(ctx)
  end
  if row.saved then
    local remove_menu=I.BeginMenu(ctx,'Remove category assignment'); record(a,'remove-menu')
    if remove_menu then
      local memberships={}
      for _,field in ipairs({'categoryIds','subcategoryIds'}) do
        for _,id in ipairs(row.saved[field] or {}) do memberships[id]=true end
      end
      for _,entry in ipairs(M.categories(a.library)) do
        local c=entry.category
        if memberships[c.id] and item(a,'remove:'..c.id,M.category_path(a.library,c.id)..'##remove-'..c.id) then
          a:edit(function(state)
            for _,p in ipairs(state.plugins) do if p.id==row.saved.id then M.unassign(state,p,c.id) end end
          end)
        end
      end
      I.EndMenu(ctx)
    end
    if item(a,'thumbnail','Choose thumbnail...') then
      local ok,path=reaper.GetUserFileNameForRead('','Choose a PNG thumbnail','.png')
      if ok then a:edit(function(state)
        for _,p in ipairs(state.plugins) do if p.id==row.saved.id then p.previewPath=path end end
      end) end
    end
  end
  I.EndPopup(ctx)
end
local function scroll_selected(a,index)
  if index==a.selection and a.scroll_selection then
    a.I.SetScrollHereY(a.ctx,0.5); a.scroll_selection=false
  end
end
local function card(a,row,index,width)
  local I,ctx=a.I,a.ctx
  local image_h=width*0.75
  local height=image_h+44
  I.PushID(ctx,index)
  local x,y=I.GetCursorScreenPos(ctx)
  local clicked=I.InvisibleButton(ctx,'FX',width,height)
  scroll_selected(a,index)
  if not I.IsItemVisible(ctx) then I.PopID(ctx); return end
  record(a,'card:'..index)
  local hover=I.IsItemHovered(ctx); local draw=I.GetWindowDrawList(ctx)
  I.DrawList_AddRectFilled(draw,x+1,y+2,x+width+1,y+image_h+3,0x00000055,5)
  I.DrawList_AddRectFilled(draw,x,y,x+width,y+image_h,0x171717ff,5)
  local img=image(a,row.saved)
  if img then
    local iw,ih=I.Image_GetSize(img)
    local scale=math.min((width-4)/iw,(image_h-4)/ih)
    local w,h=iw*scale,ih*scale
    I.DrawList_AddImageRounded(draw,img,x+(width-w)/2,y+(image_h-h)/2,x+(width+w)/2,y+(image_h+h)/2,0,0,1,1,0xffffffff,4)
  else
    I.DrawList_AddText(draw,x+12,y+image_h/2-7,0x888888ff,'No preview')
  end
  if hover or (a.keyboard_selection and index==a.selection) then
    I.DrawList_AddRect(draw,x,y,x+width,y+image_h,hover and 0x777777ff or 0x13bd99ff,5,0,1.5)
  end
  local label=row.name:gsub('^[^:]+:%s*','')
  I.DrawList_AddTextEx(draw,nil,14,x+3,y+image_h+7,row.catalog and 0xd8d8d8ff or 0x969696ff,label,width-6,x,y+image_h,x+width,y+height)
  if hover then
    I.BeginTooltip(ctx); I.Text(ctx,row.name)
    if not row.catalog then I.TextDisabled(ctx,'Unavailable in this REAPER installation') end
    I.EndTooltip(ctx)
  end
  context(a,row)
  if clicked then a.selection=index; a:choose(row) end
  I.PopID(ctx)
end
local function list(a)
  local I,ctx=a.I,a.ctx
  if not a.clipper then a.clipper=I.CreateListClipper(ctx); I.Attach(ctx,a.clipper) end
  I.PushStyleVar(ctx,I.StyleVar_ItemSpacing,0,2)
  I.ListClipper_Begin(a.clipper,#a.rows)
  if a.scroll_selection and #a.rows>0 then I.ListClipper_IncludeItemByIndex(a.clipper,a.selection-1) end
  while I.ListClipper_Step(a.clipper) do
    local first,last=I.ListClipper_GetDisplayRange(a.clipper)
    for index=first+1,last do
      local row=a.rows[index]
      I.PushID(ctx,index)
      local x,y=I.GetCursorScreenPos(ctx); local width=I.GetContentRegionAvail(ctx)
      local clicked=I.Selectable(ctx,'##fx',a.selection==index,0,0,28)
      record(a,'row:'..index); scroll_selected(a,index)
      local draw=I.GetWindowDrawList(ctx)
      local badge=row.saved and 'In collection' or a.add_mode and 'Add to collection' or ''
      local reserve=badge~='' and 145 or 12
      I.DrawList_PushClipRect(draw,x+8,y,x+width-reserve,y+28,true)
      I.DrawList_AddText(draw,x+9,y+6,0xe0e0e0ff,row.name)
      I.DrawList_PopClipRect(draw)
      if badge~='' then I.DrawList_AddText(draw,x+width-136,y+6,0x909090ff,badge) end
      if I.IsItemHovered(ctx) then I.BeginTooltip(ctx); I.Text(ctx,row.name); I.EndTooltip(ctx) end
      context(a,row)
      if clicked then a.selection=index; a:choose(row) end
      I.PopID(ctx)
    end
  end
  I.PopStyleVar(ctx)
end
local function folder_items(a,parent)
  local I,ctx=a.I,a.ctx
  for _,c in ipairs(M.children(a.library,parent)) do
    local children=M.children(a.library,c.id)
    if #children>0 then
      local expanded=I.BeginMenu(ctx,c.name..'##'..c.id); record(a,'folder:'..c.id)
      if expanded then
        if item(a,'cat:'..c.id,'All '..c.name) then a:select_category(c.id) end
        I.Separator(ctx); folder_items(a,c.id); I.EndMenu(ctx)
      end
    elseif item(a,'cat:'..c.id,c.name,a.category==c.id) then a:select_category(c.id) end
  end
end
local function category_bar(a)
  local I,ctx=a.I,a.ctx
  local roots=M.children(a.library,'')
  local available=I.GetContentRegionAvail(ctx)-20
  local widths={I.CalcTextSize(ctx,'All')+24,I.CalcTextSize(ctx,'All FX')+24}
  for _,c in ipairs(roots) do
    widths[#widths+1]=I.CalcTextSize(ctx,c.name..(#M.children(a.library,c.id)>0 and '  ▾' or ''))+24
  end
  local rows,used=1,0
  for _,w in ipairs(widths) do if used>0 and used+w+8>available then rows=rows+1; used=0 end; used=used+w+8 end
  I.PushStyleColor(ctx,I.Col_ChildBg,0x2d2d2dff)
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,10,9)
  if I.BeginChild(ctx,'categories',0,rows*38+10,I.ChildFlags_AlwaysUseWindowPadding,I.WindowFlags_NoScrollbar|I.WindowFlags_NoScrollWithMouse) then
    local start=I.GetCursorScreenPos(ctx); local limit=start+I.GetContentRegionAvail(ctx)
    local selected_root=a.category
    for _,entry in ipairs(M.categories(a.library)) do
      if entry.category.id==a.category then
        local c=entry.category
        local ids={}; for _,v in ipairs(a.library.categories) do ids[v.id]=v end
        while c.parentId and ids[c.parentId] do c=ids[c.parentId] end
        selected_root=c.id; break
      end
    end
    local first_tab=true
    local function tab(key,label,active,callback)
      local width=I.CalcTextSize(ctx,label)+24
      if not first_tab then
        local last=I.GetItemRectMax(ctx)
        if last+width+8<=limit then I.SameLine(ctx) end
      end
      first_tab=false
      if active then I.PushStyleColor(ctx,I.Col_Button,0x4b4b4bff) end
      if button(a,key,label,width,30) then callback() end
      if active then I.PopStyleColor(ctx) end
    end
    tab('collection','All',a.category=='' and not a.show_all,function() a:select_category('') end)
    tab('all','All FX',a.show_all,function() a:select_category('',true) end)
    for _,c in ipairs(roots) do
      local children=M.children(a.library,c.id)
      local popup='folder-popup:'..c.id
      tab('cat:'..c.id,c.name..(#children>0 and '  ▾' or ''),selected_root==c.id,function()
        if #children>0 then I.OpenPopup(ctx,popup) else a:select_category(c.id) end
      end)
      local popup_x=I.GetItemRectMin(ctx)
      local _,popup_y=I.GetItemRectMax(ctx)
      I.SetNextWindowPos(ctx,popup_x,popup_y+4,I.Cond_Appearing)
      if I.BeginPopup(ctx,popup) then
        if item(a,'cat:'..c.id..':all','All '..c.name,a.category==c.id) then a:select_category(c.id) end
        I.Separator(ctx); folder_items(a,c.id); I.EndPopup(ctx)
      end
    end
    I.EndChild(ctx)
  end
  I.PopStyleVar(ctx); I.PopStyleColor(ctx)
end
local function header(a)
  local I,ctx=a.I,a.ctx
  local focused=I.IsWindowFocused(ctx,I.FocusedFlags_ChildWindows)
  if focused and not a.was_focused then a.focus=true end
  a.was_focused=focused
  if a.focus or I.IsWindowAppearing(ctx) then I.SetKeyboardFocusHere(ctx); a.focus=false end
  I.PushStyleVar(ctx,I.StyleVar_FramePadding,10,9)
  I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,1)
  I.PushStyleColor(ctx,I.Col_Border,a.search_active and 0x13bd99ff or 0x4a4a4aff)
  I.SetNextItemWidth(ctx,-118)
  local enter=I.IsKeyPressed(ctx,I.Key_Enter) and a.search_active
  local query=a.add_mode and a.add_query or a.query
  local changed,value=I.InputTextWithHint(ctx,'##search',a.add_mode and 'Find a plugin to add to your collection...' or 'Search all installed plugins...',query)
  record(a,'search'); a.search_active=I.IsItemActive(ctx)
  if changed then
    if a.add_mode then a.add_query=value else a.query=value end
    a.selection=1; a.keyboard_selection=false
  end
  I.PopStyleColor(ctx); I.PopStyleVar(ctx,2)
  I.SameLine(ctx)
  if button(a,a.add_mode and 'back' or 'add-plugin',a.add_mode and 'Back' or 'Add Plugin',110,34) then
    if a.add_mode then a.add_mode=false; a.focus=true else a:open_add() end
  end
  return enter
end
local function popups(a)
  local I,ctx=a.I,a.ctx
  if a.open_new_category then I.OpenPopup(ctx,'New category'); a.open_new_category=false end
  if I.BeginPopup(ctx,'New category') then
    local c; c,a.new_category=I.InputText(ctx,'Name',a.new_category)
    record(a,'category-name'); a.category_name_active=I.IsItemActive(ctx)
    if a.category~='' then I.TextDisabled(ctx,'Parent: '..M.category_path(a.library,a.category)) end
    if button(a,'create-category','Create',90,0) then
      if a:edit(function(state) M.add_category(state,a.new_category,a.category) end) then
        a.new_category=''; a.focus=true; I.CloseCurrentPopup(ctx)
      end
    end
    I.SameLine(ctx)
    if button(a,'cancel-category','Cancel',90,0) then a.focus=true; I.CloseCurrentPopup(ctx) end
    I.EndPopup(ctx)
  end
  if a.open_assign then I.OpenPopup(ctx,'Add to collection'); a.open_assign=false end
  I.SetNextWindowSize(ctx,490,0,I.Cond_Appearing)
  if I.BeginPopupModal(ctx,'Add to collection',nil,I.WindowFlags_AlwaysAutoResize) then
    I.TextWrapped(ctx,a.pending.name)
    I.TextDisabled(ctx,'Choose categories, or leave unchecked to keep it unclassified.')
    if I.BeginChild(ctx,'assign-categories',0,280) then
      for _,entry in ipairs(M.categories(a.library)) do
        local c=entry.category
        local changed,value=I.Checkbox(ctx,M.category_path(a.library,c.id)..'##'..c.id,a.pending_categories[c.id] or false)
        record(a,'assign-check:'..c.id)
        if changed then a.pending_categories[c.id]=value end
      end
      I.EndChild(ctx)
    end
    I.Separator(ctx)
    if button(a,'confirm-add','Add to collection',170,32) then
      local target=''
      local ok=a:edit(function(state)
        local p=M.remember(state,a.pending.saved or a.pending.catalog)
        for _,entry in ipairs(M.categories(state)) do
          local id=entry.category.id
          if a.pending_categories[id] then M.assign(state,p,id); if target=='' then target=id end end
        end
      end)
      if ok then a.pending=nil; a:select_category(target); I.CloseCurrentPopup(ctx) end
    end
    I.SameLine(ctx)
    if button(a,'cancel-add','Cancel',100,32) then a.pending=nil; a.focus=true; I.CloseCurrentPopup(ctx) end
    I.EndPopup(ctx)
  end
end
local function footer(a)
  local I,ctx=a.I,a.ctx
  I.Separator(ctx)
  local track=reaper.GetSelectedTrack(0,0); local name=''
  if track then local _; _,name=reaper.GetTrackName(track) end
  I.TextDisabled(ctx,track and 'Target: '..name or 'Select a track to insert an FX')
  I.SameLine(ctx)
  I.TextDisabled(ctx,'  |  Right-click for options')
  I.SameLine(ctx)
  local width=I.GetContentRegionAvail(ctx)
  if width>100 then I.SetCursorPosX(ctx,I.GetCursorPosX(ctx)+width-90) end
  if button(a,'settings','Settings',90,27) then I.OpenPopup(ctx,'Settings') end
  if I.BeginPopup(ctx,'Settings') then
    if item(a,'new-category','New category...') then a.open_new_category=true end
    if item(a,'rescan','Refresh installed FX') then a.catalog=H.catalog(); a.revision=a.revision+1 end
    I.TextDisabled(ctx,#a.catalog..' installed FX | '..#a.library.plugins..' in collection')
    I.EndPopup(ctx)
  end
  if a.status~='' and a.status~='Saved' then I.TextWrapped(ctx,a.status) end
end
local function body(a)
  local I,ctx=a.I,a.ctx
  if I.BeginChild(ctx,'results',0,-45) then
    if a.reset_scroll then I.SetScrollY(ctx,0); a.reset_scroll=false end
    if a.options.observe then
      local x,y=I.GetCursorScreenPos(ctx); local w,h=I.GetContentRegionAvail(ctx)
      a.rects.background={x=x+w-35,y=y+h-35,w=22,h=22}
    end
    if a.view_mode=='grid' then
      local width=I.GetContentRegionAvail(ctx)
      local cols=math.max(1,math.floor((width+14)/175))
      local cell=(width-(cols-1)*14)/cols
      for index,row in ipairs(a.rows) do
        if (index-1)%cols~=0 then I.SameLine(ctx,0,14) end
        card(a,row,index,cell)
      end
    else list(a) end
    if #a.rows==0 then I.TextDisabled(ctx,'No plugins found. Search the installed catalog or choose another category.') end
    if I.BeginPopupContextWindow(ctx,'background-options',I.PopupFlags_MouseButtonRight|I.PopupFlags_NoOpenOverItems) then
      common_menu(a); I.EndPopup(ctx)
    end
    I.EndChild(ctx)
  end
end
function U.frame(a)
  local I,ctx=a.I,a.ctx
  a.rects={}
  I.PushFont(ctx,nil,14)
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,16,12)
  I.PushStyleVar(ctx,I.StyleVar_ItemSpacing,8,8)
  I.PushStyleVar(ctx,I.StyleVar_FramePadding,10,6)
  I.PushStyleVar(ctx,I.StyleVar_FrameRounding,4)
  I.PushStyleVar(ctx,I.StyleVar_ChildRounding,4)
  I.PushStyleVar(ctx,I.StyleVar_PopupRounding,5)
  I.PushStyleVar(ctx,I.StyleVar_ScrollbarSize,17)
  local colors={{I.Col_WindowBg,0x202020ff},{I.Col_PopupBg,0x292929ff},{I.Col_FrameBg,0x383838ff},
    {I.Col_Button,0x383838ff},{I.Col_ButtonHovered,0x494949ff},{I.Col_ButtonActive,0x545454ff},
    {I.Col_Header,0x0e7d6690},{I.Col_HeaderHovered,0x4a4a4aff},{I.Col_HeaderActive,0x0e7d66ff}}
  for _,c in ipairs(colors) do I.PushStyleColor(ctx,c[1],c[2]) end
  I.SetNextWindowSize(ctx,1155,700,I.Cond_FirstUseEver)
  local visible,open=I.Begin(ctx,'ReaSkii Picker | alpha',a.open,I.WindowFlags_NoCollapse|I.WindowFlags_NoScrollbar|I.WindowFlags_NoScrollWithMouse)
  a.open=open
  if visible then
    local enter=header(a)
    if not a.add_mode then category_bar(a) end
    local query=a.add_mode and a.add_query or a.query
    a.view_mode=M.view_mode(query,a.show_all,a.add_mode)
    local cache_key=table.concat({query,a.category,a.view_mode,tostring(a.revision)},'\0')
    if cache_key~=a.cache_key then
      a.rows=M.results(a.library,a.catalog,query,a.category,a.show_all or a.add_mode)
      a.cache_key=cache_key; a.reset_scroll=true
      a.selection=math.min(math.max(1,a.selection),math.max(1,#a.rows))
    end
    local popup=I.IsPopupOpen(ctx,'',I.PopupFlags_AnyPopupId|I.PopupFlags_AnyPopupLevel)
    if a.search_active and not popup then
      if I.IsKeyPressed(ctx,I.Key_DownArrow) then a.selection=math.min(#a.rows,a.selection+1); a.scroll_selection=true; a.keyboard_selection=true end
      if I.IsKeyPressed(ctx,I.Key_UpArrow) then a.selection=math.max(1,a.selection-1); a.scroll_selection=true; a.keyboard_selection=true end
    end
    if enter and not popup and #a.rows>0 then a:choose(a.rows[a.selection]) end
    local label=a.add_mode and 'Add Plugin  /  Choose a plugin, then its categories' or
      a.view_mode=='list' and 'Installed plugins' or a.category~='' and M.category_path(a.library,a.category) or 'Collection'
    I.TextDisabled(ctx,label..'   ·   '..#a.rows..' results')
    I.Separator(ctx)
    body(a); footer(a); popups(a)
    if not popup and I.IsKeyPressed(ctx,I.Key_Escape) then
      if a.add_mode then a.add_mode=false; a.focus=true
      elseif a.query~='' then a.query=''; a.focus=true else a.open=false end
    end
    I.End(ctx)
  end
  I.PopStyleColor(ctx,#colors); I.PopStyleVar(ctx,7); I.PopFont(ctx)
  if a.options.observe then a.options.observe(a) end
  return a.open
end
return U
