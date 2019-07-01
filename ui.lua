local ui = {}

local SDL = require("SDL")
local Image = require("SDL.image")
local TTF = require("SDL.ttf")
local util = require("util")

local width = 1024
local height = 600
local E = {}

local win
local rdr
local font
local root = { type = "root", x = 0, y = 0, children = {} }
local on_key_cb = function() end
local running = true
local focus
local update = true

local function alpha(color)
   return (0xff000000 - (color & 0xff000000)) | (color & 0xffffff)
end

local function utf8_sub(s, i, j)
   return string.sub(s, utf8.offset(s, i), j and utf8.offset(s, j + 1) - 1)
end

local function offset(rect, off)
  return { x = rect.x + off.x, y = rect.y + off.y, w = rect.w, h = rect.h }
end

local function expand(rect, n)
  return { x = rect.x - n, y = rect.y - n, w = rect.w + n * 2, h = rect.h + n * 2 }
end

function ui.set_focus(obj)
   focus = assert(obj)
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
   rdr:setDrawBlendMode(SDL.blendMode.Blend)

   win:setResizeable(true)

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

   local s, err = font.renderUtf8(font, self.text, "blended", alpha(self.color))
   if not s then
      return nil, err
   end

   self.tex, err = rdr:createTextureFromSurface(s)
   if not self.tex then
      return nil, err
   end
end

local function text_set(self, str)
   self.text = str
   self.cursor = utf8.len(str)
   self.tex = nil
   self.cursor_x = nil
   self:resize()
   update = true
end

local function text_add(self, str)
   self.text = utf8_sub(self.text, 1, self.cursor) .. str .. utf8_sub(self.text, self.cursor + 1)
   self.cursor = self.cursor + utf8.len(str)
   self.tex = nil
   self.cursor_x = nil
   self:resize()
   update = true
end

local function text_backspace(self)
   if self.cursor > 0 then
      self.text = utf8_sub(self.text, 1, self.cursor - 1) .. utf8_sub(self.text, self.cursor + 1)
      self.cursor = self.cursor - 1
      self.tex = nil
      self.cursor_x = nil
   end
   self:resize()
   update = true
end

local function text_cursor_move(self, rel)
   local new_value = math.min(math.max(0, self.cursor + rel), utf8.len(self.text))
   if self.cursor ~= new_value then
      self.cursor = new_value
      self.cursor_x = nil
      update = true
   end
end

local function text_cursor_set(self, new_value)
   new_value = math.min(math.max(0, new_value), utf8.len(self.text))
   if self.cursor ~= new_value then
      self.cursor = new_value
      self.cursor_x = nil
      update = true
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

local function text_on_key(self, key, is_text, is_repeat)
   if self.on_key_cb then
      local ok = self:on_key_cb(key, is_text, is_repeat)
      if ok then
         return true
      end
   end
   if key == "Backspace" then
      self:backspace()
      self:resize()
      return true
   elseif key == "Return" then
      if self.eval and not is_repeat and self.text ~= "" then
         self:eval(self.text)
         return true
      end
   elseif key == "Left" then
      self:cursor_move(-1)
      return true
   elseif key == "Right" then
      self:cursor_move(1)
      return true
   elseif key == "Home" then
      self:cursor_set(0)
      return true
   elseif key == "End" then
      self:cursor_set(math.huge)
      return true
   elseif is_text then
      self:add(key)
      self:resize()
      return true
   end
end

local function text_resize(self)
   self.w, self.h = font_size(self.text)
   self.tex = nil
   self.cursor_x = nil

   crop(self)
   if self.parent and self.parent ~= self and self.parent.resize then
      self.parent:resize()
   end
end

