require("strict")
local LmodError          = LmodError
local ModulePath         = ModulePath
local assert             = assert
local capture            = capture
local cmdDir             = cmdDir
local concatTbl          = table.concat
local firstInPath        = firstInPath
local floor              = math.floor
local getenv             = os.getenv
local io                 = io
local ipairs             = ipairs
local loadfile           = loadfile
local loadstring         = loadstring
local myFileName         = myFileName
local next               = next
local os                 = os
local pairs              = pairs
local print              = print
local prtErr             = prtErr
local setmetatable       = setmetatable
local sort               = table.sort
local string             = string
local systemG            = _G
local tonumber           = tonumber
local tostring           = tostring
local type               = type
local expert             = expert
local removeEntry        = table.remove

require("TermWidth")
require("fileOps")
require("string_trim")
require("fillWords")
require("lastFileInDir")

ModuleName=""
local BeautifulTbl = require('BeautifulTbl')
local ColumnTable  = require('ColumnTable')
local Dbg          = require("Dbg")
local Default      = '(D)'
local InheritTmpl  = require("InheritTmpl")
local M            = {}
local MT           = MT
local ModuleStack  = require("ModuleStack")
local Spider       = require("Spider")
local abspath      = abspath
local extname      = extname
local hook         = require("Hook")
local isFile       = isFile
local lfs          = require('lfs')
local pathJoin     = pathJoin
local posix        = require("posix")

--module("Master")

s_master = {}

local function new(self,safe)
   local o = {}

   setmetatable(o,self)
   self.__index = self
   o.safe       = safe
   return o
end

function M.formModName(moduleName)
   local idx = moduleName:find('/') or 0
   idx = idx - 1
   local modName = moduleName:sub(1,idx)
   return modName
end



local searchTbl = {'.lua','', '/default', '/.version'}

local function followDefault(path)
   if (path == nil) then return nil end
   local dbg      = Dbg:dbg()
   dbg.start("followDefault(path=\"",path,"\")")
   local attr = lfs.symlinkattributes(path)
   local result = path
   if (attr == nil) then
      result = nil
   elseif (attr.mode == "link") then
      local rl = posix.readlink(path)
      local a  = {}
      local n  = 0
      for s in path:split("/") do
         n = n + 1
         a[n] = s or ""
      end

      a[n] = ""
      local i  = n
      for s in rl:split("/") do
         if (s == "..") then
            i = i - 1
         else
            a[i] = s
            i    = i + 1
         end
      end
      result = concatTbl(a,"/")
   end
   dbg.print("result: ",result,"\n")
   dbg.fini()
   return result
end


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
            result    = followDefault(result)
            dbg.print("(2) result: ",result, " f: ", f, "\n")
            t.default = 1
         elseif (found and v == '/.version' and ii == 1) then
            local vf = M.versionFile(result)
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
            dbg.print("i: ",tostring(i)," j: ", tostring(j),"\n")
            dbg.print("result: ",result,"\n")
            dbg.print("fn:     ",fn,"\n")
            dbg.print("extra:  ",extra,"\n")
            extra    = extra:gsub("%.lua$","")
            fullName = moduleName .. extra
            break
         end
      end

      dbg.print("found:", tostring(found), " fn: ",tostring(fn),"\n")

      ------------------------------------------------------------
      --  Search for "last" file in directory
      ------------------------------------------------------------

      if (not found and ii == 1) then
         t.default  = 1
         result = lastFileInDir(fn)
         if (result) then
            found = true
            local i, j = result:find(mpath,1,true)
            fullName   = result:sub(j+2)
            fullName   = fullName:gsub("%.lua$","")
         end
      end
      if (found) then break end
   end

   modName = M.formModName(fullName)

   t.fn          = result
   t.modFullName = fullName
   t.modName     = modName
   dbg.print("modName: ",modName," fn: ", result," modFullName: ", fullName," default: ",tostring(t.default),"\n")
   dbg.fini()
   return t
end

