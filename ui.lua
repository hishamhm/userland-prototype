local ui = {}

local util = require("util")
local utf8 = require("utf8")

local bit = require("bit")

local love = love

local width = 1024
local height = 600
local E = {}

local root = { type = "root", x = 0, y = 0, children = {} }
local on_key_cb = function() end
local focus
local update = true

local font

local function blue(color)
   return bit.band(color, 0xff) / 0xff
end

local function green(color)
   return bit.band(bit.rshift(color, 8), 0xff) / 0xff
end

local function red(color)
   return bit.band(bit.rshift(color, 16), 0xff) / 0xff
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

local glow_curve = { 0.80, 0.40, 0.20, 0.10, 0.05 }

local function glow(rect, color)
   for i = 1, 5 do
      local factor = glow_curve[i]
      love.graphics.setColor(red(color), green(color), blue(color), factor)
      local r = expand(rect, i)
      love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
   end
end

function ui.set_focus(obj)
   focus = assert(obj)
   if focus.parent and focus.parent.scroll_v then
      if focus.y - focus.parent.scroll_v < 0 then
         focus.parent.scroll_v = focus.y
      end
      if focus.y - focus.parent.scroll_v + focus.h > focus.parent.h then
         focus.parent.scroll_v = focus.y - focus.parent.h + focus.h
      end
   end
   update = true
end

function ui.get_focus()
   return focus
end

function ui.init()
   love.window.setTitle("Userland")
   love.window.setMode(width, height, {
      centered = true,
      resizable = true,
   })

   font = love.graphics.newFont("DejaVuSansMono.ttf", 14)
   love.graphics.setFont(font)
   love.keyboard.setKeyRepeat(true)

   root.w, root.h = love.window.getMode()
end

function ui.image(filename, flags)
   flags = flags or {}
   local obj = {
      type = "image",
      x = flags.x,
      y = flags.y,
      w = flags.w,
      h = flags.h,
   }
   local img, err = Image.load(filename)
   if not img then
print(err)
      return nil, err
   end
   local w, h = img:getSize()
   obj.w = obj.w or w
   obj.h = obj.h or h

   obj.tex, err = rdr:createTextureFromSurface(img)
   if not obj.tex then
print(err)
      return nil, err
   end

   return obj
end

local function font_size(text)
   local h = font:getHeight()
   if text == "" then
      return 1, h
   else
      local w = font:getWidth(text)
      return w, h
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

local function text_backspace_char(self)
   if self.cursor > 0 then
      self.text = utf8_sub(self.text, 1, self.cursor - 1) .. utf8_sub(self.text, self.cursor + 1)
      self.cursor = self.cursor - 1
      self.tex = nil
      self.cursor_x = nil
   end
   self:resize()
   update = true
end

local function prev_word(self)
   local x = self.cursor - 1
   local len = utf8.len(self.text)
   while x > 0 do
      local c = utf8_sub(self.text, x, x)
      if c:match("^%W*$") then
         x = x - 1
      else
         break
      end
   end
   while x > 0 do
      local c = utf8_sub(self.text, x, x)
      if c:match("^%w*$") then
         x = x - 1
      else
         break
      end
   end
   return math.max(math.min(x, len), 0)
end

local function next_word(self)
   local x = self.cursor + 1
   local len = utf8.len(self.text)
   while x < len do
      local c = utf8_sub(self.text, x, x)
      if c:match("^%w*$") then
         x = x + 1
      else
         break
      end
   end
   while x < len do
      local c = utf8_sub(self.text, x, x)
      if c:match("^%W*$") then
         x = x + 1
      else
         x = x - 1
         break
      end
   end
   return math.max(math.min(x, len), 0)
end

local function text_backspace_word(self)
   if self.cursor > 0 then
      local x = prev_word(self)
      self.text = utf8_sub(self.text, 1, x) .. utf8_sub(self.text, self.cursor + 1)
      self.cursor = x
      self.tex = nil
      self.cursor_x = nil
   end
   self:resize()
   update = true
