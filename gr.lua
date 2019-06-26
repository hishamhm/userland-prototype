local gr = {}

local SDL = require("SDL")
local Image = require("SDL.image")
local TTF = require("SDL.ttf")

local width = 800
local height = 600
local E = {}

local win
local rdr
local font
local root = { type = "root", children = {} }
local on_key_cb = function() end
local on_mouse_drag_cb = function() end
local running = true
local focus

local do_print1 = true
local function print1(...)
   if do_print1 then
      print(...)
   end
end

local function utf8_sub(s, i, j)
   return string.sub(s, utf8.offset(s, i), j and utf8.offset(s, j + 1) - 1)
end

function gr.set_focus(obj)
   focus = obj
end

function gr.init()
   local ret, err = SDL.init()
   if not ret then
      error(err)
   end

   ret, err = TTF.init()
   if not ret then
      error(err)
   end

   font = TTF.open("DejaVuSansMono.ttf", 14)

   win, err = SDL.createWindow({
      title = "Userland",
      width = width,
      height = height,
      flags = { SDL.flags.OpenGL },
   })
   if not win then
      error(err)
   end

   rdr, err = SDL.createRenderer(win, -1, { SDL.flags.Accelerated })
   if not rdr then
      error(err)
   end
end

function gr.clear()
   rdr:clear()
end

function gr.image(filename, flags)
   local obj = {
      type = "image",
      x = flags.x,
      y = flags.y,
      w = flags.w,
      h = flags.h,
   }
   local img, err = Image.load(filename)
   if not img then
      return nil, err
   end

   obj.tex, err = rdr:createTextureFromSurface(img)
   if not obj.tex then
      return nil, err
   end

   return obj
end

local function font_size(text)
   if text == "" then
      local w, h = font.sizeUtf8(font, " ")
      w = 1
      return w, h
   else
      return font.sizeUtf8(font, text)
   end
end

local function text_render(self)
   self.w, self.h = font_size(self.text)
   if not self.w then
      return nil, self.h
   end

   local s, err = font.renderUtf8(font, self.text, "blended", self.color)
   if not s then
      return nil, err
   end

   self.tex, err = rdr:createTextureFromSurface(s)
   if not self.tex then
      return nil, err
   end
end

local function text_add(self, str)
   self.text = utf8_sub(self.text, 1, self.cursor) .. str .. utf8_sub(self.text, self.cursor + 1)
   self.cursor = self.cursor + utf8.len(str)
   self.tex = nil
   self.cursor_x = nil
end

local function text_backspace(self)
   if self.cursor > 0 then
      self.text = utf8_sub(self.text, 1, self.cursor - 1) .. utf8_sub(self.text, self.cursor + 1)
      self.cursor = self.cursor - 1
      self.tex = nil
      self.cursor_x = nil
   end
end

local function text_cursor_left(self)
   if self.cursor > 0 then
      self.cursor = self.cursor - 1
      self.cursor_x = nil
   end
end

local function text_cursor_right(self)
   if self.cursor < utf8.len(self.text) then
      self.cursor = self.cursor + 1
      self.cursor_x = nil
   end
end

local function text_calc_cursor_x(self)
   local s = utf8_sub(self.text, 1, self.cursor)
   local w = font_size(s)
   self.cursor_x = self.x + w + 1
end

local function crop(obj)
   if obj.min_w then
      obj.w = math.max(obj.w, obj.min_w)
   end
   if obj.min_h then
      obj.h = math.max(obj.h, obj.min_h)
   end
   if obj.max_w then
      obj.w = math.min(obj.w, obj.max_w)
   end
   if obj.max_h then
      obj.h = math.min(obj.h, obj.max_h)
   end
end

function gr.text(text, flags)
   flags = flags or E
   local obj = {
      type = "text",
      x = flags.x,
      y = flags.y,
      max_w = flags.max_w,
      max_h = flags.max_h,
      min_w = flags.min_w,
      min_h = flags.min_h,
      on_key = flags.on_key,
      show_cursor = flags.show_cursor,
      cursor = 0,
      color = flags.color or 0xFFFFFF,
      text = text,
      render = text_render,
      add = text_add,
      cursor_left = text_cursor_left,
      cursor_right = text_cursor_right,
      backspace = text_backspace,
      calc_cursor_x = text_calc_cursor_x,
   }
   obj.w, obj.h = font_size(obj.text)
   crop(obj)

   return obj
