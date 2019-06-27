local shell = {}

local ui
local unistd = require("posix.unistd")
local poll = require("posix.poll")

local pipes = {}

function shell.init(ui_)
   ui = ui_
end

function shell.on_key(self, key)
   if key == "Ctrl L" then
      self.parent.parent.children = {}
      self.data.add_prompt("$ ")
      return true
   end
end

function shell.eval(self, text)
   if #text > 0 then
      local fds = {}
      fds.stdout_r, fds.stdout_w = unistd.pipe()
      fds.stderr_r, fds.stderr_w = unistd.pipe()
      pipes[self.parent] = fds
      local childpid = unistd.fork()
      if childpid == 0 then
         -- child process
         unistd.close(fds.stdout_r)
         unistd.close(fds.stderr_r)
         unistd.dup2(fds.stdout_w, unistd.STDOUT_FILENO)
         unistd.dup2(fds.stderr_w, unistd.STDERR_FILENO)
         os.execute(text)
         os.exit(0)
      else
         self.data.add_prompt("$ ")
      end
   end
end

local TEXT_W = 492 - 8

local function poll_fd(win, fd, color)
   local data = poll.rpoll(fd, 0)
   if data == 1 then
      local list
      if #win.children == 1 then
         local list = ui.vbox({ min_w = TEXT_W, max_h = 200, spacing = 4, scroll_by = 21, fill = 0x000000, border = 0x00ffff })
         win:add_child(list)
      else
         list = win.children[2]
      end
      if list then
         for line in unistd.read(fd, 1024):gmatch("[^\n]+") do
            list:add_child(ui.text(line, { max_w = TEXT_W, color = color }))
         end
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