end

local function text_delete_char(self)
   if self.cursor < utf8.len(self.text) then
      self.text = utf8_sub(self.text, 1, self.cursor) .. utf8_sub(self.text, self.cursor + 2)
      self.tex = nil
      self.cursor_x = nil
   end
   self:resize()
   update = true
end

local function text_cursor_move_char(self, rel)
   local new_value = math.min(math.max(0, self.cursor + rel), utf8.len(self.text))
   if self.cursor ~= new_value then
      self.cursor = new_value
      self.cursor_x = nil
      update = true
   end
end

local function text_cursor_move_word(self, rel)
   local old_value = self.cursor
   if rel < 0 and self.cursor > 0 then
      for _ = rel, -1 do
         self.cursor = prev_word(self)
      end
   elseif rel > 0 and self.cursor < utf8.len(self.text) then
      for _ = 1, rel do
         self.cursor = next_word(self)
      end
   end
   if self.cursor ~= old_value then
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
   self.cursor_x = w + 1
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
   if key == "backspace" then
      self:backspace_char()
      self:resize()
      return true
   elseif key == "Ctrl backspace" or key == "Alt backspace" then
      self:backspace_word()
      self:resize()
      return true
   elseif key == "delete" then
      self:delete_char()
      self:resize()
      return true
   elseif key == "Ctrl left" then
      self:cursor_move_word(-1)
      return true
   elseif key == "Ctrl right" then
      self:cursor_move_word(1)
      return true
   elseif key == "left" then
      self:cursor_move_char(-1)
      return true
   elseif key == "right" then
      self:cursor_move_char(1)
      return true
   elseif key == "home" then
      self:cursor_set(0)
      return true
   elseif key == "end" then
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

