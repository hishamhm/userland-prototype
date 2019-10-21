local synth = {}

local denver = require("denver")
local sone = require("sone")

local flux = require("flux")

local ui

function synth.init(ui_)
   ui = ui_
   return { "~" }
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
   return "$~" .. c .. r, c, r
end

function synth.enable(cell)
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
   local id = "$~" ..c .. r
   return flux.set_mode(flux.register(id, column.data.add_cell(column, direction)), "synth")
end

function synth.eval(cell, trigger_object)
   local prompt = assert(ui.below(cell, "prompt"))
   local w, f = prompt.text:match("~%s*(%S+)%s+(%S+)")

   local depends = {}

   local ok, waveform = flux.value(w, w)
   if ok then
      depends[flux.get(w)] = true
   end

   local ok, frequency = flux.value(f, f)
   local dep_id = flux.get(f)
   if dep_id then
--   if ok then
      depends[dep_id] = true
--   end
   end

--   if trigger_object and not depends[trigger_object] then
--      -- this triggering was unnecessary; unlink cells:
--      flux.undepend(trigger_object, cell)
--   end

   for k, _ in pairs(depends) do
      flux.depend(k, cell)
   end

   frequency = tonumber(frequency) or 0
   if waveform then
      if waveform ~= cell.data.waveform or
         frequency ~= cell.data.frequency
      then
         if cell.data.source then
            cell.data.source:setLooping(false)
            love.audio.stop(cell.data.source)
         end
         if frequency > 0 and denver.is_valid(waveform) then
            cell.data.sound_data = denver.get({ waveform = waveform, frequency = frequency })
--            sone.filter(cell.data.sound_data, {
--               type = "lowpass",
--               frequency = 3000,
--            })
            cell.data.source = love.audio.newSource(cell.data.sound_data)
            cell.data.waveform = waveform
            cell.data.frequency = frequency
            cell.data.enabled = true
         else
            cell.data.source = nil
            return
         end
      end

      if not cell.data.source then
         return
      end

      if cell.data.enabled then
         cell.data.source:setLooping(true)
         love.audio.play(cell.data.source)
         cell.border = 0x00ff00
         cell.focus_border = 0x77ff77
      else
         cell.data.source:setLooping(false)
         love.audio.stop(cell.data.source)
         cell.border = 0x00cccc
         cell.focus_border = 0x77ffff
      end
   end
end

function synth.on_key(cell, text)
   local prompt = ui.below(cell, "prompt")
   if text == "return" then
      cell.data.enabled = not cell.data.enabled
      flux.eval(cell)
      return true
   elseif text == "down" then
      local next = ui.next_sibling(cell)
      if not next then
--         if prompt.text ~= "" then
            next = new_cell(cell, "down")
--         end
      end
      ui.set_focus(ui.below(next, "prompt"))
      return true
   elseif text == "tab" or text == "Shift return" then
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

return synth
