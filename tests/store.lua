local root,work=arg[1],arg[2]
local S=dofile(root..'/src/store.lua')
local count=0
local function check(ok,name) assert(ok,name); count=count+1; print('PASS\t'..name) end
local library=assert(S.load_picker(work..'/source'))
check(#library.categories==25 and #library.plugins==121,'real Picker import preserves all categories/plugins')
local dest=work..'/library.json'
assert(S.save(dest,library))
local loaded=assert(S.load(dest))
check(#loaded.plugins==121 and loaded.plugins[1].ident==library.plugins[1].ident,'identifiers survive persistence')
loaded.categories[1].name='Test edit'; assert(S.save(dest,loaded))
check(assert(S.load(dest)).categories[1].name=='Test edit','second save replaces only own state')
check(assert(S.load(dest..'.bak')).categories[1].name~='Test edit','previous state backed up')
check(not S.save(work..'/missing/dest.json',loaded),'write failure is reported')
local f=assert(io.open(work..'/bad.json','w')); f:write('{broken'); f:close()
check(not S.load(work..'/bad.json'),'corrupt JSON refused')
print('DONE\t'..count)
