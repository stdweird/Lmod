-- $Id: Master.lua 694 2011-01-28 20:04:24Z mclay $ --
require("strict")
Master = { }
local Load         = Load
local LoadTbl      = LoadTbl
local ModulePath   = ModulePath
local UnLoad       = UnLoad
local UnLoadSys    = UnLoadSys
local UnLoadTbl    = UnLoadTbl
local assert       = assert
local capture      = capture
local cmdDir       = cmdDir
local concatTbl    = table.concat
local firstInPath  = firstInPath
local floor        = math.floor
local getenv       = os.getenv
local io           = io
local ipairs       = ipairs
local loadfile     = loadfile
local loadstring   = loadstring
local next         = next
local os           = os
local pairs        = pairs
local print        = print
local prtErr       = prtErr
local setmetatable = setmetatable
local sort         = table.sort
local string       = string
local systemG      = _G
local tonumber     = tonumber
local tostring     = tostring
local type         = type
local unloadsys    = unloadsys
local expert       = expert
local removeEntry  = table.remove

require('lfs')
require('ColumnTable')
require('MT')
require("fileOps")
require("Dbg")
require("string_trim")

ModuleName=""
local abspath      = abspath
local pathJoin     = pathJoin
local extname      = extname
local MT           = MT
local lfs          = lfs
local ColumnTable  = ColumnTable
local Dbg          = Dbg
local isFile       = isFile
local posix        = require("posix")
local ModuleStack  = require("ModuleStack")

module("Master")

s_master = {}

local function new(self,safe)
   local o = {}

   setmetatable(o,self)
   self.__index = self
   o.safe       = safe
   o.reloadT    = {}
   return o
end

function formModName(moduleName)
   local idx = moduleName:find('/') or 0
   idx = idx - 1
   local modName = moduleName:sub(1,idx)
   return modName
end

count = 0

local searchTbl = {'.lua','', '/default', '/.version'}

