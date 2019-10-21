local spreadsheet = {}

local formulas = require("user.spreadsheet.formulas")

local flux = require("flux")

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

function spreadsheet.enable(cell)
   local cell_name, c, r = calc_cell_name(cell)
   cell.data.c = c
   cell.data.r = r
   flux.register(cell_name, cell)
   ui.below(cell, "context"):set(cell_name)
   return true
end

local function new_cell(self, direction)
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
   return flux.set_mode(flux.register(id, column.data.add_cell(column, direction)), "spreadsheet")
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

function spreadsheet.value(cell)
   local output = ui.below(cell, "output")
   if output and output.children[1] then
      if output.children[1].as_text then
         return true, output.children[1]:as_text()
      end
   end
   local prompt = ui.below(cell, "prompt")
   if prompt and prompt.text ~= "" then
      return true, prompt.text
   end
end

local function eval_formula(formula, cell, trigger_object)
   local my_id = cell.data.c .. cell.data.r
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
      local ok, value = flux.value(id, 0)
      local dep_id = flux.get(id)
      if dep_id then
         --if ok then
         depends[dep_id] = true
         --end
      end
      return value
   end

   print(require"inspect"(ast))
   local result = formulas.eval(ast, cell_value)

--   if trigger_object and not depends[trigger_object] then
--      -- this triggering was unnecessary; unlink cells:
--      flux.undepend(trigger_object, cell)
--   end

   for k, _ in pairs(depends) do
      flux.depend(k, cell)
   end

   return result
end

function spreadsheet.eval(cell, trigger_object)
   local prompt = ui.below(cell, "prompt")
   local formula = prompt.text:match("^%s*=%s*(.*)$")
   if formula then
      local result = eval_formula(formula, cell, trigger_object)
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
end

function spreadsheet.on_key(cell, text)
   local prompt = ui.below(cell, "prompt")
   if text == "down" or text == "return" then
      flux.eval(cell)

      local next = ui.next_sibling(cell)
      if not next then
--         if prompt.text ~= "" then
            next = new_cell(cell, "down")
--         end
      end
      ui.set_focus(ui.below(next, "prompt"))
      return true
   elseif text == "tab" or text == "Shift return" then
      flux.eval(cell)
      local column = ui.above(cell, "column")
      local nextcol = ui.next_sibling(column)
      if nextcol then
         local n = math.min(#nextcol.children, cell.data.r)
         ui.set_focus(nextcol.children[n])
      else
         if prompt.text ~= "" then
            local next = new_cell(cell, "right")
            ui.set_focus(ui.below(next, "prompt"))
         end
      end
      return true
   end
end

return spreadsheet
