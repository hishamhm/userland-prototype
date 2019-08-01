local flux = {}

local lexer = require("flux.lexer")

flux.tokenize = lexer.tokenize

local init_data

local weak_key = { __mode = "k" }
local weak_value = { __mode = "v" }

local modules = {
   default = {}
}
local names = setmetatable({}, weak_key)
local objects = setmetatable({}, weak_value)
local dependents = setmetatable({}, weak_key)
local modes = setmetatable({}, weak_key)

function flux.init(init_data_)
   init_data = init_data_
end

function flux.register(name, object)
   names[object] = name
   objects[name] = object
   return object
end

function flux.load_modules(dirname, basename)
   local lfs = require("lfs")

   for f in lfs.dir(dirname) do
      local name = f:match("^(.*)%.lua$")
      if name then
         local pok, mod = pcall(require, basename .. "." .. name)
         if pok and mod then
            local aliases = mod.init(init_data)
            modules[name] = mod
            if aliases then
               for _, alias in ipairs(aliases) do
                  modules[alias] = mod
               end
            end
         end
      end
   end
end

function flux.connect(a, b)
   dependents[a] = dependents[a] or setmetatable({}, weak_key)
   dependents[a][b] = true
end

function flux.disconnect(a, b)
   if dependents[a] then
      dependents[a][b] = nil
   end
end

function flux.get(name)
   return objects[name]
end

local function call(op, object, ...)
   local mode = modes[object]
   if mode and modules[mode] and modules[mode][op] then
      return modules[mode][op](object, ...)
   else
      return false
   end
end

function flux.eval(object, trigger_object, loop_ctrl)
   loop_ctrl = loop_ctrl or {}
   if loop_ctrl[object] then
      return
   end
   loop_ctrl[object] = true

   call("eval", object, trigger_object)

   if dependents[object] then
      for dep, _ in pairs(dependents[object]) do
         flux.eval(dep, object, loop_ctrl)
      end
   end
end

function flux.on_key(object, key, is_text, is_repeat)
   return call("on_key", object, key, is_text, is_repeat)
end

function flux.frame()
   for _, mod in pairs(modules) do
      if mod.frame then
         mod.frame()
      end
   end
end

function flux.set_mode(object, mode, creator_object)
   if modules[mode] then
      modes[object] = mode
      if call("enable", object, creator_object) then
         flux.eval(object)
      end
   end
   return object
end

function flux.get_mode(object)
   return modes[object] or "default"
end

return flux