local function text_as_text(self)
   return self.text
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
      focusable = flags.focusable,
      color = flags.color or 0xffffff,
      fill = flags.fill,
      border = flags.border,
      data = flags.data,
      on_key_cb = flags.on_key,

      cursor = math.max(math.min(flags.cursor or 0, #text), 0),
      text = text,
      render = text_render,
      add = text_add,
      set = text_set,
      cursor_set = text_cursor_set,
      cursor_move_char = text_cursor_move_char,
      cursor_move_word = text_cursor_move_word,
      backspace_char = text_backspace_char,
      backspace_word = text_backspace_word,
      delete_char = text_delete_char,
      calc_cursor_x = text_calc_cursor_x,
      resize = text_resize,
      on_key = flags.editable and text_on_key,
      on_click = flags.on_click,
      as_text = text_as_text,
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
      tree:remove_n_children_at(#collapse, pos + 1)
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

function ui.tree(flags, tree)
   flags.scroll_by = 17
   local box = ui.vbox(flags)
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

   update = true
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

--- Removes n children starting at a given position.
-- Calling this method with no arguments removes all children.
-- @param self the box object
-- @param n amount of children to remove (defaults to all children)
-- @param pos position of the first child to remove (defaults to 1)
local function box_remove_n_children_at(self, n, pos)
   n = n or #self.children
   pos = pos or 1
   for _ = pos, math.min(pos + n - 1, #self.children) do
      detach(self.children[pos])
   end
   self:resize()
   update = true
end

local function box_replace_child(self, old, new)
   for i, c in ipairs(self.children) do
      if c == old then
         detach(old)
         new.parent = self
         self.children[i] = new
         self:resize()
         update = true
         return
      end
   end
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

function ui.above(t, k)
   if t.name == k then
      return t
   end
   if t.parent then
      local p, err = ui.above(t.parent, k)
      if not p then
         return nil, "< " .. (t.name or t.type) .. " " .. err
      end
      return p
   end
   return nil, "< " .. (t.name or t.type)
end

function ui.below(t, k)
   if t.name == k then
      return t
   end
   if not t.children then
      return nil
   end
   for _, child in ipairs(t.children) do
      if child.name == k then
         return child
      end
   end
   for _, child in ipairs(t.children) do
      if type(child) == "table" and child.children then
         local found = ui.below(child, k)
         if found then
            return found
         end
      end
   end
end

local function box_as_text(self)
   local out = {}
   for i, child in ipairs(self.children) do
      out[i] = child:as_text()
   end
   return table.concat(out, self.type == "vbox" and "\n" or nil)
end

local function ui_box(flags, children, type)
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
      focus_fill_color = flags.focus_fill_color,
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
      remove_n_children_at = box_remove_n_children_at,
      replace_child = box_replace_child,
      as_text = box_as_text,
   }

   for _, child in ipairs(obj.children) do
      detach(child)
      child.parent = obj
   end

   obj:resize()
   return obj
end

function ui.vbox(flags, children)
   return ui_box(flags, children, "vbox")
end

function ui.hbox(flags, children)
   return ui_box(flags, children, "hbox")
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
   -- FIXME
   update = true
end

function ui.fullscreen(mode)
   love.window.setFullscreen(mode)
   local w, h = love.window.getMode()
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
   ["lctrl"] = true,
   ["lalt"] = true,
   ["lshift"] = true,
   ["lgui"] = true,
   ["rctrl"] = true,
   ["ralt"] = true,
   ["rshift"] = true,
}

local draw

local function box_draw(self, off, clip)
   local offself = offset(self, off)
   if self.fill then
      love.graphics.setColor(red(self.fill), green(self.fill), blue(self.fill))
      love.graphics.rectangle("fill", offself.x, offself.y, offself.w, offself.h)
   end
   if self.border then
      local color = (self == focus or self == focus.parent) and self.focus_border or self.border
      if self == focus or self == focus.parent then
         love.graphics.setScissor()
         glow(offself, color)
      end
      love.graphics.setColor(red(color), green(color), blue(color))
      love.graphics.rectangle("line", offself.x, offself.y, offself.w, offself.h)
      love.graphics.setScissor(clip.x, clip.y, clip.w, clip.h)
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

--local function copy_to_rdr(obj, off)
--   if obj.tex then
--      local src = { x = 0, y = 0, w = obj.w, h = obj.h }
--      rdr:copy(obj.tex, src, offset(obj, off))
--   end
--end

local function intersect_rect(r1, r2)
--print("intersect ", r1.x.."x"..r1.y.."+"..r1.w.."+"..r1.h, r2.x.."x"..r2.y.."+"..r2.w.."+"..r2.h)
   if r1.x + r1.w - 1 < r2.x
   or r2.x + r2.w - 1 < r1.x
   or r1.y + r1.h - 1 < r2.y
   or r2.y + r2.h - 1 < r1.y
   then
      return false
   end
   local x1 = math.max(r1.x, r2.x)
   local x2 = math.min(r1.x + r1.w - 1, r2.x + r2.w - 1)
   local y1 = math.max(r1.y, r2.y)
   local y2 = math.min(r1.y + r1.h - 1, r2.y + r2.h - 1)
   local res = {
      x = x1,
      y = y1,
      w = x2 - x1,
      h = y2 - y1,
   }
--print("res ", res.x.."x"..res.y.."+"..res.w.."+"..res.h)
   return true, res
end

draw = function(obj, off, clip)
   clip = clip or root

   local offobj = offset(obj, off)
   local ok
   local prevclip = clip
   ok, clip = intersect_rect(clip, offobj)
   if not ok then
      return false
   end

   if obj == focus and obj.parent.focus_fill_color then
      local ok, r = intersect_rect(expand(prevclip, -1), offset({ x = 1, y = obj.y, w = obj.parent.w - 2, h = obj.h }, off))
      if ok then
         love.graphics.setScissor(r.x, r.y, r.w, r.h)
         local color = obj.parent.focus_fill_color
         love.graphics.setColor(red(color), green(color), blue(color))
         love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
      end
   end


--print("clip: ", clip.x, clip.y, clip.w, clip.h)
   love.graphics.setScissor(clip.x, clip.y, clip.w, clip.h)

--do return true end

   if obj.type == "image" then
      if not obj.tex then
         obj:render()
      end
      --copy_to_rdr(obj, off)
   elseif obj.type == "text" then
      if obj.fill then
         love.graphics.setColor(red(obj.fill), green(obj.fill), blue(obj.fill))
         love.graphics.rectangle("fill", offobj.x, offobj.y, offobj.w, offobj.h)
      end
      if obj.border then
         local color = obj == focus and obj.focus_border or obj.border
         love.graphics.setColor(red(color), green(color), blue(color))
         love.graphics.rectangle("line", offobj.x, offobj.y, offobj.w, offobj.h)
      end

      if not obj.tex then
         obj.tex = true
         obj.w, obj.h = font_size(obj.text)
      end

      local show_cursor = obj.editable and (obj == focus or ui.above(obj, "cell") == focus)
      local line
      if show_cursor then
         if not obj.cursor_x then
            obj:calc_cursor_x()
         end
         clip.w = clip.w + 10
         line = { x1 = obj.x + obj.cursor_x + off.x, y1 = obj.y + 1 + off.y, x2 = obj.x + obj.cursor_x + off.x, y2 = obj.y + obj.h - 2 + off.y }
         if focus == obj then
            love.graphics.setScissor()
            glow({ x = line.x1, y = line.y1, w = 1, h = (line.y2 - line.y1 + 1) }, 0x009999)
         end
      end

      love.graphics.setScissor(clip.x, clip.y, clip.w, clip.h)
      love.graphics.setColor(red(obj.color), green(obj.color), blue(obj.color))
      love.graphics.print(obj.text, offobj.x, offobj.y)

      if show_cursor then
         if focus == obj then
            love.graphics.setColor(1, 1, 1)
         else
            love.graphics.setColor(0, 0.6, 0.6)
         end
         love.graphics.line(line.x1, line.y1, line.x2, line.y2)
      end
   elseif obj.type == "rect" then
      if obj.fill then
         love.graphics.setColor(red(obj.fill), green(obj.fill), blue(obj.fill))
         love.graphics.rectangle("fill", offobj.x, offobj.y, offobj.w, offobj.h)
      end
      if obj.border then
         local color = obj == focus and obj.focus_border or obj.border
         love.graphics.setColor(red(color), green(color), blue(color))
         love.graphics.rectangle("line", offobj.x, offobj.y, offobj.w, offobj.h)
      end
   elseif obj.type == "vbox" then
      box_draw(obj, off, clip)
   elseif obj.type == "hbox" then
      box_draw(obj, off, clip)
   end
end

local function run_on_key(key, is_text, is_repeat)
   if focus then
      local f = focus
      while f do
         if f.on_key then
            local done = f:on_key(key, is_text, is_repeat, focus)
            if done then
               return
            end
         end
         f = f.parent
      end
   end
   if on_key_cb then
      on_key_cb(focus, key, is_text, is_repeat, focus)
   end
end

local function point_in_rect(p, r)
   return p.x >= r.x and p.x <= r.x + r.w - 1
      and p.y >= r.y and p.y <= r.y + r.h - 1
end

local function objects_under_mouse(obj, off, rets, p)
   obj = obj or root
   off = off or { x = 0, y = 0 }
   rets = rets or {}
   if not p then
      local x, y = love.mouse.getPosition()
      p = { x = x, y = y }
   end
   if obj.children then
      for _, child in ipairs(obj.children) do
         local offchild = offset(child, off)
         if point_in_rect(p, offchild) then
            offchild.y = offchild.y - (child.scroll_v or 0)
            offchild.x = offchild.x - (child.scroll_h or 0)
            objects_under_mouse(child, offchild, rets, p)
         end
      end
   end
   table.insert(rets, obj)
   return rets
end

local function draw_background()
   love.graphics.setScissor(0, 0, root.w, root.h)

   local D1 = 200
   local D2 = 100

   love.graphics.setColor(0, 0.2, 0.2)
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_h / 4) % D2), root.w, D2 do
      love.graphics.line(i, 0, i, root.h)
   end
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_v / 4) % D2), root.h, D2 do
      love.graphics.line(0, i, root.w, i)
   end

   love.graphics.setColor(0, 0.5, 0.5)
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_h / 2) % D1), root.w, D1 do
      love.graphics.line(i, 0, i, root.h)
   end
   for i = math.floor(D1/2) - (math.floor(root.children[1].scroll_v / 2) % D1), root.h, D1 do
      love.graphics.line(0, i, root.w, i)
   end