end

function gr.rect(flags)
   local obj = {
      type = "rect",
      x = flags.x,
      y = flags.y,
      w = flags.w,
      h = flags.h,
      fill = flags.fill,
      border = flags.border,
   }

   return obj
end

local function detach(child)
   if child.parent then
      for i, o in ipairs(child.parent.children) do
         if o == child then
            table.remove(child.parent.children, i)
            break
         end
      end
   end
end

local function box_resize(obj)
   local a = obj.a
   local b = obj.b
   local max = 0
   local sum = obj.padding
   for _, child in ipairs(obj.children) do
      max = math.max(max, child[b] + (obj.padding * 2))
      sum = sum + child[a] + obj.padding
   end
   obj[b] = max
   obj[a] = sum
   if obj.parent and obj.parent ~= obj and obj.parent.resize then
      obj.parent:resize()
   end
   crop(obj)
end

local function add_child(self, child)
   detach(child)
   child.parent = self
   table.insert(self.children, child)
   self:resize()
end

local function box_on_wheel(self, y)
   if y == 1 then -- and self.scroll_v <= #self.children - 2 then
      for _, child in ipairs(self.children) do
         child.y = child.y + 5
      end
      --self.scroll_v = self.scroll_v + 5
   elseif y == -1 then -- and self.scroll_v > 0 then
      --self.scroll_v = self.scroll_v - 5
      for _, child in ipairs(self.children) do
         child.y = child.y - 5
      end
   end
end

local function make_box(flags, children, name, a, b)
   local obj = {
      type = name,
      x = flags.x,
      y = flags.y,
      w = flags.w or 0,
      h = flags.h or 0,
      scroll_v = 0,
      max_w = flags.max_w,
      max_h = flags.max_h,
      min_w = flags.min_w,
      min_h = flags.min_h,
      a = a,
      b = b,
      fill = flags.fill,
      border = flags.border,
      padding = flags.padding or 0,
      children = children,

      resize = box_resize,      
      on_wheel = box_on_wheel,
      add_child = add_child,
   }

   for _, child in ipairs(obj.children) do
      detach(child)
      child.parent = obj
   end

   obj:resize()
   
   return obj
end

function gr.vbox(flags, children)
   return make_box(flags, children, "vbox", "h", "w")
end

function gr.hbox(flags, children)
   return make_box(flags, children, "hbox", "w", "h")
end

function gr.in_root(obj)
   table.insert(root.children, obj)
   obj.parent = root
   return obj
end

function gr.on_key(cb)
   on_key_cb = cb
end

function gr.on_mouse_drag(cb)
   on_mouse_drag_cb = cb
end

function gr.quit()
   running = false
end

function gr.fullscreen(mode)
   win:setFullscreen(mode and SDL.window.Desktop or 0)
end

local ismod = {
   [SDL.key.LeftControl] = true,
   [SDL.key.LeftAlt] = true,
   [SDL.key.LeftShift] = true,
   [SDL.key.LeftGUI] = true,
   [SDL.key.RightControl] = true,
   [SDL.key.RightAlt] = true,
   [SDL.key.RightShift] = true,
}

local draw

local function box_draw(self, a, b, s, scrolldir)
   if self.fill then
      rdr:setDrawColor(self.fill)
      rdr:fillRect(self)
   end
   if self.border then
      rdr:setDrawColor(self.border)
      rdr:drawRect(self)
   end
   local aa = self[a] + self.padding
   local bb = self[b] + self.padding
   for _, child in ipairs(self.children) do
      child.parent = self
--      if not child[a] then
         child[a] = aa
--      end
--      if not child[b] then
         child[b] = bb
--      end
      if (child[a] + child[s] + self.padding - 1) > self[a] + self.padding then
         local ok = draw(child)
--         if ok == false then
--            break
--         end
      end
      aa = child[a] + child[s] + self.padding
   end
end

local function copy_to_rdr(obj)
   --crop(obj)
   if obj.tex then
      local src = { x = 0, y = 0, w = obj.w, h = obj.h }
      -- local dst = { x = obj.x, y = obj.y - scroll_v, w = obj.w, h = obj.h }
      rdr:copy(obj.tex, src, obj)
   end
end

