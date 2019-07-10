local shell = {}

local ui
local unistd = require("posix.unistd")
local poll = require("posix.poll")

local pipes = {}

local function normalize(dir)
   dir = dir:gsub("^" .. os.getenv("HOME"), "~")
   dir = dir .. "/"
   dir = dir:gsub("//", "/"):gsub("/[^/]+/%.%./", "/"):gsub("//", "/")
   return dir
end

local function add_cell(self)
   local column = ui.above(self, "column")
   column.data.add_cell(column, "$", (self.data.pwd or "") .. " ", nil, { pwd = self.data.pwd })
end

function shell.init(ui_)
   ui = ui_
end

function shell.enable(self)
   local cell = ui.above(self, "cell")
   self.data.pwd = self.data.pwd or normalize(os.getenv("PWD"))
   cell.data.mode = "$"
   ui.below(cell, "context"):set(self.data.pwd .. " ")
   ui.below(cell, "prompt"):resize()
end

function shell.on_key(self, key)
   local column = ui.above(self, "column")
   local cell = ui.above(self, "cell")
   if key == "Ctrl L" then
      column.children = {}
      column.data.add_cell(column, "$", self.data.pwd .. " ", nil, { pwd = self.data.pwd })
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
      column.data.add_cell(column, "$", self.data.pwd .. " ", "right", { pwd = self.data.pwd })
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
            column:remove_n_children_below(1, cur - 1)
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

function shell.eval(self, text)
   local cell = ui.above(self, "cell")
   local context = ui.below(cell, "context")
   local prompt = ui.below(cell, "prompt")
   local output = ui.below(cell, "output")

   self.data = self.data or {}

   local nextcmd = true
   local pwd = text:match("^%s*cd%s*(.*)%s*$")
   if pwd then
      if pwd == "" then
         pwd = os.getenv("HOME")
      end
      pwd = pwd:gsub("^~", os.getenv("HOME") .. "/")
      if pwd:match("^/") then
         self.data.pwd = pwd
      else
         self.data.pwd = self.data.pwd .. "/" .. pwd
      end
      self.data.pwd = normalize(self.data.pwd)
      context:set(self.data.pwd .. " ")
      prompt:set("")
      text = "ls | column | expand"
      nextcmd = false
   end
   if output then
      output:remove_n_children_below(math.huge, 0)
   end
   if #text > 0 then
      local fds = {}
      fds.stdout_r, fds.stdout_w = unistd.pipe()
      fds.stderr_r, fds.stderr_w = unistd.pipe()
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
            cd_to = "cd " .. self.data.pwd .. " && ( "
            cd_done = " )"
         end
         os.execute(cd_to .. text .. cd_done)
         os.exit(0)
      else
         if nextcmd then
            add_cell(self)
         end
      end
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
   end
end

local TEXT_W = 492 - 8

local function poll_fd(cell, fd, color)
   local data = poll.rpoll(fd, 0)
   if data == 1 then
      local list
      local cont = false
      if #cell.children == 1 then
         local list = ui.vbox({
            name = "output",
            min_w = TEXT_W,
            max_w = TEXT_W * 2,
            max_h = 200,
            spacing = 4,
            scroll_by = 21,
            fill = 0x77000000,
            border = 0x00ffff,
            focus_fill_color = 0x114444,
            on_key = output_on_key,
            on_click = function() return true end,
         })
         cell:add_child(list)
      else
         list = cell.children[2]
         cont = true
      end
      if list then
         for line in unistd.read(fd, 1024):gmatch("([^\n]*)\n?") do
            -- FIXME proper tab expansion
            line = line:gsub("\t", "   ")
            -- FIXME don't merge stdout and stderr lines
            if cont and #list.children > 0 then
               list.children[#list.children]:cursor_move(math.huge)
               list.children[#list.children]:add(line)
            else
               list:add_child(ui.text(line, { color = color }))
            end
            cont = false
         end
         list.scroll_v = list.total_h - list.h
      end
   end
end

function shell.frame()
   for cell, fds in pairs(pipes) do
      poll_fd(cell, fds.stdout_r, 0xffffff)
      poll_fd(cell, fds.stderr_r, 0xff7777)
   end
end

return shell