end

local mouse_obj

local function mouse_callback(cb_name, x, y)
   if mouse_obj then
      mouse_obj[cb_name](mouse_obj, x, y)
      return
   end
   local objs = objects_under_mouse()
--   for _, obj in ipairs(objs) do
--      io.write((obj.name or obj.type) .. " ")
--   end
--   io.write("\n")
   for _, obj in ipairs(objs) do
      if obj[cb_name] then
         mouse_obj = obj
         obj[cb_name](obj, x, y)
         return
      end
   end
end

local modstate = {}
local mousestate = {}

function ui.run(frame)
   root.on_wheel = function(_, x, y)
      root.children[1]:on_wheel(x, y)
   end
   root.on_drag = function(_, x, y)
      root.children[1]:on_drag(x, y)
   end

   function love.keyreleased(key, scancode)
      if ismod[key] then
         modstate[key] = false
      end
   end

   function love.keypressed(key, scancode, isrepeat)
print("keypressed", key, scancode, isrepeat)
      if ismod[key] then
         modstate[key] = true
      else
         local mk = ""
         if modstate["lgui"] then
            mk = "Win " .. mk
         end
         if modstate["lshift"] or modstate["rshift"] then
            mk = "Shift " .. mk
         end
         if modstate["lalt"] or modstate["ralt"] then
            mk = "Alt " .. mk
         end
         if modstate["lctrl"] or modstate["rctrl"] then
            mk = "Ctrl " .. mk
         end
         if (mk ~= "" and mk ~= "Shift ") or #key ~= 1 then
            run_on_key(mk .. key, false, isrepeat)
         end
      end
   end

   function love.textinput(text)