function loadModuleFile(t)
   local dbg    = Dbg:dbg()
   dbg.start("loadModuleFile")
   dbg.print("t.file: ",t.file,"\n")
   dbg.flush()

   systemG._MyFileName = t.file

   local myType = extname(t.file)
   local func
   local msg
   if (myType == ".lua") then
      if (isFile(t.file)) then
         func, msg = loadfile(t.file)
      end
   else
      local mt	  = MT:mt()
      local s     = concatTbl(mt:list("short","active"),":")
      local opt   = "-l \"" .. s .. "\""
      if (t.help) then
         opt      = t.help
      end
      local a     = {}
      a[#a + 1]	  = pathJoin(cmdDir(),"tcl2lua.tcl")
      a[#a + 1]	  = opt
      a[#a + 1]	  = t.file
      local cmd   = concatTbl(a," ")
      local s     = capture(cmd) 
      if (s) then
         func, msg   = loadstring(s)
      else
         func = nil
         msg  = "TCL modulefile was not read."
      end
   end

   if (func) then
      func()
   else
      if (t.reportErr) then
         local n = t.moduleName or ""
         LmodError("Unable to load module: ",n,"\n    ",msg,"\n")
      end
   end

   dbg.fini()
end

function M.master(self, safe)
   if (next(s_master) == nil) then
      MT       = systemG.MT
      s_master = new(self, safe)
   end
   return s_master
end

function M.safeToUpdate()
   return s_master.safe
end

function M.unload(...)
   local mStack = ModuleStack:moduleStack()
   local mt     = MT:mt()
   local dbg    = Dbg:dbg()
   local a      = {}
   dbg.start("Master:unload(",concatTbl({...},", "),")")

   local mcp_old = mcp

   mcp = MasterControl.build("unload")
   dbg.print("Setting mpc to ", mcp:name(),"\n")

   for _, moduleName in ipairs{...} do
      dbg.print("Trying to unload: ", moduleName, "\n")
      if (mt:haveSN(moduleName,"inactive")) then
         dbg.print("Removing inactive module: ", moduleName, "\n")
         mt:remove(moduleName)
         a[#a + 1] = true
      elseif (mt:haveSN(moduleName,"active")) then
         dbg.print("Mark ", moduleName, " as pending\n")
         mt:setStatus(moduleName,"pending")
         local f              = mt:fileName(moduleName)
         local fullModuleName = mt:fullName(moduleName)
         dbg.print("Master:unload: \"",fullModuleName,"\" from f: ",f,"\n")
         mt:beginOP()
         mStack:push(fullModuleName,f)
	 loadModuleFile{file=f,moduleName=moduleName,reportErr=false}
         mStack:pop()
         mt:endOP()
         dbg.print("calling mt:remove(\"",moduleName,"\")\n")
         mt:remove(moduleName)
         a[#a + 1] = true
      else
         a[#a + 1] = false
      end
   end
   if (M.safeToUpdate() and mt:safeToCheckZombies() and mStack:empty()) then
      M.reloadAll()
   end
   mcp = mcp_old
   dbg.print("Resetting mpc to ", mcp:name(),"\n")
   dbg.fini()
   return a
end

function M.versionFile(path)
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

local function access_find_module_file(moduleName)
   local mt = MT:mt()
   if ((shortName(moduleName) == moduleName) and
       (mt:haveSN(moduleName, "any"))) then
      local full = mt:fullName(moduleName) 
      return mt:fileName(moduleName), full or ""
   end
   local t    = find_module_file(moduleName)
   local full = t.modFullName or ""
   local fn   = t.fn
   return fn, full
end

function M.access(self, ...)
   local dbg    = Dbg:dbg()
   local mt     = MT:mt()
   local mStack = ModuleStack:moduleStack()
   local prtHdr = systemG.prtHdr
   local help   = nil
   local a      = {}
   local result, t
   io.stderr:write("\n")
   if (systemG.help ~= dbg.quiet) then help = "-h" end
   for _, moduleName in ipairs{...} do
      local fn, full   = access_find_module_file(moduleName)
      --io.stderr:write("full: ",full,"\n")
      systemG.ModuleFn   = fn
      systemG.ModuleName = full
      if (fn and isFile(fn)) then
         prtHdr()
         mStack:push(full, fn)
	 loadModuleFile{file=fn,help=help,moduleName=moduleName,reportErr=true}
         mStack:pop()
         io.stderr:write("\n")
      else
         a[#a+1] = moduleName
      end
   end

   if (#a > 0) then
      io.stderr:write("Failed to find the following module(s):  \"",concatTbl(a,"\", \""),"\" in your MODULEPATH\n")
      io.stderr:write("Try: \n",
       "    \"module spider ", concatTbl(a," "), "\"\n",
       "\nto see if the module(s) are available across all compilers and MPI implementations.\n")
   end
end


function M.load(...)
   local mStack = ModuleStack:moduleStack()
   local mt    = MT:mt()
   local dbg   = Dbg:dbg()
   local a     = {}

   dbg.start("Master:load(",concatTbl({...},", "),")")

   a   = {}
   for _,moduleName in ipairs{...} do
      local loaded  = false
      local t	    = find_module_file(moduleName)
      local fn      = t.fn
      if (mt:haveSN(moduleName,"active") and fn  ~= mt:fileName(moduleName)) then
         dbg.print("Master:load reload module: \"",moduleName,"\" as it is already loaded\n")
         local mcp_old = mcp
         mcp           = MCP
         mcp:unload(moduleName)
         local aa = mcp:load(moduleName)
         mcp           = mcp_old
         loaded = aa[1]
      elseif (fn) then
         dbg.print("Master:loading: \"",moduleName,"\" from f: \"",fn,"\"\n")
         mt:add(t, "pending")
	 mt:beginOP()
         mStack:push(t.modFullName,fn)
	 loadModuleFile{file=fn,moduleName=moduleName,reportErr=true}
         t.mType = mStack:moduleType()
         mStack:pop()
	 mt:endOP()
         dbg.print("Making ", t.modName, " active\n")
         mt:setStatus(t.modName,"active")
         mt:set_mType(t.modName,t.mType)
         dbg.print("Marked: ",t.modFullName," as loaded\n")
         loaded = true
         hook.apply("load",t)
      end
      a[#a+1] = loaded
   end
   if (M.safeToUpdate() and mt:safeToCheckZombies() and mStack:empty()) then
      dbg.print("Master:load calling reloadAll()\n")
      M.reloadAll()
   end
   dbg.fini()
   return a
end

function M.fakeload(...)
   local a   = {}
   local mt  = MT:mt()
   local dbg = Dbg:dbg()
   dbg.start("Master:fakeload(",concatTbl({...},", "),")")

   for _, moduleName in ipairs{...} do
      local loaded = false
      local t      = find_module_file(moduleName)
      local fn     = t.fn
      if (fn) then
         t.mType = "m"
         mt:add(t,"active")
         loaded = true
      end
      a[#a+1] = loaded
   end
end         


function M.reloadAll()
   local mt   = MT:mt()
   local dbg  = Dbg:dbg()
   dbg.start("Master:reloadAll()")


   local mcp_old = mcp
   mcp = MCP
   dbg.print("Setting mpc to ", mcp:name(),"\n")

   local same = true
   local a    = mt:list("userName","any")
   for _, v in ipairs(a) do
      if (mt:have(v,"active")) then
         local fullName = mt:fullName(v)
         local t        = find_module_file(fullName)
         local fn       = mt:fileName(v)
         if (t.fn ~= fn) then
            dbg.print("Master:reloadAll t.fn: \"",t.fn or "nil","\"",
                      " mt:fileName(v): \"",fn or "nil","\"\n")
            dbg.print("Master:reloadAll Unloading module: \"",v,"\"\n")
            mcp:unloadsys(v)
            dbg.print("Master:reloadAll Loading module: \"",fullName or "nil","\"\n")
            local loadA = mcp:load(fullName)
            dbg.print("Master:reloadAll: fn: \"",fn or "nil",
                      "\" mt:fileName(v): \"", mt:fileName(v) or "nil","\"\n")
            if (loadA[1] and fn ~= mt:fileName(v)) then
               same = false
               dbg.print("Master:reloadAll module: ",fullName," marked as reloaded\n")
            end
         end
      else
         local fn       = mt:fileName(v)
         local fullName = mt:fullName(v)
         dbg.print("Master:reloadAll Loading module: \"",fullName or "nil","\"\n")
         local aa = mcp:load(fullName)
         if (aa[1] and fn ~= mt:fileName(v)) then
            dbg.print("Master:reloadAll module: ",fullName," marked as reloaded\n")
         end
         same = not aa[1]
      end
   end
   for _, v in ipairs(a) do
      if (not mt:have(v,"active")) then
         local t = { modFullName = v, modName = shortName(v)}
         dbg.print("Master:reloadAll module: ",v," marked as inactive\n")
         mt:add(t, "inactive")
      end
   end

   mcp = mcp_old
   dbg.print("Setting mpc to ", mcp:name(),"\n")
   dbg.fini()
   return same
end

function M.inheritModule()
   local dbg     = Dbg:dbg()
   dbg.start("Master:inherit()")

   local mStack  = ModuleStack:moduleStack()
   local myFn    = mStack:fileName()
   local mName   = mStack:moduleName()
   local inhTmpl = InheritTmpl:inheritTmpl()

   dbg.print("myFn:  ", myFn,"\n")
   dbg.print("mName: ", mName,"\n")

   
   local t = inhTmpl.find_module_file(mName,myFn)
   dbg.print("fn: ", tostring(t.fn),"\n")
   if (t.fn == nil) then
      LmodError("Failed to inherit: ",mName,"\n")
   else
      mStack:push(mName,t.fn)
      loadModuleFile{file=t.fn,moduleName=mName, reportErr=true}
      mStack:pop()
   end
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


local function prtDirName(width,path,a)
   local len     = path:len()
   local lcount  = floor((width - (len + 2))/2)
   local rcount  = width - lcount - len - 2
   a[#a+1] = "\n"
   a[#a+1] = string.rep("-",lcount)
   a[#a+1] = " "
   a[#a+1] = path
   a[#a+1] = " "
   a[#a+1] = string.rep("-",rcount)
   a[#a+1] = "\n"
end


local function findDefault(mpath, path, prefix)
   local dbg      = Dbg:dbg()
   local mt       = MT:mt()
   local localDir = true
   dbg.start("Master.findDefault(",mpath,", ", path,", ",prefix,")")

   local i,j = path:find(mpath)
   --dbg.print("i: ",tostring(i)," j: ", tostring(j)," path:len(): ",path:len(), "\n")
   if (i and j + 1 < path:len()) then
      local mname = path:sub(j+2)
      i = mname:find("/")
      if (i) then
         mname = mname:sub(1,i-1)
      end
      local pathA  = mt:locationTbl(mname)
      local mpath2 = pathA[1].mpath
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
         local vf = M.versionFile(vFn)
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
      local result, count = lastFileInDir(path)
      if (count > 1) then
         default = result
      end
   end
   if (default) then
      default = abspath(default, localDir)
   end
   dbg.print("(4) default: \"",tostring(default),"\"\n")

   dbg.fini()
   return default
end


local function availDir(searchA, mpath, path, prefix, dbT, a, legendT)
   local dbg    = Dbg:dbg()
   dbg.start("Master.availDir(searchA=(",concatTbl(searchA,", "),"), mpath=\"",mpath,"\", ",
             "path=\"",path,"\", prefix=\"",prefix,"\")")
   local sCount  = #searchA
   local attr    = lfs.attributes(path)
   local mt      = MT:mt()
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
	 attr = lfs.attributes(f) or {}
         dbg.print("file: ",file," f: ",f," attr.mode: ", attr.mode,"\n")
         local readable = posix.access(f,"r")
	 if (readable and (attr.mode == 'file' or attr.mode == 'link') and (file ~= "default")) then
            local dflt = ""
            local n    = prefix .. file
            n = n:gsub("%.lua$","")
            local found = false
            if (sCount == 0) then
               found = true
            else
               for _,v in ipairs(searchA) do
                  if (n:find(v,1,true) or n:find(v)) then
                     found = true
                  end
               end
            end

            if (found) then
               if (defaultModuleName == abspath(f,localDir)) then
                  dflt = Default
                  legendT[Default] = "Default Module"
               end
               local aa      = {}
               local propT   = {}
               local sn      = shortName(n)
               local entry   = dbT[sn]
               if (entry) then
                  dbg.print("Found dbT[sn]\n")
                  if (entry[f]) then
                     propT =  entry[f].propT or {}
                  end
               else
                  dbg.print("Did not find dbT[sn]\n")
               end

               local resultA = colorizePropA("short",n, propT, legendT)
               aa[#aa + 1] = '  '
               for i = 1,#resultA do
                  aa[#aa+1] = resultA[i]
               end
               aa[#aa + 1] = dflt
               a[#a + 1]   = aa
            end
         elseif (attr.mode == 'directory') then
            availDir(searchA,mpath, f,prefix .. file..'/', dbT, a, legendT)
	 end
      end
   end
   dbg.fini()
end

function M.avail(searchA)
   local dbg    = Dbg:dbg()
   dbg.start("Master.avail(",concatTbl(searchA,", "),")")
   local mpathA = MT:mt():module_pathA()
   local width  = TermWidth()

   local mcp_old = mcp
   mcp           = MasterControl.build("spider")
   dbg.print("Setting mpc to ", mcp:name(),"\n")
   local moduleT = getModuleT()
   mcp           = mcp_old
   dbg.print("Resetting mpc to ", mcp:name(),"\n")
   local dbT     = {}
   Spider.buildSpiderDB({"default"}, moduleT, dbT)

   local legendT = {}

   local aa = {}

   for _,path in ipairs(mpathA) do
      local a = {}
      availDir(searchA, path, path, '', dbT, a, legendT)
      if (next(a)) then
         local b = {}
         for i = 1, #a do
            local fn = a[i][2]:gsub("\027[^m]+m","")
            local d,v = splitFileName(fn)
            local name 
            if (d == "./") then
               name = v
            elseif (v:sub(1,1):find("%d")) then
               name = pathJoin(d,concatTbl(parseVersion(v)))
            else
               name = pathJoin(d,v)
            end

            b[i] = { name, i}
         end

         prtDirName(width, path,aa)
         sort(b, function(a,b) return a[1] < b[1] end )

         local bb = {}
         for i = 1, #b do
            local j = b[i][2]
            bb[i] = a[j]
         end

         local ct  = ColumnTable:new{tbl=bb,gap=1, len=length}
         aa[#aa+1] = ct:build_tbl()
         aa[#aa+1] = "\n"
      end
   end

   if (next(legendT)) then
      local term_width = TermWidth()
      aa[#aa+1] = "\n  Where:\n"
      local a = {}
      for k, v in pairsByKeys(legendT) do
         a[#a+1] = { "   " .. k ..":", v}
      end
      local bt = BeautifulTbl:new{tbl=a, column = term_width-1, len=length}
      aa[#aa+1] = bt:build_tbl()
      aa[#aa+1] = "\n"
   end
   

   if (not expert()) then
      local a = fillWords("","Use \"module spider\" to find all possible modules.",width)
      local b = fillWords("","Use \"module keyword key1 key2 ...\" to search for all " ..
                             "possible modules matching any of the \"keys\".",width)
      aa[#aa+1] = "\n"
      aa[#aa+1] = a
      aa[#aa+1] = "\n"
      aa[#aa+1] = b
      aa[#aa+1] = "\n\n"
   end
   pcall(pager,io.stderr,concatTbl(aa,""))
   dbg.fini()
end

local function spanOneModule(path, name, nameA, fileType, keyA)
   local dbg    = Dbg:dbg()
   local mStack = ModuleStack:moduleStack()
   dbg.start("spanOneModule(path=\"",path,"\", name=\"",name,
             "\", nameA=(",concatTbl(nameA,","),"), fileType=\"",fileType,
             "\", keyA=(",concatTbl(keyA,","),"))")
   if (fileType == "file" and posix.access(path,"r")) then
      for _,v in ipairs(keyA) do
	 nameA[#nameA+1] = name
	 local n = concatTbl(nameA,"/")
	 ModuleName = n
	 systemG.whatis  = function(msg, v)
                              local searchString = v
                              return function(msg)
                                 local nm     = ModuleName or ""
                                 local l      = nm:len()
                                 local nblnks
                                 if (l < 20) then
                                    nblnks = 20 - l
                                 else
                                    nblnks = 2
                                 end
                                 local prefix = nm .. string.rep(" ",nblnks) .. ": "
                                 if (msg:find(searchString,1,true)) then
                                    io.stderr:write(prefix, msg, "\n")
                                 end
                              end
                           end
         mStack:push(ModuleName,path)
	 loadModuleFile{file=path,moduleName=ModuleName, reportErr=true}
         mStack:pop()
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
               M.spanOneModule(f, file, nameA, attr.mode,keyA)
               removeEntry(nameA,#nameA)
            end
         end
      end
   end
   dbg.fini()
end


function M.spanAll(self, keyA)
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
                  M.spanOneModule(f, file, nameA, attr.mode, keyA)
               end
	    end
         end
      end
   end
   dbg.fini()
end

return M
