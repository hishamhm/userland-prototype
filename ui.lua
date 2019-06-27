local ui = {}

local SDL = require("SDL")
local Image = require("SDL.image")
local TTF = require("SDL.ttf")

local width = 1024
local height = 600
local E = {}

local win
local rdr
local font
local root = { type = "root", x = 0, y = 0, children = {} }
local on_key_cb = function() end
local on_mouse_drag_cb = function() end
local running = true
local focus
local update = true

local function utf8_sub(s, i, j)
   return string.sub(s, utf8.offset(s, i), j and utf8.offset(s, j + 1) - 1)
end

local function offset(rect, off)
  return { x = rect.x + off.x, y = rect.y + off.y, w = rect.w, h = rect.h }
end
 
function ui.set_focus(obj)
   focus = obj
   update = true
end

function ui.init()
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

   local w, h = win:getSize()
   root.w = w
   root.h = h
end

function ui.clear()
   rdr:clear()
   update = true
end

function ui.image(filename, flags)
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
   update = true
end

local function text_backspace(self)
   if self.cursor > 0 then
      self.text = utf8_sub(self.text, 1, self.cursor - 1) .. utf8_sub(self.text, self.cursor + 1)
      self.cursor = self.cursor - 1
      self.tex = nil
      self.cursor_x = nil
   end
   update = true
end

local function text_cursor_left(self)
   if self.cursor > 0 then
      self.cursor = self.cursor - 1
      self.cursor_x = nil
   end
   update = true
end

local function text_cursor_right(self)
   if self.cursor < utf8.len(self.text) then
      self.cursor = self.cursor + 1
      self.cursor_x = nil
   end
   update = true
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

local function text_resize(self)
   self.w, self.h = font_size(self.text)

   crop(self)
   if self.parent and self.parent ~= self and self.parent.resize then
      self.parent:resize()
   end
end

function ui.text(text, flags)
   flags = flags or E
   local obj = {
      type = "text",
      x = flags.x or 0,
      y = flags.y or 0,
      max_w = flags.max_w,
      max_h = flags.max_h,
      min_w = flags.min_w,
      min_h = flags.min_h,
      on_key = flags.on_key,
      editable = flags.editable,
      cursor = 0,
      color = flags.color or 0xFFFFFF,
      text = text,
      render = text_render,
      add = text_add,
      cursor_left = text_cursor_left,
      cursor_right = text_cursor_right,
      backspace = text_backspace,
      calc_cursor_x = text_calc_cursor_x,
      resize = text_resize,
   }
   obj:resize()
   return obj
end

