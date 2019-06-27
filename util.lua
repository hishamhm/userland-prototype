local util = {}

--- Return an array of keys of a table.
-- @param tbl table: The input table.
-- @return table: The array of keys.
function util.keys(tbl)
   local ks = {}
   for k,_ in pairs(tbl) do
      table.insert(ks, k)
   end
   return ks
end

--- Simple sort function used as a default for util.sortedpairs.
local function default_sort(a, b)
   local ta = type(a)
   local tb = type(b)
   if ta == "number" and tb == "number" then
      return a < b
   elseif ta == "number" then
      return true
   elseif tb == "number" then
      return false
   else
      return tostring(a) < tostring(b)
   end
end

--- A table iterator generator that returns elements sorted by key,
-- to be used in "for" loops.
-- @param tbl table: The table to be iterated.
-- @param sort_function function or table or nil: An optional comparison function
-- to be used by table.sort when sorting keys, or an array listing an explicit order
-- for keys. If a value itself is an array, it is taken so that the first element
-- is a string representing the field name, and the second element is a priority table
-- for that key, which is returned by the iterator as the third value after the key
-- and the value.
-- @return function: the iterator function.
function util.sortedpairs(tbl, sort_function)
   sort_function = sort_function or default_sort
   local keys = util.keys(tbl)
   local sub_orders = {}

   if type(sort_function) == "function" then
      table.sort(keys, sort_function)
   else
      local order = sort_function
      local ordered_keys = {}
      local all_keys = keys
      keys = {}

      for _, order_entry in ipairs(order) do
         local key, sub_order
         if type(order_entry) == "table" then
            key = order_entry[1]
            sub_order = order_entry[2]
         else
            key = order_entry
         end

         if tbl[key] then
            ordered_keys[key] = true
            sub_orders[key] = sub_order
            table.insert(keys, key)
         end
      end

      table.sort(all_keys, default_sort)
      for _, key in ipairs(all_keys) do
         if not ordered_keys[key] then
            table.insert(keys, key)
         end
      end
   end

   local i = 1
   return function()
      local key = keys[i]
      i = i + 1
      return key, tbl[key], sub_orders[key]
   end
end

return util
