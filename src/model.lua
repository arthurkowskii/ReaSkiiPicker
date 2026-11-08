local M = {}
local function nonempty(s) return type(s)=='string' and s:match('%S') end
local function contains(values, value)
  for _,v in ipairs(values or {}) do if v == value then return true end end
  return false
end
local function key(p) return p.name .. '\0' .. p.ident end
M.key = key
function M.validate(state)
  assert(type(state)=='table' and type(state.categories)=='table' and type(state.plugins)=='table','Invalid library')
  local ids, plugins = {}, {}
  for _,c in ipairs(state.categories) do
    assert(nonempty(c.id) and nonempty(c.name) and not ids[c.id], 'Invalid/duplicate category')
    ids[c.id] = c
  end
  for _,c in ipairs(state.categories) do
    local seen, parent = {}, c
    while parent do
      assert(not seen[parent.id], 'Category cycle'); seen[parent.id] = true
      if parent.parentId and parent.parentId ~= '' then
        assert(ids[parent.parentId], 'Unknown parent'); parent = ids[parent.parentId]
      else parent = nil end
    end
  end
  for _,p in ipairs(state.plugins) do
    assert(nonempty(p.id) and nonempty(p.name) and nonempty(p.ident) and not plugins[p.id], 'Invalid/duplicate plugin')
    plugins[p.id] = true
    for _,field in ipairs({'categoryIds','subcategoryIds'}) do
      assert(p[field]==nil or type(p[field])=='table','Invalid memberships')
      for _,id in ipairs(p[field] or {}) do assert(ids[id], 'Unknown membership') end
    end
  end
  return state
end
function M.categories(state)
  local out = {}
  local function visit(parent, depth)
    local children = {}
    for _,c in ipairs(state.categories) do if (c.parentId or '')==parent then children[#children+1]=c end end
    table.sort(children,function(a,b)
      if (a.order or 0)~=(b.order or 0) then return (a.order or 0)<(b.order or 0) end
      return a.name < b.name
    end)
    for _,c in ipairs(children) do
      out[#out+1]={category=c, depth=depth}; visit(c.id,depth+1)
    end
  end
  visit('',0); return out
end
local function in_category(state,p,id)
  if not id or id=='' then return true end
  local descendants={[id]=true}
  for _=1,#state.categories do
    for _,c in ipairs(state.categories) do if descendants[c.parentId] then descendants[c.id]=true end end
  end
  for _,field in ipairs({'categoryIds','subcategoryIds'}) do
    for _,v in ipairs(p[field] or {}) do if descendants[v] then return true end end
  end
  return false
end
function M.results(state,catalog,query,category,show_all)
  local exact, names, curated = {}, {}, {}
  for _,p in ipairs(catalog) do
    exact[key(p)]=p
    if names[p.name] ~= nil then names[p.name]=false else names[p.name]=p end
  end
  for _,p in ipairs(state.plugins) do curated[key(p)]=p end
  local out, tokens = {}, {}
  for word in (query or ''):lower():gmatch('%S+') do tokens[#tokens+1]=word end
  if #tokens > 0 or show_all then
    for _,p in ipairs(catalog) do
      local match, name = true, p.name:lower()
      for _,word in ipairs(tokens) do if not name:find(word,1,true) then match=false; break end end
      if match then out[#out+1]={name=p.name,ident=p.ident,catalog=p,saved=curated[key(p)]} end
    end
    table.sort(out,function(a,b) return a.name<b.name or (a.name==b.name and a.ident<b.ident) end)
  else
    for _,p in ipairs(state.plugins) do
      if in_category(state,p,category) then
        -- A unique exact display-name match supports Picker identifiers from a different host API.
        local resolved=exact[key(p)] or names[p.name] or nil
        out[#out+1]={name=p.name,ident=p.ident,saved=p,catalog=resolved}
      end
    end
    table.sort(out,function(a,b)
      local function order(row)
        local p=row.saved
        return (p.categoryOrder or {})[category or ''] or p.manualOrder or math.huge
      end
      if order(a)~=order(b) then return order(a)<order(b) end
      return a.name<b.name
    end)
  end
  return out
end
local function new_id(state, prefix)
  local used={}
  for _,list in ipairs({state.plugins,state.categories}) do for _,p in ipairs(list) do used[p.id]=true end end
  local n=1; while used[prefix..n] do n=n+1 end
  return prefix..n
end
function M.view_mode(query,show_all,adding)
  if adding then return 'add' end
  if show_all or (query or ''):match('%S') then return 'list' end
  return 'grid'
end
function M.children(state,parent)
  local out={}
  for _,c in ipairs(state.categories) do
    if (c.parentId or '')==(parent or '') then out[#out+1]=c end
  end
  table.sort(out,function(a,b)
    if (a.order or 0)~=(b.order or 0) then return (a.order or 0)<(b.order or 0) end
    return a.name<b.name
  end)
  return out
end
function M.category_path(state,id)
  local ids,out={},{}
  for _,c in ipairs(state.categories) do ids[c.id]=c end
  local c=ids[id]
  while c do table.insert(out,1,c.name); c=ids[c.parentId] end
  return table.concat(out,' / ')
end
function M.remember(state,fx)
  for _,p in ipairs(state.plugins) do if key(p)==key(fx) then return p end end
  local saved={id=new_id(state,'fx-'),name=fx.name,ident=fx.ident,categoryIds={},manualOrder=#state.plugins+1}
  state.plugins[#state.plugins+1]=saved
  return saved
end
function M.assign(state,fx,category)
  local found=false
  for _,c in ipairs(state.categories) do if c.id==category then found=true end end
  assert(found,'Unknown category')
  local saved=M.remember(state,fx)
  saved.categoryIds=saved.categoryIds or {}
  if not contains(saved.categoryIds,category) and not contains(saved.subcategoryIds,category) then
    saved.categoryIds[#saved.categoryIds+1]=category
  end
  return saved
end
function M.unassign(state,p,category)
  for _,field in ipairs({'categoryIds','subcategoryIds'}) do
    for i=#(p[field] or {}),1,-1 do if p[field][i]==category then table.remove(p[field],i) end end
  end
end
function M.add_category(state,name,parent)
  assert(type(name)=='string','Invalid category name')
  name=name:match('^%s*(.-)%s*$'); assert(#name>0 and #name<=100,'Category name must contain 1-100 bytes')
  if parent and parent~='' then
    local found=false; for _,c in ipairs(state.categories) do if c.id==parent then found=true end end
    assert(found,'Unknown parent')
  end
  local c={id=new_id(state,'cat-'),name=name,order=#state.categories,parentId=parent~='' and parent or nil}
  state.categories[#state.categories+1]=c; return c
end
return M
