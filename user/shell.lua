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
   local window = self.parent.parent
   local history = window.parent
   history.data.add_prompt(history, "$", " " .. (self.data.pwd or "") .. " ", nil, { pwd = self.data.pwd })
end

function shell.init(ui_)
   ui = ui_
end

function shell.enable(self)
   local window = self.parent.parent
   self.data.pwd = self.data.pwd or normalize(os.getenv("PWD"))
   window.data.context = "$"
   self.parent.children.context:set(" " .. self.data.pwd .. " ")
   self.parent.children.prompt:resize()
end

function shell.on_key(self, key)
   local history = self.parent.parent.parent
   local window = self.parent.parent
   if key == "Ctrl L" then
      history.children = {}
      history.data.add_prompt(history, "$", " " .. self.data.pwd .. " ", nil, { pwd = self.data.pwd })
      return true
   elseif key == "Ctrl Tab" then
      history.data.add_prompt(history, "$", " " .. self.data.pwd .. " ", "right", { pwd = self.data.pwd })
      return true
   elseif key == "Ctrl A" then
      self:cursor_set(0)
      return true
   elseif key == "Ctrl E" then
      self:cursor_set(math.huge)
      return true
   elseif key == "Up" then
      -- TODO make not O(n)
      local prev, cur
      for i, child in ipairs(history.children) do
         if child == window then
            cur = i
            break
         end
         prev = child
      end
      if prev then
         local prevprompt = prev.children[1].children.prompt
         if self.text == "" and cur == #history.children and prevprompt.data.pwd == self.data.pwd then
            history:remove_n_children_below(1, cur - 1)
         end
         ui.set_focus(prevprompt)
      end
   elseif key == "Down" then
      -- TODO make not O(n)
      local next
      local pick = false
      for _, child in ipairs(history.children) do
         if pick then
            next = child
            break
         end
         if child == window then
            pick = true
         end
      end
      if next then
         ui.set_focus(next.children[1].children.prompt)
      else
         if self.text ~= "" then
            add_cell(self)
         end
      end
   end
end

function shell.eval(self, text)
   local window = self.parent.parent
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
      self.parent.children.context:set(" " .. self.data.pwd .. " ")
      self.parent.children.prompt:set("")
      text = "ls | column | expand"
      nextcmd = false
   end
   if window.children.output then
      window.children.output:remove_n_children_below(math.huge, 0)
   end
   if #text > 0 then
      local fds = {}
      fds.stdout_r, fds.stdout_w = unistd.pipe()
      fds.stderr_r, fds.stderr_w = unistd.pipe()
      pipes[window] = fds
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

local TEXT_W = 492 - 8

local function poll_fd(win, fd, color)
   local data = poll.rpoll(fd, 0)
   if data == 1 then
      local list
      local cont = false
      if #win.children == 1 then
         local list = ui.vbox({ name = "output", min_w = TEXT_W, max_w = TEXT_W * 2, max_h = 200, spacing = 4, scroll_by = 21, fill = 0x77000000, border = 0x00ffff })
         win:add_child(list)
      else
         list = win.children[2]
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
   for win, fds in pairs(pipes) do
      poll_fd(win, fds.stdout_r, 0xffffff)
      poll_fd(win, fds.stderr_r, 0xff7777)
   end
end

return shell
