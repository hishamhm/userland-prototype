local shell = {}

local ui

local poll = require("posix.poll")
local wait = require("posix.sys.wait")
local posix = require("posix")
local unistd = require("posix.unistd")

local lfs = require("lfs")

local flux = require("flux")

local syntect = require("syntect")

local pipes = {}

local function normalize(dir)
   dir = dir .. "/"
   dir = dir:gsub("//", "/"):gsub("/[^/]+/%.%./", "/"):gsub("//", "/")
   return dir
end

local function show_dir(dir)
   return dir:gsub("^" .. os.getenv("HOME"), "~")
end

local function new_cell(cell, direction)
   assert(cell.data.pwd)
   local column = ui.above(cell, "column")
   return flux.set_mode(column.data.add_cell(column, direction), "shell", cell)
end

function shell.init(ui_)
   ui = ui_
   return { "$" }
end

function shell.enable(cell, prevcell)
   local prevpwd
   if prevcell then
      prevpwd = prevcell.data.pwd
   end
   cell.data.pwd = cell.data.pwd or prevpwd or normalize(os.getenv("PWD"))
   ui.below(cell, "context"):set(show_dir(cell.data.pwd))
   local prompt = ui.below(cell, "prompt")
   prompt:set("")
   prompt:resize()
   return true
end

function shell.on_key(cell, key)
   local column = ui.above(cell, "column")
   local prompt = ui.below(cell, "prompt")
   if key == "Ctrl L" then
      column.children = {}
      new_cell(cell)
      return true
   elseif key == "Ctrl M" then
      local output = ui.below(cell, "output")
      if output then
         output.max_h = math.min(output.max_h * 2, output.total_h)
         output:resize()
      end
      return true
   elseif key == "Ctrl N" then
      local output = ui.below(cell, "output")
      if output then
         output.max_h = math.max(21, math.floor(output.max_h / 2))
         output:resize()
      end
      return true
   elseif key == "Ctrl Tab" then
      new_cell(cell, "right")
      return true
   elseif key == "Ctrl A" then
      prompt:cursor_set(0)
      return true
   elseif key == "Ctrl E" then
      prompt:cursor_set(math.huge)
      return true
   elseif key == "Up" then
      local prevcell, cur = ui.previous_sibling(cell)
      if prevcell then
         if prompt.text == "" and cur == #column.children and prevcell.data.pwd == cell.data.pwd then
            column:remove_n_children_at(1, cur)
         end
         ui.set_focus(prevcell)
      end
      return true
   elseif key == "Down" then
      local output = ui.below(cell, "output")
      if ui.get_focus() == prompt and output then
         ui.set_focus(output)
         output.scroll_v = 0
         output.scroll_h = 0
         cell:resize()
         return true
      end
      local next = ui.next_sibling(cell)
      if next then
         ui.set_focus(ui.below(next, "prompt"))
      else
         if prompt.text ~= "" then
            new_cell(cell)
         end
      end
      return true
   end
end

local function output_on_key(self, key, is_text, is_repeat, focus)
   if not focus then
      return
   end

   if (self.type == "vbox" and key == "Up")
   or (self.type == "hbox" and key == "Left") then
      local prev = ui.previous_sibling(focus)
      if prev then
         ui.set_focus(prev)
      end
      return true
   elseif (self.type == "vbox" and key == "Down")
   or (self.type == "hbox" and key == "Right") then
      local next = ui.next_sibling(focus)
      if next then
         ui.set_focus(next)
      end
      return true
   elseif key == "Return" and not is_repeat then
      local prompt = ui.below(ui.above(self, "cell"), "prompt")
      if focus.text then
         prompt:add(focus.text)
         ui.set_focus(prompt)
      end
   end
end

local TEXT_W = 492 - 8

local function add_output(cell)
   local output = ui.below(cell, "output")
   if output then
      return output, true
   end
   output = ui.vbox({
      name = "output",
      min_w = TEXT_W,
      max_w = TEXT_W * 2,
      max_h = 450,
      spacing = 4,
      scroll_by = 21,
      fill = 0x77000000,
      border = 0x00ffff,
      focus_fill_color = 0x114444,
      on_key = output_on_key,
      on_click = function() return true end,
   })
   cell:add_child(output)
   return output, false