function ui.text(text, flags)
   flags = flags or E
   local obj = {
      type = "text",
      name = flags.name,
      x = flags.x or 0,
      y = flags.y or 0,
      max_w = flags.max_w,
      max_h = flags.max_h,
      min_w = flags.min_w,
      min_h = flags.min_h,
      editable = flags.editable,
      color = flags.color or 0xffffff,
      fill = flags.fill,
      border = flags.border,
      eval = flags.eval,
      data = flags.data,
      on_key_cb = flags.on_key,

      cursor = math.max(math.min(flags.cursor or 0, #text), 0),
      text = text,
      render = text_render,
      add = text_add,
      set = text_set,
      cursor_set = text_cursor_set,
      cursor_move = text_cursor_move,
      backspace = text_backspace,
      calc_cursor_x = text_calc_cursor_x,
      resize = text_resize,
      on_key = text_on_key,
      on_click = flags.on_click,
   }
   obj:resize()
   return obj
end

local function tree_collapser_on_click(self)
   self.data.open = not self.data.open
   local line = self.parent
   local tree = line.parent
   if self.data.open then
      self:set(" ▽ ")
      local children = line.data.collapsed
      line.data.collapsed = nil
      tree:add_children_below(children, line)
   else
      self:set(" ▷ ")
      local level = line.data.level
      local collapse = {}
      local pos
      for i, child in ipairs(tree.children) do
         if not pos then
            if child == line then
               pos = i
            end
         else
            if child.data.level > level then
               table.insert(collapse, child)
            else
               break
            end
         end
      end
      tree:remove_n_children_below(#collapse, pos)
      line.data.collapsed = collapse
   end
end

local function traverse_tree(tree, box, level, seen)
   seen[tree] = true
   for k, v in util.sortedpairs(tree) do
      local line = ui.hbox({ scrollable = false, data = { level = level } })
      for _ = 1, level - 1 do
         line:add_child(ui.text("   "))
      end
      if type(v) == "table" and not seen[v] then
         line:add_child(ui.text(" ▽ ", { color = 0x00ffff, on_click = tree_collapser_on_click, data = { open = true } } ))
         line:add_child(ui.text(tostring(k)))
         box:add_child(line)
         traverse_tree(v, box, level + 1, seen)
      else
         line:add_child(ui.text("   "))
         line:add_child(ui.text(tostring(k) .. " = " ..tostring(v)))
         box:add_child(line)
      end
   end
end

function ui.tree(tree)
   local box = ui.vbox({ name = "tree", scroll_by = 17 })
   traverse_tree(tree, box, 1, {})
   return box
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
      focus_border = flags.focus_border,
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
   local X, Y, W, H, TW, TH
   if self.type == "vbox" then
      X, Y, W, H, TW, TH = "x", "y", "w", "h", "total_w", "total_h"
   else
      X, Y, W, H, TW, TH = "y", "x", "h", "w", "total_h", "total_w"
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
   self[TH] = yy
   self[TW] = ww
   crop(self)

   if self.parent and self.parent ~= self and self.parent.resize then
      self.parent:resize()
   end
end

local function box_add_child(self, child)
   detach(child)
   child.parent = self
   table.insert(self.children, child)
   -- TODO schedule a single resize after all children added
   self:resize()
   update = true
   return child
end

local function box_add_children_below(self, children, item)
   local pos = nil
   for i, child in ipairs(self.children) do
      if not pos then
         if child == item then
            pos = i
            break
         end
      end
   end
   local n = #children
   for i = #self.children, pos + 1, -1 do
      self.children[i + n] = self.children[i]
   end
   for i, child in ipairs(children) do
      detach(child)
      child.parent = self
      self.children[i + pos] = child
   end
   self:resize()
   update = true
end

local function box_remove_n_children_below(self, n, pos)
   for _ = pos + 1, math.min(pos + n, #self.children) do
      detach(self.children[pos + 1])
   end
   self:resize()
   update = true
end

local function box_on_wheel(self, x, y)
   if y == -1 and self.scroll_v < self.total_h - self.h then
      self.scroll_v = self.scroll_v + self.scroll_by
   elseif y == 1 and self.scroll_v > 0 then
      self.scroll_v = math.max(0, self.scroll_v - self.scroll_by)
   end
   if x == -1 and self.scroll_h < self.total_w - self.w then
      self.scroll_h = self.scroll_h + self.scroll_by
   elseif x == 1 and self.scroll_h > 0 then
      self.scroll_h = math.max(0, self.scroll_h - self.scroll_by)
   end
   update = true
end

local function box_on_drag(self, x, y)
   self.scroll_v = math.max(0, self.scroll_v - y)
   self.scroll_h = math.max(0, self.scroll_h - x)
   update = true
end

local box_children_mt = {
   __index = function(t, k)
      for i = 1, #t do
         local ti = rawget(t, i)
         if ti.name == k then
            return ti
         end
      end
   end
}

local function make_box(flags, children, type)
   flags = flags or E
   local obj = {
      name = flags.name,
      type = type,
      x = flags.x or 0,
      y = flags.y or 0,
      w = flags.w or 0,
      h = flags.h or 0,
      total_w = 0,
      total_h = 0,
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
      focus_border = flags.focus_border,
      children = children or {},
      data = flags.data,

      resize = box_resize,
      on_wheel = flags.scrollable ~= false and box_on_wheel,
      on_drag = flags.scrollable ~= false and box_on_drag,
      on_click = flags.on_click,
      on_key = flags.on_key,
      add_child = box_add_child,
      add_children_below = box_add_children_below,
      remove_n_children_below = box_remove_n_children_below,
   }
   setmetatable(obj.children, box_children_mt)

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

function ui.previous_sibling(self)
   -- TODO make not O(n)
   local prev, cur
   for i, child in ipairs(self.parent.children) do
      if child == self then
         cur = i
         break
      end
      prev = child
   end
   return prev, cur
end

function ui.next_sibling(self)
   -- TODO make not O(n)
   local next
   local pick = false
   for _, child in ipairs(self.parent.children) do
      if pick then
         next = child
         break
      end
      if child == self then
         pick = true
      end
   end
   return next
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
      rdr:setDrawColor(alpha(self.fill)) -- wat
      rdr:fillRect(offself)
   end
   if self.border then
      local color = (self == focus or self == focus.parent) and self.focus_border or self.border
      if self == focus or self == focus.parent then
         rdr:setClipRect(root)
         for i = 1, 5 do
            local v = (0xff - math.floor(0x99 / i)) << 24
            rdr:setDrawColor(alpha(color + v))
            rdr:drawRect(expand(offself, i))
         end
      end
      rdr:setDrawColor(alpha(color))
      rdr:drawRect(offself)
      rdr:setClipRect(clip)
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
      if obj.fill then
         rdr:setDrawColor(alpha(obj.fill))
         rdr:fillRect(offobj)
      end
      if obj.border then
         local color = obj == focus and obj.focus_border or obj.border
         rdr:setDrawColor(alpha(color))
         rdr:drawRect(offobj)
      end

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
         rdr:setDrawColor(alpha(obj.fill))
         rdr:fillRect(offobj)
      end
      if obj.border then
         local color = obj == focus and obj.focus_border or obj.border
         rdr:setDrawColor(alpha(color))
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
      on_key_cb(focus, key, is_text, is_repeat)
   end
end

local function objects_under_mouse(obj, off, rets, p)
   obj = obj or root
   off = off or { x = 0, y = 0 }
   rets = rets or {}
   if not p then
      local _, x, y = SDL.getMouseState()
      p = { x = x, y = y }
   end
   if obj.children then
      for _, child in ipairs(obj.children) do
         local offchild = offset(child, off)
         if SDL.pointInRect(p, offchild) then
            offchild.y = offchild.y - (obj.scroll_v or 0)
            offchild.x = offchild.x - (obj.scroll_h or 0)
            objects_under_mouse(child, offchild, rets, p)
         end
      end
   end
   table.insert(rets, obj)
   return rets
end

local function draw_background()
   rdr:setClipRect({ x = 0, y = 0, w = root.w, h = root.h })

   local D1 = 200
   local D2 = 100

   rdr:setDrawColor(alpha(0x003333))
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_h / 4) % D2), root.w, D2 do
      rdr:drawLine({ x1 = i, y1 = 0, x2 = i, y2 = root.h })
   end
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_v / 4) % D2), root.h, D2 do
      rdr:drawLine({ x1 = 0, y1 = i, x2 = root.w, y2 = i })
   end

   rdr:setDrawColor(alpha(0x007777))
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_h / 2) % D1), root.w, D1 do
      rdr:drawLine({ x1 = i, y1 = 0, x2 = i, y2 = root.h })
   end
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_v / 2) % D1), root.h, D1 do
      rdr:drawLine({ x1 = 0, y1 = i, x2 = root.w, y2 = i })
   end
