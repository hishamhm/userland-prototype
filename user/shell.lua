local shell = {}

local ui

local poll = require("posix.poll")
local wait = require("posix.sys.wait")
local posix = require("posix")
local unistd = require("posix.unistd")

local gensym
do
   local g = 0
   gensym = function()
      g = g + 1
      return "$" .. g
   end
end

local lfs = require("lfs")

local flux = require("flux")

local syntect = require("syntect")

local pipes = {}

local function normalize(dir)
   dir = dir .. "/"
   dir = dir:gsub("//", "/"):gsub("/[^/]+/%.%./", "/"):gsub("//", "/")
   return dir
end

local function show_context(cell)
   local id = cell.data.id
   if not id then
      id = gensym()
      cell.data.id = id
      flux.register(id, cell)
   end
   local dir = cell.data.pwd
   return id .. " " .. dir:gsub("^" .. os.getenv("HOME"), "~")
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
   ui.below(cell, "context"):set(show_context(cell))
   local prompt = ui.below(cell, "prompt")
   prompt:set("")
   prompt:resize()
   return true
end

local function down_cell(cell)
   local next = ui.next_sibling(cell)

   if not next then
      local pipeline = ui.above(cell, "pipeline")
      if pipeline then
         next = ui.next_sibling(pipeline)
      end
   end

   if next then
      return ui.set_focus(ui.below(next, "prompt"))
   else
      local prompt = ui.below(cell, "prompt")
      if prompt.text ~= "" then
         ui.set_focus(new_cell(cell))
      end
   end

   return true
end

function shell.on_key(cell, key)
   local column = ui.above(cell, "column")
   local prompt = ui.below(cell, "prompt")
   if key == "Ctrl L" then
      local columns = ui.above(cell, "columns")
      columns:remove_n_children_at(nil, 2)
      column:remove_n_children_at()
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
      return down_cell(cell)
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
      min_w = 340,
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
   output.scroll_v = 0
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
      if i > 1 then
         flux.require(cells[i - 1], cells[i])
         if i < #pipeline then
            cells[i].data.in_pipe = true
         end
      end
   end

   local group = ui.hbox({
      name = "pipeline",
      data = {
         pwd = cell.data.pwd,
      },
      scrollable = false,
      margin = 5,
      spacing = 10,
      border = 0x789abc,
      fill   = 0x77345678,
      on_key = pipeline_on_key,
   }, cells)
   column:replace_child(cell, group)

   flux.eval(cells[1])

   down_cell(group)
end

local function propagate(cell, data)
   for nextcell in flux.each_requirement(cell) do
      local nextpipes = pipes[nextcell]
      if nextpipes then
         unistd.write(nextpipes.stdin_w, data)
      end
   end
end

local function close_readers(cell)
   for nextcell in flux.each_requirement(cell) do
      local nextpipes = pipes[nextcell]
      if nextpipes and nextpipes.stdin_w then
         unistd.close(nextpipes.stdin_w)
      end
   end
end

local function make_pipes(cell)
   local fds = {}
   fds.stdin_r, fds.stdin_w = unistd.pipe()
   if cell.data.in_pipe then
      fds.stdout_r, fds.stdout_w = unistd.pipe()--posix.openpty()
      fds.stderr_r, fds.stderr_w = unistd.pipe()--posix.openpty()
   else
      fds.stdout_r, fds.stdout_w = posix.openpty()
      fds.stderr_r, fds.stderr_w = posix.openpty()
   end
   pipes[cell] = fds
   return fds
end

function shell.eval(cell)
   local context = ui.below(cell, "context")
   local prompt = ui.below(cell, "prompt")
   local output = ui.below(cell, "output")

   local input = prompt.text
   if #input:match("^%s*(.-)%s*$") == 0 then
      return
   end
print("will eval ", cell, input)

   input = input:gsub("$([A-Z0-9$]+)", function(var)
      local ref = flux.get(var)
      local refout = ui.below(ref, "output")
      if not refout then
         refout = ui.below(ref, "prompt")
      end
      if refout and refout.as_text then
         local val = refout:as_text()
         if val then
            flux.depend(ref, cell)
            return val
         end
      end
      return var
   end)
print("will eval ", cell, input)

   cell.data = cell.data or {}

   local pipeline = {}
   for part in input:gmatch("%s*([^|]*)") do
      table.insert(pipeline, part)
   end

   if #pipeline > 1 then
      return expand_pipeline(cell, pipeline)
   end

   local nextcmd = true
   local cmd, arg = input:match("^%s*([^%s]+)%s*(.-)%s*$")

   if cmd == "quiet" then
      cmd, arg = arg:match("^%s*([^%s]+)%s*(.-)%s*$")
      cell.data.quiet = true
      input = cmd .. " " .. arg
   else
      cell.data.quiet = false
   end

   if cmd == "cat" then
      if not arg then
         return
      end

      if not arg:match("^/") then
         arg = cell.data.pwd:gsub("^~", os.getenv("HOME") .. "/") .. "/" .. arg
      end

      local output = reset_output(cell)
      down_cell(cell)

      local lines, err = syntect.highlight_file(arg)
      if lines then
         add_styled_lines(output, lines)
      else
         output:add_child(ui.text(err, { color = 0xff0000 }))
      end

      -- FIXME this reads the file twice
      local fd = io.open(arg, "r")
      if fd then
         local data = fd:read("*a")
         fd:close()

         propagate(cell, data)
         close_readers(cell)
      end

      return
   end

   if cmd == "show" then
      if arg == "" then
         local fds = {}
         fds.stdout_r, fds.stdin_w = unistd.pipe()
         pipes[cell] = fds

         cell.data.type = "image"
         cell.data.buffer = {}
