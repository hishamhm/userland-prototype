local shell = {}

local ui
local posix = require("posix")
local unistd = require("posix.unistd")
local poll = require("posix.poll")
local wait = require("posix.sys.wait")
local lfs = require("lfs")
local lexer = require("flux.lexer")

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

local function add_cell(self)
   local column = ui.above(self, "column")
   column.data.add_cell(column, { mode = "shell" }, show_dir(self.data.pwd), nil, { pwd = self.data.pwd })
end

function shell.init(ui_)
   ui = ui_
   return { "$" }
end

function shell.enable(self)
   local cell = ui.above(self, "cell")
   self.data.pwd = self.data.pwd or normalize(os.getenv("PWD"))
   cell.data.mode = "shell"
   ui.below(cell, "context"):set(show_dir(self.data.pwd))
   local prompt = ui.below(cell, "prompt")
   prompt:set("")
   prompt:resize()
end

function shell.on_key(self, key)
   local column = ui.above(self, "column")
   local cell = ui.above(self, "cell")
   if key == "Ctrl L" then
      column.children = {}
      column.data.add_cell(column, { mode = "shell" }, self.data.pwd, nil, { pwd = self.data.pwd })
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
      column.data.add_cell(column, { mode = "shell" }, self.data.pwd, "right", { pwd = self.data.pwd })
      return true
   elseif key == "Ctrl A" then
      self:cursor_set(0)
      return true
   elseif key == "Ctrl E" then
      self:cursor_set(math.huge)
      return true
   elseif key == "Up" then
      local prev, cur = ui.previous_sibling(cell)
      if prev then
         local prevprompt = ui.below(prev, "prompt")
         if self.text == "" and cur == #column.children and prevprompt.data.pwd == self.data.pwd then
            column:remove_n_children_at(1, cur)
         end
         ui.set_focus(prev)
      end
      return true
   elseif key == "Down" then
      if #cell.children == 2 then
         ui.set_focus(cell.children[2].children[1])
         cell.children[2].scroll_v = 0
         cell.children[2].scroll_h = 0
         cell:resize()
         return true
      end
      local next = ui.next_sibling(cell)
      if next then
         ui.set_focus(ui.below(next, "prompt"))
      else
         if self.text ~= "" then
            add_cell(self)
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

function shell.eval(self, tokens, input)
   local cell = ui.above(self, "cell")
   local context = ui.below(cell, "context")
   local prompt = ui.below(cell, "prompt")
   local output = ui.below(cell, "output")

   self.data = self.data or {}

   local nextcmd = true
   local cmd = tokens[1]
   local arg = input:match("^%s*[^%s]+%s+(.-)%s*$")

   if cmd == "cat" then
      if not arg then
         return
      end

      if not arg:match("^/") then
         arg = self.data.pwd:gsub("^~", os.getenv("HOME") .. "/") .. "/" .. arg
      end

      local output = reset_output(cell)
      add_cell(self)

      local lines, err = syntect.highlight_file(arg)
      if not lines then
         output:add_child(ui.text(err, { color = 0xff0000 }))
         return
      end
      local regions = {}
      for _, line in ipairs(lines) do
         for i = 1, #line, 2 do
            local style = line[i]
            local text, nl = line[i+1]:match("([^\n]*)(\n?)")
            table.insert(regions, ui.text(text, { color = style, focusable = false }))
            if nl == "\n" then
               output:add_child(ui.hbox({ scrollable = false }, regions))
               regions = {}
            end
         end
      end
      return
   end

   if cmd == "cd" then
      local pwd = arg
      if not pwd then
         pwd = os.getenv("HOME")
      end
      pwd = pwd:gsub("^~", os.getenv("HOME") .. "/")
      if not pwd:match("^/") then
         pwd = self.data.pwd .. "/" .. pwd
      end
      pwd = normalize(pwd)
      local attrs = lfs.attributes(pwd)
      if attrs and attrs.mode == "directory" then
         self.data.pwd = pwd
         context:set(show_dir(self.data.pwd))
         prompt:set("")
         input = "ls -1"
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
         if self.data.pwd then
            cd_to = "cd " .. self.data.pwd .. "; "
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
            add_cell(self)
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
            for line, nl in data:gmatch("([^\n]*)(\n*)") do
               -- FIXME proper tab expansion
               line = line:gsub("\t", "   ")
               -- TODO handle colors
               line = line:gsub("\27%[[^m]*m", "")
               line = line:gsub("\r", "")
               -- FIXME don't merge stdout and stderr lines
               if #line > 0 then
                  if cell.data.nl then
                     output:add_child(ui.text("", { color = color }))
                     cell.data.nl = false
                  end
                  output.children[#output.children]:cursor_move_char(math.huge)
                  output.children[#output.children]:add(line)
               end
               if #nl > 0 then
                  for _ = 1, #nl do
                     if cell.data.nl then
                        output:add_child(ui.text("", { color = color }))
                     else
                        cell.data.nl = true
                     end
                  end
               end
            end
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
