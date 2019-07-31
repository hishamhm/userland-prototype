local flux = {}

local init_data

function flux.init(init_data_)
   init_data = init_data_
end

function flux.load_modules(dirname, basename)
   local modules = {}

   local lfs = require("lfs")

   for f in lfs.dir(dirname) do
      local name = f:match("^(.*)%.lua$")
      if name then
         local pok, mod = pcall(require, basename .. "." .. name)
         if pok and mod then
            mod.init(init_data)
            modules[name] = mod
         end
      end
   end

   return modules
end


return flux