end

local function mouse_callback(cb_name, x, y)
   local objs = objects_under_mouse()
   for _, obj in ipairs(objs) do
      io.write((obj.name or obj.type) .. " ")
   end
   io.write("\n")
   for _, obj in ipairs(objs) do
      if obj[cb_name] then
         obj[cb_name](obj, x, y)
         break
      end
   end
end

function ui.run(frame)
   root.on_wheel = function(_, x, y)
      root.children[1]:on_wheel(x, y)
   end
   root.on_drag = function(_, x, y)
      root.children[1]:on_drag(x, y)
   end

   while running do
      for e in SDL.pollEvent() do
         if e.type == SDL.event.Quit then
            running = false
         elseif e.type == SDL.event.KeyDown then
            if not ismod[e.keysym.sym] then
               local k = SDL.getKeyName(e.keysym.sym)
               local mod = SDL.getModState()
               local mk = ""
               if mod[SDL.keymod.LGUI] then
                  mk = "Win " .. mk
               end
               if mod[SDL.keymod.LeftShift] or mod[SDL.keymod.RightShift] then
                  mk = "Shift " .. mk
               end
               if mod[SDL.keymod.LeftAlt] or mod[SDL.keymod.RightAlt] then
                  mk = "Alt " .. mk
               end
               if mod[SDL.keymod.LeftControl] or mod[SDL.keymod.RightControl] then
                  mk = "Ctrl " .. mk
               end
               if (mk ~= "" and mk ~= "Shift ") or #k ~= 1 then
                  run_on_key(mk .. k, false, e["repeat"])
               end
            end
         elseif e.type == SDL.event.TextInput then
            run_on_key(e.text, true, e["repeat"])
         elseif e.type == SDL.event.MouseButtonDown then
            local objs = objects_under_mouse()
            focus = objs[1]
            update = true
         elseif e.type == SDL.event.MouseButtonUp then
            mouse_callback("on_click")
         elseif e.type == SDL.event.MouseWheel then
            mouse_callback("on_wheel", e.x, e.y)
         elseif e.type == SDL.event.MouseMotion then
            if e.state[1] == 1 then
               mouse_callback("on_drag", e.xrel, e.yrel)
            end
         else
            local w, h = win:getSize()
            root.w = w
            root.h = h
            root.children[1].max_w = w
            root.children[1].max_h = h
            root.children[1]:resize()
            update = true
         end
      end

      frame()

      if update then
         rdr:setDrawColor(alpha(0x000000))
         rdr:clear()

         draw_background()

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