function ui.rect(flags)
   local obj = {
      type = "rect",
      x = flags.x or 0,
      y = flags.y or 0,
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

local function box_resize(self)
   local X, Y, W, H
   if self.type == "vbox" then
      X, Y, W, H = "x", "y", "w", "h"
   else
      X, Y, W, H = "y", "x", "h", "w"
   end
   local ww = self.margin * 2
   local yy = self.margin
   for _, child in ipairs(self.children) do
      child.parent = self
      child[X] = self.margin
      child[Y] = yy
      yy = yy + child[H] + self.spacing
      ww = math.max(ww, child[W] + self.margin * 2)
   end
   yy = yy - self.spacing + self.margin
   self[W] = ww
   self[H] = yy
   crop(self)

   if self.parent and self.parent ~= self and self.parent.resize then
      self.parent:resize()
   end
end

local function add_child(self, child)
   detach(child)
   child.parent = self
   table.insert(self.children, child)
   self:resize()
   update = true
end

local function box_on_wheel(self, y)
   if y == 1 then
      self.scroll_v = self.scroll_v + self.scroll_by
   elseif y == -1 and self.scroll_v > 0 then
      self.scroll_v = self.scroll_v - self.scroll_by
   end
   update = true
end

local function make_box(flags, children, type)
   local obj = {
      name = flags.name,
      type = type,
      x = flags.x or 0,
      y = flags.y or 0,
      w = flags.w or 0,
      h = flags.h or 0,
      margin = flags.margin or flags.spacing or 0,
      spacing = flags.spacing or 0,
      scroll_v = 0,
      scroll_h = 0,
      scroll_by = flags.scroll_by or 5,
      max_w = flags.max_w,
      max_h = flags.max_h,
      min_w = flags.min_w,
      min_h = flags.min_h,
      fill = flags.fill,
      border = flags.border,
      children = children or {},

      resize = box_resize,
      on_wheel = flags.scroll ~= false and box_on_wheel,
      add_child = add_child,
   }

   for _, child in ipairs(obj.children) do
      detach(child)
      child.parent = obj
   end

   obj:resize()
   return obj
end

function ui.vbox(flags, children)
   return make_box(flags, children, "vbox")
end

function ui.hbox(flags, children)
   return make_box(flags, children, "hbox")
end

function ui.in_root(obj)
   table.insert(root.children, obj)
   obj.parent = root
   update = true
   return obj
end

function ui.on_key(cb)
   on_key_cb = cb
   update = true
end

function ui.on_mouse_drag(cb)
   on_mouse_drag_cb = cb
   update = true
end

function ui.quit()
   running = false
   update = true
end

function ui.fullscreen(mode)
   win:setFullscreen(mode and SDL.window.Desktop or 0)
   local w, h = win:getSize()
   root.w = w
   root.h = h
   update = true
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

local function box_draw(self, off, clip)
   local offself = offset(self, off)
   if self.fill then
      rdr:setDrawColor(self.fill + 1) -- wat
      rdr:fillRect(offself)
   end
   if self.border then
      rdr:setDrawColor(self.border)
      rdr:drawRect(offself)
   end
   offself.y = offself.y - self.scroll_v
   offself.x = offself.x - self.scroll_h
   for _, child in ipairs(self.children) do
      if (child.y + child.h - self.scroll_v) > self.margin
      and (child.x + child.w - self.scroll_h) > self.margin
      and (child.y - self.scroll_v) < self.h
      and (child.x - self.scroll_h) < self.w
      then
         draw(child, offself, clip)
      end
   end
end

local function copy_to_rdr(obj, off)
   if obj.tex then
      local src = { x = 0, y = 0, w = obj.w, h = obj.h }
      rdr:copy(obj.tex, src, offset(obj, off))
   end
end

draw = function(obj, off, clip)
   clip = clip or root
   local offobj = offset(obj, off)
   local ok
   ok, clip = SDL.intersectRect(clip, offobj)
   if not ok then
      return false
   end
   if clip then
      if clip.border then
         rdr:setClipRect(clip)
      else
         rdr:setClipRect(clip)
      end
   end

   if obj.type == "image" then
      if not obj.tex then
         obj:render()
      end
      copy_to_rdr(obj, off)
   elseif obj.type == "text" then
      if not obj.tex then
         obj:render()
      end
      if obj.editable and obj.cursor and obj == focus then
         local cliprect = rdr:getClipRect()
         cliprect.w = cliprect.w + 10
         rdr:setClipRect(cliprect)
      end
      copy_to_rdr(obj, off)
      if obj.editable and obj == focus then
         if not obj.cursor_x then
            obj:calc_cursor_x()
         end
         rdr:drawLine({ x1 = obj.cursor_x + off.x, y1 = obj.y + 1 + off.y, x2 = obj.cursor_x + off.x, y2 = obj.y + obj.h - 2 + off.y })
      end
   elseif obj.type == "rect" then
      if obj.fill then
         rdr:setDrawColor(obj.fill)
         rdr:fillRect(offobj)
      end
      if obj.border then
         rdr:setDrawColor(obj.border)
         rdr:drawRect(offobj)
      end
   elseif obj.type == "vbox" then
      box_draw(obj, off, clip)
   elseif obj.type == "hbox" then
      box_draw(obj, off, clip)
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

local function objects_under_mouse(obj, off, rets)
   obj = obj or root
   off = off or { x = 0, y = 0 }
   rets = rets or {}
   local _, x, y = SDL.getMouseState()
   local p = { x = x, y = y }
   if obj.children then
      for _, child in ipairs(obj.children) do
         local offchild = offset(child, off)
         if SDL.pointInRect(p, offchild) then
            objects_under_mouse(child, offchild, rets)
         end
      end
   end
   table.insert(rets, obj)
   return rets
end

function ui.run(frame)
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
            update = true
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
         elseif e.type == SDL.event.MouseMotion then
            if e.state[1] == 1 then
               on_mouse_drag_cb(e.x, e.y)
            end
         else
            update = true
         end
      end

      frame()

      if update then
         rdr:setDrawColor(0x000000)
         rdr:clear()
         for _, child in ipairs(root.children) do
            child.parent = root
            draw(child, root, root)
         end
         rdr:present()
         rdr:present()
         update = false
      end
   
      SDL.delay(16)
   end
end

return ui