local function find_module_file(moduleName)
   local dbg      = Dbg:dbg()
   dbg.start("find_module_file(",moduleName,")")

   local t        = { fn = nil, modFullName = nil, modName = nil, default = 0, hash = 0}
   local mt       = MT:mt()
   local fullName = moduleName
   local idx      = moduleName:find('/')
   local localDir = true
   local key, extra, modName
   if (idx == nil) then
      key   = moduleName
      extra = ''
   else
      key   = moduleName:sub(1,idx-1)
      extra = moduleName:sub(idx)
   end

   local pathA = mt:locationTbl(key)

   if (pathA == nil or #pathA == 0) then
      dbg.fini()
      return t
   end
   local fn, result

   for ii, vv in ipairs(pathA) do
      t.default = 0
      local mpath  = vv.mpath
      fn           = pathJoin(vv.file, extra)
      result = nil
      local found  = false
      for _,v in ipairs(searchTbl) do
         local f    = fn .. v
         local attr = lfs.attributes(f)
         local readable = posix.access(f,"r")
         dbg.print('(1) fn: ',fn," v: ",v," f: ",f,"\n")

         if (readable and attr and attr.mode == 'file') then
            result    = f
            found     = true
         end
         if (found and v == '/default' and ii == 1) then
            result    = abspath(result, localDir)
            t.default = 1
         elseif (found and v == '/.version' and ii == 1) then
            local vf = versionFile(result)
            if (vf) then
               t         = find_module_file(pathJoin(key,vf))
               t.default = 1
               result    = t.fn
            end
         end
         if (found) then
            local i,j = result:find(fn,1,true)
            if (i and j) then
               extra = result:sub(1,i-1) .. result:sub(j+1)
            else
               extra = result
            end
            extra    = extra:gsub(".lua$","")
            fullName = moduleName .. extra
            break
         end
      end

      dbg.print("found:", tostring(found), " fn: ",fn,"\n")

      ------------------------------------------------------------
      --  Search for "last" file in directory
      ------------------------------------------------------------

      if (not found and ii == 1) then
         t.default  = 1
         if (ii > 1) then
            t.default  = 0
         end
            
         fullName   = ''
         local mn   = nil
         local attr = lfs.attributes(fn)
         if (attr and attr.mode == 'directory' and posix.access(fn,"x")) then
            local last = ''
            found      = true   
            for file in lfs.dir(fn) do
               local f = pathJoin(fn, file)
               dbg.print("(2) fn: ",fn," file: ",file," f: ",f,"\n")
               attr = lfs.attributes(f)
               local readable = posix.access(f,"r")
               if (readable and file:sub(1,1) ~= "." and attr.mode == 'file' and f > last and file:sub(-1,-1) ~= '~') then
                  last	= f
               end
            end
            if (last ~= '') then
               result      = last
               local i, j  = result:find(mpath,1,true)
               fullName    = result:sub(j+2)
               fullName    = fullName:gsub(".lua$","")
            end
         end
      end
      if (found) then break end
   end

   modName = formModName(fullName)

   t.fn          = result
   t.modFullName = fullName
   t.modName     = modName
   dbg.print("modName: ",modName," fn: ", result," modFullName: ", fullName," default: ",tostring(t.default),"\n")
   dbg.fini()
   return t
end

local function loadModuleFile(t)
   local dbg    = Dbg:dbg()
   dbg.start("loadModuleFile")
   dbg.flush()

   systemG._MyFileName = t.file

   local myType = extname(t.file)
   if (myType == ".lua") then
      if (isFile(t.file)) then
         assert(loadfile(t.file))()
      end
   else
      local mt	  = MT:mt()
      local opt   = "-l \"" .. mt:loadActiveList() .. "\""
      if (t.help) then
         opt      = t.help
      end
      local a     = {}
      a[#a + 1]	  = pathJoin(cmdDir(),"tcl2lua.tcl")
      a[#a + 1]	  = opt
      a[#a + 1]	  = t.file
      local cmd   = concatTbl(a," ")
      local s     = capture(cmd)
      assert(loadstring(s))()
   end
   dbg.fini()
end

function master(self, safe)
   if (next(s_master) == nil) then
      s_master = new(self, safe)
   end
   return s_master
end

function safeToUpdate()
   return s_master.safe
end

function unload(...)
   local mt     = MT:mt()
   local dbg    = Dbg:dbg()
   local a      = {}
   local prevT  = { load = systemG.load, unload = systemG.unload}
   for _,v in ipairs{...} do
      a[#a+1] = v
   end
   dbg.start("Master:unload(",concatTbl(a,", "),")")

   for k in pairs(UnLoadTbl) do
      if ( prevT[k] == nil and systemG[k] ~= UnLoadTbl[k]) then
         prevT[k]   = systemG[k]
      end
      systemG[k] = UnLoadTbl[k]
   end

   a = {}

   for _, moduleName in ipairs{...} do
      if (mt:haveModuleAnyActive(moduleName)) then
         local f = mt:fileNameActive(moduleName)
         dbg.print("Master:unload: \"",moduleName,"\" from f: ",f,"\n")
         mt:beginOP()
         mt:removeActive(moduleName)
	 loadModuleFile{file=f}
         mt:endOP()
         a[#a + 1] = true
      else
         a[#a + 1] = false
      end
   end
   if (safeToUpdate() and mt:safeToCheckZombies()) then
      reloadAll()
   end
   for k in pairs(prevT) do
      systemG[k] = prevT[k]
   end
   dbg.fini()
   return a
end

function versionFile(path)
   local dbg     = Dbg:dbg()
   dbg.start("versionFile(",path,")")
   local f       = io.open(path,"r")
   if (not f)                        then
      dbg.print("could not find: ",path,"\n")
      dbg.fini()
      return nil
   end
   local s       = f:read("*line")
   f:close()
   if (not s:find("^#%%Module"))      then
      dbg.print("could not find: #%Module\n")
      dbg.fini()
      return nil
   end
   local cmd = pathJoin(cmdDir(),"ModulesVersion.tcl") .. " " .. path
   return capture(cmd):trim()
end

function access(self, ...)
   local dbg    = Dbg:dbg()
   local mt     = MT:mt()
   local prtHdr = systemG.prtHdr
   local help   = nil
   local result, t
   io.stderr:write("\n")
   if (systemG.help ~= dbg.quiet) then help = "-h" end
   for _, moduleName in ipairs{...} do
      local fn
      if (isFile(moduleName)) then
         fn = moduleName
      else
         fn = moduleName .. ".lua"
         if (not isFile(fn)) then
            t                  = find_module_file(moduleName)
            fn                 = t.fn
            systemG.ModuleName = t.modFullName
         end
      end
      systemG.ModuleFn   = fn
      if (fn) then
         prtHdr()
	 loadModuleFile{file=fn,help=help}
         io.stderr:write("\n")
      end
   end
end

function load(...)
   local mStack = ModuleStack:moduleStack()
   local mt    = MT:mt()
   local dbg   = Dbg:dbg()
   local a     = {}

   dbg.start("Master:load(",concatTbl({...},", "),")")

   for k in pairs(LoadTbl) do
      systemG[k] = LoadTbl[k]
   end

   a   = {}
   for _,moduleName in ipairs{...} do
      local loaded  = false
      local t	    = find_module_file(moduleName)
      local fn      = t.fn
      if (mt:haveModuleAnyActive(moduleName) and fn  ~= mt:fileNameActive(moduleName)) then
         dbg.print("Master:load reload module: \"",moduleName,"\" as it is already loaded\n")
         UnLoad(moduleName)
         local aa = Load(moduleName)
         loaded = aa[1]
      elseif (fn) then
         dbg.print("Master:loading: \"",moduleName,"\" from f: \"",fn,"\"\n")
	 mt:beginOP()
         mStack:push(moduleName)
	 loadModuleFile{file=fn}
         t.mType = mStack:moduleType()
         mStack:pop()
	 mt:endOP()
         mt:addActive(t)
         mt:addTotal(t)
         loaded = true
      elseif (not mt:haveModuleTotal(moduleName)) then
         dbg.warning("Failed to load: ",moduleName,"\n")
      end
      a[#a+1] = loaded
   end
   if (safeToUpdate() and mt:safeToCheckZombies()) then
      dbg.print("Master:load calling reloadAll()\n")
      reloadAll()
   end
   dbg.fini()
   return a
end

function fakeload(...)
   local mt  = MT:mt()
   local dbg = Dbg:dbg()
   dbg.start("Master:fakeload(",concatTbl({...},", "),")")
   a = {}

   for _, moduleName in ipairs{...} do
      local loaded = false
      local t      = find_module_file(moduleName)
      local fn     = t.fn
      if (fn) then
         t.mType = "m"
         mt:addActive(t)
         mt:addTotal(t)
         loaded = true
      end
      a[#a+1] = loaded
   end
end         


function reloadAll()
   local mt   = MT:mt()
   local dbg  = Dbg:dbg()
   dbg.start("Master:reloadAll()")

   local same = true
   local a    = mt:listTotal()
   for _, v in ipairs(a) do
      if (mt:haveModuleActive(v)) then
         local fullName = mt:modFullNameTotal(v)
         local t        = find_module_file(fullName)
         local fn       = mt:fileNameTotal(v)
         if (t.fn ~= fn) then
            dbg.print("Master:reloadAll t.fn: \"",t.fn or "nil","\"",
                      " mt:fileNameTotal(v): \"",fn or "nil","\"\n")
            dbg.print("Master:reloadAll Unloading module: \"",v,"\"\n")
            UnLoadSys(v)
            dbg.print("Master:reloadAll Loading module: \"",fullName or "nil","\"\n")
            local loadA = Load(fullName)
            dbg.print("Master:reloadAll: fn: \"",fn or "nil",
                      "\" mt:fileNameTotal(v): \"", mt:fileNameTotal(v) or "nil","\"\n")
            if (loadA[1] and fn ~= mt:fileNameTotal(v)) then
               same = false
               s_master.reloadT[fullName] = 1
               dbg.print("Master:reloadAll module: ",fullName," marked as reloaded\n")
            end
         end
      else
         local fn       = mt:fileNameTotal(v)
         local fullName = mt:modFullNameTotal(v)
         dbg.print("Master:reloadAll Loading module: \"",fullName or "nil","\"\n")
         local aa = Load(fullName)
         if (aa[1] and fn ~= mt:fileNameTotal(v)) then
            s_master.reloadT[fullName] = 1
            dbg.print("Master:reloadAll module: ",fullName," marked as reloaded\n")
         end
         same = not aa[1]
      end
   end
   dbg.fini()
   return same
end

function reloadClear(self,name)
   local dbg  = Dbg:dbg()
   dbg.start("Master:reloadClear()")
   dbg.print("removing \"",name,"\" from reload table\n")
   self.reloadT[name] = nil
   dbg.fini()
end

local function dirname(f)
   local result = './'
   for w in f:gmatch('.*/') do
      result = w
      break
   end
   return result
end


function prtReloadT(self)
   if (next(self.reloadT) == nil or expert()) then return end
   local t = self.reloadT
   local a = {}
   local i = 0
   for name in pairs(t) do
      i    = i + 1
      a[i] = "  " .. i .. ") " .. name
   end
   if (i > 0) then
      io.stderr:write("Due to MODULEPATH changes the follow modules have been reloaded:\n")
      ct = ColumnTable:new{tbl=a,prt=prtErr}
      ct:print_tbl()
   end
end

local function prtDirName(width,path)
   local len     = path:len()
   local lcount  = floor((width - (len + 2))/2)
   local rcount  = width - lcount - len - 2
   io.stderr:write("\n",string.rep("-",lcount)," ",path,
                   " ", string.rep("-",rcount),"\n")
end


local function findDefault(mpath, path, prefix)
   local dbg     = Dbg:dbg()
   local mt      = MT:mt()
   dbg.start("Master.findDefault(",mpath,", ", path,", ",prefix,")")

   local i,j = path:find(mpath)
   --dbg.print("i: ",tostring(i)," j: ", tostring(j)," path:len(): ",path:len(), "\n")
   if (i and j + 1 < path:len()) then
      local mname = path:sub(j+2)
      i = mname:find("/")
      if (i) then
         mname = mname:sub(1,i-1)
      end
      local pathA = mt:locationTbl(mname)
      mpath2 = pathA[1].mpath
      --dbg.print("mname: ", mname, " mpath: ", mpath, " mpath2: ",mpath2,"\n")

      if (mpath ~= mpath2) then
         dbg.print("(1)default: \"nil\"\n")
         dbg.fini()
         return nil
      end
   end

   --dbg.print("abspath(\"", tostring(path .. "/default"), ", \"",tostring(localDir),"\")\n")
   local default = abspath(path .. "/default", localDir)
   --dbg.print("(2) default: ", tostring(default), "\n")
   if (default == nil) then
      local vFn = abspath(pathJoin(path,".version"), localDir)
      if (isFile(vFn)) then
         local vf = versionFile(vFn)
         if (vf) then
            local f = pathJoin(path,vf)
            default = abspath(f,localDir)
            --dbg.print("(1) f: ",f," default: ", tostring(default), "\n")
            if (default == nil) then
               local fn = vf .. ".lua"
               local f  = pathJoin(path,fn)
               default  = abspath(f,localDir)
               dbg.print("(2) f: ",f," default: ", tostring(default), "\n")
            end
            --dbg.print("(3) default: ", tostring(default), "\n")
         end
      end
   end
   if (default == nil and prefix ~= "") then
      local attr  = lfs.attributes(path)
      local count = 0
      if (attr and attr.mode == "directory" and posix.access(path,"rx")) then
         local last = ""
         for file in lfs.dir(path) do
            local f = pathJoin(path, file)
            attr = lfs.attributes(f)
            local readable = posix.access(f,"r")
            if (readable and file:sub(1,1) ~= "." and attr and attr.mode == 'file' and file:sub(-1,-1) ~= '~') then
               count    = count + 1
               if (f > last) then
                  last	= f
               end
            end
         end
         if (last ~= "" and count > 1) then
            default = last
         end
      end
   end
   if (default) then
      default = abspath(default, localDir)
   end
   dbg.print("(4) default: \"",tostring(default),"\"\n")

   dbg.fini()
   return default
end


local function availDir(searchA, mpath, path, prefix, a)
   local dbg    = Dbg:dbg()
   dbg.start("Master.availDir(searchA=(",concatTbl(searchA,", "),"), mpath=\"",mpath,"\", ",
             "path=\"",path,"\", prefix=\"",prefix,"\", a=(",concatTbl(a,", "),") )")
   local sCount = #searchA
   local attr = lfs.attributes(path)
   if (not attr) then
      dbg.fini()
      return
   end
   assert(type(attr) == "table")
   if ( attr.mode ~= "directory" or not posix.access(path,"x")) then
      dbg.fini()
      return
   end


   -- Check for default first
   local defaultModuleName = findDefault(mpath, path, prefix)
   local localDir          = true
   dbg.print("defaultModuleName: \"",tostring(defaultModuleName),"\"\n")

   for file in lfs.dir(path) do
      if (file:sub(1,1) ~= "." and not file ~= "CVS" and file:sub(-1,-1) ~= '~') then
         local f = pathJoin(path, file)
	 attr = lfs.symlinkattributes(f) or {}
         dbg.print("file: ",file," f: ",f," attr.mode: ", attr.mode,"\n")
         local readable = posix.access(f,"r")
	 if (readable and (attr.mode == 'file' or attr.mode == 'link') and (file ~= "default")) then
            local n = prefix .. file
            n = n:gsub(".lua","")
            if (defaultModuleName == abspath(f,localDir)) then
               n = n .. ' (default)'
            end
            if (sCount == 0) then
               a[#a + 1 ] = '  ' .. n .. '  '
            else
               for _,v in ipairs(searchA) do
                  if (n:find(v)) then
                     a[#a + 1 ] = '  ' .. n .. '  '
                     break
                  end
               end
            end
         elseif (attr.mode == 'directory') then
            availDir(searchA,mpath, f,prefix .. file..'/',a)
	 end
      end
   end
   dbg.fini()
end

function avail(searchA)
   local dbg    = Dbg:dbg()
   dbg.start("Master.avail(",concatTbl(searchA,", "),")")
   local mpathA = MT:mt():module_pathA()
   local width  = 80
   if (getenv("TERM")) then
      width  = tonumber(capture("tput cols"))
   end
   for _,path in ipairs(mpathA) do
      local a = {}
      availDir(searchA, path, path, '', a)
      if (next(a)) then
         prtDirName(width, path)
         sort(a)
         local ct  = ColumnTable:new{tbl=a,prt=prtErr}
         ct:print_tbl()
      end
   end
   io.stderr:write("\n")
   dbg.fini()
end

local function spanOneModule(path, name, nameA, fileType, keyA)
   local dbg    = Dbg:dbg()
   dbg.start("spanOneModule(path=\"",path,"\", name=\"",name,"\", nameA=(",concatTbl(nameA,","),"), fileType=\"",fileType,"\", keyA=(",concatTbl(keyA,","),"))")
   if (fileType == "file" and posix.access(path,"r")) then
      for _,v in ipairs(keyA) do
	 SearchString = v
	 nameA[#nameA+1] = name
	 local n = concatTbl(nameA,"/")
	 ModuleName = n
	 systemG.whatis  = function(msg)
			      local nm     = ModuleName or ""
			      local l      = nm:len()
			      local nblnks
			      if (l < 20) then
				 nblnks = 20 - l
			      else
				 nblnks = 2
			      end
			      local prefix = nm .. string.rep(" ",nblnks) .. ": "
			      if (msg:find(SearchString,1,true)) then
				 io.stderr:write(prefix, msg, "\n")
			      end
			   end
	 loadModuleFile{file=path}
      end
   elseif (fileType == "directory" and posix.access(path,"x")) then
      --io.stderr:write("dir: ",path," name: ", name, "\n")
      for file in lfs.dir(path) do
         if (file:sub(1,1) ~= "." and not file ~= "CVS" and file:sub(-1,-1) ~= '~') then
            local f = pathJoin(path, file)
            local readable = posix.access(f,"r")
            if (readable) then
               attr = lfs.symlinkattributes(f)
               if (attr.mode == "directory") then
                  nameA[#nameA+1] = file
               end
               --local n = concatTbl(nameA,"/")
               --io.stderr:write("file: ",file," f: ",f," mode: ",attr.mode, " n: ", n, "\n")
               spanOneModule(f, file, nameA, attr.mode,keyA)
               removeEntry(nameA,#nameA)
            end
         end
      end
   end
   dbg.fini()
end


function spanAll(self, keyA)
   local dbg    = Dbg:dbg()
   dbg.start("Master:spanAll(keyA=(",concatTbl(keyA,","),"))")
   mpathA = MT:mt():module_pathA()
   for _, path in ipairs(mpathA) do
      local attr = lfs.attributes(path)
      if (attr and attr.mode == "directory" and posix.access(path,"x")) then
         for file in lfs.dir(path) do
	    --io.stderr:write("(1) spanAll: file: ",file,"\n")
            if (file:sub(1,1) ~= "." and not file ~= "CVS" and file:sub(-1,-1) ~= '~') then
               local f = pathJoin(path, file)
               local readable = posix.access(f,"r")
               if (readable) then
                  attr = lfs.attributes(f)
                  local nameA = {}
                  if (attr.mode == "directory") then
                     nameA[#nameA+1] = file
                  end
                  --local n = concatTbl(nameA,"/")
                  --io.stderr:write("(2) spanAll: file: ",file," f: ",f," mode: ", attr.mode," n: ",n,"\n")
                  spanOneModule(f, file, nameA, attr.mode, keyA)
               end
	    end
         end
      end
   end
   dbg.fini()
end