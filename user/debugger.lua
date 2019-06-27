local debugger = {}

local ui

function debugger.init(ui_)
   ui = ui_
end

function debugger.new(self)
   local columns = self.parent.parent.parent
   columns:add_child(ui.vbox({ name = string.char(64 + #columns.children + 1), spacing = 4, fill = 0x000000 }, {
      ui.vbox({ name = "window", scrollable = false, min_w = 492, max_w = 492, spacing = 4, fill = 0x333333, border = 0x00ffff }, {
         ui.tree(_G)
      })
   }))
end

return debugger