end

local function reset_output(cell)
   local output = add_output(cell)
   output:remove_n_children_at()
   return output
end

local ecma48sgr_colors = {
   [0]  = 0xdddddd,
   [31] = 0x993333,
   [32] = 0x009933,
   [33] = 0x999933,
   [34] = 0x0066ff,
   [35] = 0x993399,
   [36] = 0x009999,
   [37] = 0xdddddd,
}

local bold_ecma48sgr_colors = {
   [0]  = 0xffffff,
   [31] = 0xff7777,
   [32] = 0x00ff77,
   [33] = 0xffff77,
   [34] = 0x3399ff,
   [35] = 0xff77ff,
   [36] = 0x00ffff,
   [37] = 0xffffff,
}

local function expand_tabs(text)
   local extra = 0
   local begin = 0
   return text:gsub("()([\t\n])", function(at, c)
      at = at - begin
      if c == "\t" then
         at = at + extra
         local size = 8 - ((at - 1) % 8)
         extra = extra + size - 1
         return (" "):rep(size)
      else
         begin = begin + at
         extra = 0
         return "\n"
      end
   end)
end

local function split_ansi_colors(data, default_color)
   local color = 0 -- FIXME continue last color
   local bold = false
   local out = {}
   local i = 1
   data = expand_tabs(data:gsub("\r", ""))
   local extra = 0
   data = data:gsub("()\t", function(at)
      at = at + extra
      local size = 8 - at % 8
      extra = extra + size - 1
      return (" "):rep(size)
   end)
   while true do
      local at, cmd, nextat = data:match("()\27%[([0-9;]+)m()", i)
      local rgb = (color == 0 and not bold)
                  and default_color
                  or (bold
                     and bold_ecma48sgr_colors[color]
                     or  ecma48sgr_colors[color])
      if not at then
         table.insert(out, rgb)
         table.insert(out, data:sub(i))
         return out
      end
      if at > i then
         table.insert(out, rgb)
         table.insert(out, data:sub(i, at - 1))
      end
      for c in cmd:gmatch("[^;]+") do
         c = tonumber(c)
         if c == 0 or c == 22 then
            bold = false
         elseif c == 1 then
            bold = true
         end
         if ecma48sgr_colors[c] then
            color = c
         end
         -- TODO background colors
      end
      i = nextat
   end
end

local function add_styled_lines(output, lines)
   local regions = {}
   for _, line in ipairs(lines) do
      for i = 1, #line, 2 do
         local style = line[i]
         for text, nl in line[i+1]:gmatch("([^\n]*)(\n?)") do
            text = expand_tabs(text) -- FIXME this won't expand correctly, it's too late
            table.insert(regions, ui.text(text, { color = style, focusable = false }))
            if nl == "\n" then
               output:add_child(ui.hbox({ scrollable = false }, regions))
               regions = {}
            end
         end
      end
   end
end

local function pipeline_on_key(self, key)
--   if key == "Up" then
--      local prev, cur = ui.previous_sibling(self)
--      if prev then
--         ui.set_focus(prev)
--      end
--      return true
--   elseif key == "Down" then
--      local next = ui.next_sibling(self)
--      if next then
--         ui.set_focus(next)
--      else
--         new_cell(ui.below(self, "cell"))
--      end
--      return true
   if key == "Return" then
      ui.set_focus(self.children[1])
   end
end

