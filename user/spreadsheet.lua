local spreadsheet = {}

local formulas = require("user.spreadsheet.formulas")

local cells = setmetatable({}, { __mode = "k" })

local ui

function spreadsheet.init(ui_)
   ui = ui_
   return { "=" }
end

local function calc_cell_name(cell)
   local column = ui.above(cell, "column")
   local c = column.data.name
   local r
   for i, ch in ipairs(column.children) do
      if ch == cell then
         r = i
         break
      end
   end
   return c .. r, c, r
end

function spreadsheet.enable(self, _, _, text)
   local cell = ui.above(self, "cell")
   local cell_name, c, r = calc_cell_name(cell)
   cell.data.mode = "spreadsheet"
   cell.data.c = c
   cell.data.r = r
   cell.data.dependents = cell.data.dependents or {}
   cells[c .. r] = cell
   ui.below(cell, "context"):set(cell_name)
   local prompt = ui.below(cell, "prompt")
   if text then
      prompt:set(text)
   end
   prompt:resize()
   spreadsheet.eval(self)
end

local function add_cell(self, direction)
   local column = ui.above(self, "column")
   local r, c
   if direction == "down" then
      c = column.data.name
      r = (#column.children + 1)
   elseif direction == "right" then
      c = string.char(string.byte(column.data.name) + 1)
      r = 1
   end
   local id = c .. r
   cells[c .. r] = column.data.add_cell(column, { mode = "spreadsheet", r = r, c = c }, id, direction)
end

local function add_output(cell)
   local output = ui.below(cell, "output")
   if output then
      return output
   end
   output = ui.vbox({
      name = "output",
      min_w = 340,
      max_w = 340 * 2,
      spacing = 4,
      scroll_by = 21,
      fill = 0x77000000,
      border = 0x00ffff,
      focus_fill_color = 0x114444,
      -- on_key = output_on_key,
      on_click = function() return true end,
   })
   cell:add_child(output)
   return output
end

local function eval_formula(formula, my_id, trigger_id)
   local ast, errs = formulas.parse(formula)
   if errs then
      return "?SYNTAX ERROR"
   end
   if not ast then
      return nil
   end

   local depends = {}

   local function cell_value(id)
      id = id:upper()
      if id == my_id then
         return 0 -- LOOP!
      end
      local cell = cells[id]
      if cell then
         depends[id] = true
         local output = ui.below(cell, "output")
         if output and output.children[1] then
            return output.children[1].text
         end
         local prompt = ui.below(cell, "prompt")
         if prompt then
            return prompt.text
         end
      end
      return 0
   end

   print(require"inspect"(ast))
   local result = formulas.eval(ast, cell_value)

   if trigger_id and not depends[trigger_id] then
      -- this triggering was unnecessary; unlink cells:
      cells[trigger_id].data.dependents[my_id] = nil
   end

   for k, _ in pairs(depends) do
      local cell = cells[k]
      cell.data.dependents = cell.data.dependents or {}
      cell.data.dependents[my_id] = true
   end

   return result
end

function spreadsheet.eval(self, loop_ctrl, trigger_id)
   loop_ctrl = loop_ctrl or {}
   if loop_ctrl[self] then
      return
   end
   loop_ctrl[self] = true

   local cell = ui.above(self, "cell")
   local my_id = cell.data.c .. cell.data.r
   local prompt = ui.below(self, "prompt")
   local formula = prompt.text:match("^%s*=%s*(.*)$")
   if formula then
      local result = eval_formula(formula, my_id, trigger_id)
      if result then
         result = tostring(result)
         local output = add_output(cell)
         if #output.children == 0 then
            output:add_child(ui.text(result))
         else
            output.children[1]:set(result)
         end
      end
   else
      cell:remove_n_children_at(1, 2)
   end
   if cell.data.dependents then
      for dep_id, _ in pairs(cell.data.dependents) do
         local dep_cell = cells[dep_id]
         spreadsheet.eval(dep_cell, loop_ctrl, my_id)
      end
   end
end

function spreadsheet.on_key(self, text)
   local cell = ui.above(self, "cell")
   if text == "Down" or text == "Return" then
      spreadsheet.eval(self)
      local next = ui.next_sibling(cell)
      if next then
         ui.set_focus(ui.below(next, "prompt"))
      else
         if self.text ~= "" then
            add_cell(self, "down")
         end
      end
      return true
   elseif text == "Tab" or text == "Shift Return" then
      spreadsheet.eval(self)
      local column = ui.above(self, "column")
      local nextcol = ui.next_sibling(column)
      if nextcol then
         local n = math.min(#nextcol.children, cell.data.r)
         ui.set_focus(nextcol.children[n])
      else
         if self.text ~= "" then
            add_cell(self, "right")
         end
      end
      return true
   end
end

return spreadsheet