draw = function(obj)
   -- inherit clip area from parent
   if obj.parent.x then
      local clip = obj -- { x = obj.x, y = obj.y - scroll_v, w = obj.w, h = obj.h }
      local p = obj
      while p.parent.x do
         local ok
         ok, clip = SDL.intersectRect(clip, p.parent)
         if not ok then
            return false
         end
         p = p.parent
      end
      if clip then
         if clip.border then
            rdr:setClipRect(clip)
         else
            rdr:setClipRect(clip)
         end
      end
   else
      local w, h = win:getSize()
      rdr:setClipRect({ w = w, h = h })
   end

   if obj.type == "image" then
      if not obj.tex then
         obj:render()
      end
      copy_to_rdr(obj)
   elseif obj.type == "text" then
      if not obj.tex then
         obj:render()
      end
      if obj.cursor and obj == focus then
         local cliprect = rdr:getClipRect()
         cliprect.w = cliprect.w + 10
         rdr:setClipRect(cliprect)
      end
      copy_to_rdr(obj)
      if obj.show_cursor then
         if not obj.cursor_x then
            obj:calc_cursor_x()
         end
         rdr:drawLine({ x1 = obj.cursor_x, y1 = obj.y + 1, x2 = obj.cursor_x, y2 = obj.y + obj.h - 2 })
      end
   elseif obj.type == "rect" then
      if obj.fill then
         rdr:setDrawColor(obj.fill)
         rdr:fillRect(obj)
      end
      if obj.border then
         rdr:setDrawColor(obj.border)
         rdr:drawRect(obj)
      end
   elseif obj.type == "vbox" then
      box_draw(obj, "y", "x", "h", "scroll_v")
   elseif obj.type == "hbox" then
      box_draw(obj, "x", "y", "w", "scroll_h")
   end
end

local function run_on_key(key, is_text, is_repeat)
   if focus and focus.on_key then
      local done = focus:on_key(key, is_text, is_repeat)
      if done then
         return
      end
   end
   if on_key_cb then
      on_key_cb(key, is_text, is_repeat)
   end
end

local function objects_under_mouse(obj, rets)
   obj = obj or root
   rets = rets or {}
   local _, x, y = SDL.getMouseState()
   local p = { x = x, y = y }
   if obj.children then
      for _, child in ipairs(obj.children) do
         if SDL.pointInRect(p, child) then
            objects_under_mouse(child, rets)
         end
      end
   end
   table.insert(rets, obj)
   return rets
end

function gr.run(frame)
   while running do
      for e in SDL.pollEvent() do
         if e.type == SDL.event.Quit then
            running = false
         elseif e.type == SDL.event.KeyDown then
            if not ismod[e.keysym.sym] then
               local k = SDL.getKeyName(e.keysym.sym)
               local mod = SDL.getModState()
               if mod[SDL.keymod.LGUI] then
                  k = "Win " .. k
               end
               if mod[SDL.keymod.LeftShift] or mod[SDL.keymod.RightShift] then
                  k = "Shift " .. k
               end
               if mod[SDL.keymod.LeftAlt] or mod[SDL.keymod.RightAlt] then
                  k = "Alt " .. k
               end
               if mod[SDL.keymod.LeftControl] or mod[SDL.keymod.RightControl] then
                  k = "Ctrl " .. k
               end
               if #k ~= 1 then
                  run_on_key(k, false, e["repeat"])
               end
            end
         elseif e.type == SDL.event.TextInput then
            run_on_key(e.text, true, e["repeat"])
         elseif e.type == SDL.event.MouseButtonDown then
            local objs = objects_under_mouse()
            focus = objs[1]
            --on_mouse_drag_cb(e.x, e.y)
         elseif e.type == SDL.event.MouseWheel then
            local objs = objects_under_mouse()
            for _, obj in ipairs(objs) do
               if obj.on_wheel then
                  obj:on_wheel(e.y)
                  break
               end
            end
         elseif e.type == SDL.event.MouseButtonUp then
--print(require'inspect'(e))
         elseif e.type == SDL.event.MouseMotion then
            if e.state[1] == 1 then
               on_mouse_drag_cb(e.x, e.y)
            end
--print(require'inspect'(e))
         end
      end

      rdr:setDrawColor(0x000000)
      rdr:clear()
      for _, child in ipairs(root.children) do
         child.parent = root
         draw(child, 0)
      end

      frame()
      rdr:present()
   
      SDL.delay(16)
      do_print1 = false
   end
end

return gr