print("textinput", text)
      run_on_key(text, true, false)
   end

   function love.mousepressed(x, y, button)
      mousestate[button] = true
      local objs = objects_under_mouse()
      for _, obj in ipairs(objs) do
         if not (obj.focusable == false) then
            ui.set_focus(obj)
            break
         end
      end
      update = true
   end

   function love.mousereleased(x, y, button)
      mousestate[button] = false
      mouse_obj = nil
      mouse_callback("on_click")
      mouse_obj = nil
   end

   function love.wheelmoved(x, y)
      mouse_callback("on_wheel", x, y)
   end

   function love.mousemoved(x, y, dx, dy)
      if mousestate[1] then
         mouse_callback("on_drag", dx, dy)
      else
         mouse_obj = nil
      end
   end

   function love.update(dt)
      local w, h = love.window.getMode()
      root.w = w
      root.h = h
      root.children[1].max_w = w
      root.children[1].max_h = h
      root.children[1]:resize()

      frame()
      update = true
   end

   function love.draw()
      if update then
--         love.graphics.setBackgroundColor(0, 0, 0)
         love.graphics.clear()
--
         draw_background()
--
         for _, child in ipairs(root.children) do
            child.parent = root
            draw(child, root, root)
         end
         update = false
      end
      love.graphics.setScissor()
   end
end

return ui
