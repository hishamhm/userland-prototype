#!./lua

local ui = require("ui")
local flux = require("flux")

ui.init()

flux.init(ui)

flux.load_modules("user/", "user")

local columns = ui.in_root(ui.hbox({ name = "columns", spacing = 4, scroll_by = 20 }))
local add_column

local function down(self)
   local cell = ui.above(self, "cell")
   if not cell then
      return
   end
   local column = ui.above(cell, "column")
   local next = ui.next_sibling(cell)
   if not next then
      local prompt = ui.below(cell, "prompt")
      if prompt.text == "" then
         return
      end
      next = column.data.add_cell(column)
      flux.set_mode(next, flux.get_mode(cell), cell)
   end
   ui.set_focus(next)
end

local function right(self)
   local cell = ui.above(self, "cell")
   if not cell then
      return
   end
   local column = ui.above(cell, "column")
   local nextcol = ui.next_sibling(column)
   local next
   if nextcol then
      next = nextcol.children[1] -- FIXME cell visually to the right
   else
      local prompt = ui.below(cell, "prompt")
      if prompt.text == "" then
         return
      end
      nextcol = add_column()
      next = nextcol.data.add_cell(nextcol)
      flux.set_mode(next, flux.get_mode(cell), cell)
   end
   if next then
      ui.set_focus(next)
   end
end

local function prompt_on_key(self, key, is_text, is_repeat)
   local cell = ui.above(self, "cell")
   if key == "Ctrl backspace" then
      flux.set_mode(cell, "default")
      ui.below(cell, "prompt"):set("")
      ui.below(cell, "context"):set("?")
      cell:remove_n_children_at(nil, 2)
      cell.border = 0x00cccc
      cell.focus_border = 0x77ffff
      self:resize()
      return true
   end

   return flux.on_key(cell, key, is_text, is_repeat)
end

local function add_cell(column, direction)
   local cell = ui.vbox({
      name = "cell",
      scrollable = false,
      min_w = 350,
      spacing = 4,
      fill = 0x77333333,
      border = 0x00cccc,
      focus_border = 0x77ffff,
      data = {},
      on_key = function(cell, key, is_text, is_repeat)
         local prompt = ui.below(cell, "prompt")
         if key == "return" then
            local focus = ui.get_focus()
            if focus == prompt then
               if not is_repeat and prompt.text ~= "" then
                  local mode = flux.get_mode(cell)
                  if mode == "default" then
                     local tokens = flux.tokenize(prompt.text)
                     local arg = tokens[1]
                     flux.set_mode(cell, arg)
                  else
                     flux.eval(cell)
                  end
               end
            else
               ui.set_focus(prompt)
               return true
            end
--         elseif key == "up" then
--            local prev, cur = ui.previous_sibling(cell)
--            if prev then
--               if prompt.text == "" and cur == #column.children and (prev.data == nil or prev.data.pwd == cell.data.pwd) then -- HACK
--                  column:remove_n_children_at(1, cur)
--               end
--               ui.set_focus(prev)
--            end
--            return true
--         elseif key == "down" then
--            local next = ui.next_sibling(cell)
--            if next then
--               ui.set_focus(ui.below(next, "prompt"))
--            else
--               if prompt.text ~= "" then
--print("adding generic cell")
--                  add_cell(column)
--               end
--            end
--            return true
--
         elseif is_text or key == "backspace" or key == "Ctrl return" or key == "Ctrl backspace" then
            prompt:on_key(key, is_text, is_repeat)
            ui.set_focus(prompt)
            return true
         end
      end,
      on_click = function(self)
         ui.set_focus(ui.below(self, "prompt"))
         return true
      end,
   }, {
      ui.hbox({ scrollable = false }, {
         ui.text("?", {
            name = "context",
            color = 0x00ffff,
            editable = false,
         }),
         ui.text(" ", {
            name = "spacer",
            color = 0x00ffff,
            editable = false,
         }),
         ui.text("", {
            name = "prompt",
            editable = true,
            on_key = prompt_on_key,
         }),
      })
   })
   ui.set_focus(cell)
   if direction == "right" then
      column = add_column()
   end
   column:add_child(cell)
   return cell
end

add_column = function()
   return columns:add_child(ui.vbox({
      name = "column",
      scrollable = false,
      spacing = 4,
      data = {
         name = string.char(64 + #columns.children + 1),
         add_cell = add_cell,
      }
   }))
end

local firstcol = add_column()
local firstcell = firstcol.data.add_cell(firstcol)
--flux.set_mode(firstcell, "shell")

local fullscreen = false

ui.on_key(function(focus, key, is_text, is_repeat)
   print(key)
   if key == "escape" then
      if focus.name == "cell" then
         ui.quit()
      else
         ui.set_focus(ui.above(focus, "cell"))
      end
   elseif key == "Alt return" and not is_repeat then
      fullscreen = not fullscreen
      ui.fullscreen(fullscreen)
   elseif key == "up" then
      local cell = ui.above(focus, "cell")
      if not cell then
         return
      end
      local column = ui.above(cell, "column")
      local prev, i = ui.previous_sibling(cell)
      if prev then
         ui.set_focus(prev)
         if i == #column.children and ui.below(cell, "prompt").text == "" then
            column:remove_n_children_at(1, i)
         end
      end
   elseif key == "down" then
      down(focus)
   elseif key == "left" then
      local cell = ui.above(focus, "cell")
      if not cell then
         return
      end
      local column = ui.above(cell, "column")
      local prevcol, i = ui.previous_sibling(column)
      if prevcol then
         ui.set_focus(prevcol.children[1]) -- FIXME cell visually to the left
         if #column.children == 1 and ui.below(column.children[1], "prompt").text == "" then
            columns:remove_n_children_at(1, i)
         end
      end
   elseif key == "right" then
      right(focus)
   end
end)

ui.run(function()
   flux.frame()
end)