local function expand_pipeline(cell, pipeline)
   local column = ui.above(cell, "column")
   local cells = {}
   for i, part in ipairs(pipeline) do
      cells[i] = new_cell(cell)
      column.children[#column.children] = nil
      local cellprompt = ui.below(cells[i], "prompt")
      cellprompt:set(part)
      shell.eval(cells[i])
      if i > 1 then
         flux.connect(cells[i - 1], cells[i])
      end
   end
   local group = ui.hbox({
      name = "pipeline",
      scrollable = false,
      margin = 5,
      spacing = 10,
      border = 0x789abc,
      on_key = pipeline_on_key,
   }, cells)
   column:replace_child(cell, group)
end

function shell.eval(cell)
   local context = ui.below(cell, "context")
   local prompt = ui.below(cell, "prompt")
   local output = ui.below(cell, "output")

   local input = prompt.text

   cell.data = cell.data or {}

   local nextcmd = true
   local cmd, arg = input:match("^%s*([^%s]+)%s*(.-)%s*$")

   local pipeline = {}
   for part in input:gmatch("%s*[^|]*") do
      table.insert(pipeline, part)
   end

   if #pipeline > 1 then
      return expand_pipeline(cell, pipeline)
   end

   if cmd == "cat" then
      if not arg then
         return
      end

      if not arg:match("^/") then
         arg = cell.data.pwd:gsub("^~", os.getenv("HOME") .. "/") .. "/" .. arg
      end

      local output = reset_output(cell)
      new_cell(cell)

      local lines, err = syntect.highlight_file(arg)
      if not lines then
         output:add_child(ui.text(err, { color = 0xff0000 }))
         return
      end
      add_styled_lines(output, lines)
      return
   end

   if cmd == "cd" then
      local pwd = arg
      if not pwd then
         pwd = os.getenv("HOME")
      end
      pwd = pwd:gsub("^~", os.getenv("HOME") .. "/")
      if not pwd:match("^/") then
         pwd = cell.data.pwd .. "/" .. pwd
      end
      pwd = normalize(pwd)
      local attrs = lfs.attributes(pwd)
      if attrs and attrs.mode == "directory" then
         cell.data.pwd = pwd
         context:set(show_dir(cell.data.pwd))
         prompt:set("")
         input = "ls -1 --color"
         nextcmd = false
      else
         return
      end
   end

   if output then
      output:remove_n_children_at()
   end

   if #input > 0 then
      cell.border = 0x777733
      cell.focus_border = 0xffff33

      local fds = {}
      fds.stdout_r, fds.stdout_w = posix.openpty()
      fds.stderr_r, fds.stderr_w = posix.openpty()
      pipes[cell] = fds
      local childpid = unistd.fork()
      if childpid == 0 then
         -- child process
         unistd.close(fds.stdout_r)
         unistd.close(fds.stderr_r)
         unistd.dup2(fds.stdout_w, unistd.STDOUT_FILENO)
         unistd.dup2(fds.stderr_w, unistd.STDERR_FILENO)
         local cd_to = ""
         local cd_done = ""
         if cell.data.pwd then
            cd_to = "cd " .. cell.data.pwd .. "; "
            cd_done = ""
         end
         local ok, err, ecode = os.execute(cd_to .. input .. cd_done)
         unistd.close(unistd.STDOUT_FILENO)
         unistd.close(unistd.STDERR_FILENO)
         if err == "exit" then
            os.exit(ecode)
         end
         os.exit(0)
      else
         pipes[cell].pid = childpid
         unistd.close(fds.stdout_w)
         unistd.close(fds.stderr_w)
         if nextcmd then
            new_cell(cell)
         end
      end
   end
end

local function poll_fd(cell, fd, pid, color)
   local n = 0
   repeat
      n = n + 1
      local data = poll.rpoll(fd, 0)
      if data == 1 then
         local output, cont = add_output(cell)
         if output then
            local data = unistd.read(fd, 4096)
            if (not data) or #data == 0 then
               local ok, status, ecode = wait.wait(pid)
               if ok then
                  if ecode == 0 then
                     cell.border = 0x00cccc
                     cell.focus_border = 0x00ffff
                     cell:resize()
                  else
                     cell.border = 0xcc3333
                     cell.focus_border = 0xff3333
                     cell:resize()
                  end
               end
               pipes[cell] = nil
               return "eof"
            end
            if #output.children == 0 then
               cell.data.nl = true
            end
            add_styled_lines(output, { split_ansi_colors(data, color) })
            output.scroll_v = output.total_h - output.h
         end
      end
   until data == 0 or n == 100
end

function shell.frame()
   for cell, fds in pairs(pipes) do
      poll_fd(cell, fds.stdout_r, fds.pid, 0xffffff)
      poll_fd(cell, fds.stderr_r, fds.pid, 0xff7777)
   end
end

return shell
