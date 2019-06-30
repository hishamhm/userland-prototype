local debugger = {}

local ui

function debugger.init(ui_)
   ui = ui_
end

function debugger.new(self)
   local history = self.parent.parent
   history:add_child(ui.vbox({ name = "window", scroll_by = 21, min_w = 492, max_w = 492, max_h = 400, spacing = 4, fill = 0x222222, border = 0x00ffff }, {
      ui.tree(_G)
   }))
   history.data.add_prompt(history, "?", " ? ")
end

return debugger