print("creating anonymous image")
         return
      end

      if not arg:match("^/") then
         arg = cell.data.pwd:gsub("^~", os.getenv("HOME") .. "/") .. "/" .. arg
      end

      local output = reset_output(cell)
      down_cell(cell)

      local img = ui.image(arg)
      if img then
         output:add_child(img)
      else
         output:add_child(ui.text("could not load " .. arg, { color = 0xff0000 }))
      end
      output:resize()

      -- FIXME this reads the file twice
      local fd = io.open(arg, "r")
      if fd then
         local data = fd:read("*a")
         fd:close()

         propagate(cell, data)
         close_readers(cell)
      end

      return
   end

   if cmd == "cd" then
      local pwd = arg
      if pwd == "" then
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
         context:set(show_context(cell))
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

   cell.border = 0x777733
   cell.focus_border = 0xffff33
   cell.data.type = "text"

   local fds = make_pipes(cell)
   local childpid = unistd.fork()
   if childpid == 0 then
      -- child process
      unistd.close(fds.stdin_w)
      unistd.close(fds.stdout_r)
      unistd.close(fds.stderr_r)
      unistd.dup2(fds.stdin_r, unistd.STDIN_FILENO)
      unistd.dup2(fds.stdout_w, unistd.STDOUT_FILENO)
      unistd.dup2(fds.stderr_w, unistd.STDERR_FILENO)
      local cd_to = ""
      local cd_done = ""
      if cell.data.pwd then
         cd_to = "cd " .. cell.data.pwd .. "; "
         cd_done = ""
      end
      local ok, err, ecode = os.execute(cd_to .. input .. cd_done)
      unistd.close(unistd.STDIN_FILENO)
      unistd.close(unistd.STDOUT_FILENO)
      unistd.close(unistd.STDERR_FILENO)
      if err == "exit" then
         os.exit(ecode)
      end
      os.exit(0)
   else
      pipes[cell].pid = childpid
      unistd.close(fds.stdin_r)
      unistd.close(fds.stdout_w)
      unistd.close(fds.stderr_w)
      if nextcmd then
         down_cell(cell)
      end
   end
end

local function poll_fd(cell, fd, pid, color)
   if not fd then
      return
   end
   local n = 0
   repeat
      n = n + 1
      local has_data = poll.rpoll(fd, 0)
      if has_data == 1 then
         local output, cont = add_output(cell)
         if output then
            local data = unistd.read(fd, 4096)
if data then
   print("read ", #data, "bytes for", cell.data.type)
end
            if not data or #data == 0 then
               if pid then
print("no hang", wait.WNOHANG)
                  local ok, status, ecode = wait.wait(pid, wait.WNOHANG)
print(ok, status, ecode)
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
               else
                  if cell.data.type == "image" then
                     local out = table.concat(cell.data.buffer or {})
                     os.remove("/tmp/foo.jpg")
print("will write", #out, "bytes")
                     local ifd = io.open("/tmp/foo.jpg", "w"):write(out) -- HACK
                     ifd:close()
                     local output = add_output(cell)
print("will display result")
                     local img = ui.image("/tmp/foo.jpg")
                     if img then
                        output:remove_n_children_at(1, 1)
                        output:add_child(img)
                        output.scroll_v = 0
                        output.scroll_h = 0
                        output:resize()
                     end
                  end
                  cell.border = 0x00cccc
                  cell.focus_border = 0x00ffff
                  cell:resize()
               end
               close_readers(cell)
               pipes[cell] = nil
               return "eof"
            end
            if #output.children == 0 then
               cell.data.nl = true
            end

            if cell.data.type == "text" then
               if not cell.data.quiet then
                  add_styled_lines(output, { split_ansi_colors(data, color) })
               end
               propagate(cell, data)
            elseif cell.data.type == "image" then
               cell.data.buffer = cell.data.buffer or {}
               table.insert(cell.data.buffer, data)
--print("receiving image data", #data, string.format("%02x %02x %02x", data:sub(1,1):byte(),data:sub(2,2):byte(),data:sub(3,3):byte()), #(table.concat(cell.data.buffer)), " so far")
            else
print("unknown cell data type")
            end

            output.scroll_v = output.total_h - output.h
         end
      else
         print("has data?", has_data)
      end
   until has_data == 0 or n == 16
end

function shell.frame()
   for cell, fds in pairs(pipes) do
      poll_fd(cell, fds.stdout_r, fds.pid, 0xffffff)
      poll_fd(cell, fds.stderr_r, fds.pid, 0xff7777)
   end
end

return shell
