local debugger = {}

local ui

function debugger.init(ui_)
   ui = ui_
end

local function make_tree(tv, tk, out, seen)
   out = out or {}
   seen = seen or {}
   if type(tv) == "table" then
      if seen[tv] then
         return nil
      end
      seen[tv] = true

      local r
      if tk then
         r = {}
         out[tk] = r
      else
         r = out
      end
      for k, v in pairs(tv) do
         make_tree(v, k, r, seen)
      end
   elseif type(tv) == "function" then
      if seen[tv] then
         return nil
      end
      seen[tv] = true

      out[tk] = tv
      local i = 1
      while true do
         local uk, uv = debug.getupvalue(tv, i)
         if uk == nil then
            break
         end
         if uv == nil then
            uv = "nil"
         end
         if uk ~= "_ENV" then
            make_tree(uv, "(upvalue) " .. uk, out, seen)
         end
         i = i + 1
      end
   else
      out[tk] = tv
   end
   seen[tv] = nil
   return out
end

function debugger.new(self)
   local cell = ui.above(self, "cell")
   local column = ui.above(self, "column")
   local arg = self.text:match("debug%s*([^%s]+)")
   local root = arg and package.loaded[arg] or _G
   cell:remove_n_children_below(1, 1)
   cell:add_child(ui.tree({
      name = "tree",
      scroll_by = 21,
      min_w = 492,
      max_w = 492,
      max_h = 400,
      spacing = 4,
      fill = 0x222222,
      border = 0x00ffff,
   }, make_tree(root)))
   column.data.add_cell(column, "?", " ? ")
end

return debugger
