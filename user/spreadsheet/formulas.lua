local formulas = {}

local lexer = require("flux.lexer")

--------------------------------------------------------------------------------
-- Formula parser (taken from tl expression parser)
--------------------------------------------------------------------------------

local function fail(tokens, i, errs, msg)
   if not tokens[i] then
      local eof = tokens[#tokens]
      table.insert(errs, { y = eof.y, x = eof.x, msg = msg or "unexpected end of file" })
      return #tokens
   end
   table.insert(errs, { y = tokens[i].y, x = tokens[i].x, msg = msg or debug.traceback() })
   return i + 1
end

local function verify_tk(tokens, i, errs, tk)
   if tokens[i].tk == tk then
      return i + 1
   end
   return fail(tokens, i, errs)
end

local function new_node(tokens, i, kind)
   local t = tokens[i]
   return { y = t.y, x = t.x, tk = t.tk, kind = kind or t.kind }
end

local function verify_kind(tokens, i, errs, kind, node_kind)
   if tokens[i].kind == kind then
      return i + 1, new_node(tokens, i, node_kind)
   end
   return fail(tokens, i, errs)
end

local function parse_literal(tokens, i, errs)
   if tokens[i].kind == "string" then
      return verify_kind(tokens, i, errs, "string")
   elseif tokens[i].kind == "word" then
      return verify_kind(tokens, i, errs, "word", "variable")
   elseif tokens[i].kind == "number" then
      return verify_kind(tokens, i, errs, "number")
   elseif tokens[i].tk == "true" then
      return verify_kind(tokens, i, errs, "keyword", "boolean")
   elseif tokens[i].tk == "false" then
      return verify_kind(tokens, i, errs, "keyword", "boolean")
   elseif tokens[i].tk == "nil" then
      return verify_kind(tokens, i, errs, "keyword", "nil")
   end
   return fail(tokens, i, errs)
end

local function parse_list(tokens, i, errs, list, close, is_sep, parse_item)
   local n = 1
   while tokens[i].kind ~= "$EOF$" do
      if close[tokens[i].tk] then
         break
      end
      local item
      i, item, n = parse_item(tokens, i, errs, n)
      table.insert(list, item)
      if tokens[i].tk == "," then
         i = i + 1
         if is_sep and close[tokens[i].tk] then
            return fail(tokens, i, errs)
         end
      end
   end
   return i, list
end

local function parse_bracket_list(tokens, i, errs, list, open, close, is_sep, parse_item)
   i = verify_tk(tokens, i, errs, open)
   i = parse_list(tokens, i, errs, list, { [close] = true }, is_sep, parse_item)
   i = i + 1
   return i, list
end

local parse_expression

-- Shunting-yard algorithm for parsing expressions, as described in
-- https://www.engr.mun.ca/~theo/Misc/exp_parsing.htm#shunting_yard
do
   local precedences = {
      [1] = {
         ["not"] = 11,
         ["#"] = 11,
         ["-"] = 11,
         ["~"] = 11,
      },
      [2] = {
         ["or"] = 1,
         ["and"] = 2,
         ["<"] = 3,
         [">"] = 3,
         ["<="] = 3,
         [">="] = 3,
         ["~="] = 3,
         ["=="] = 3,
         ["|"] = 4,
         ["~"] = 5,
         ["&"] = 6,
         ["<<"] = 7,
         [">>"] = 7,
         [".."] = 8,
         ["+"] = 8,
         ["-"] = 9,
         ["*"] = 10,
         ["/"] = 10,
         ["//"] = 10,
         ["%"] = 10,
         ["^"] = 12,
         ["@funcall"] = 100,
         ["@index"] = 100,
         ["."] = 100,
         [":"] = 100,
      },
   }

   local sentinel = { op = "sentinel" }

   local function is_unop(token)
      return precedences[1][token.tk] ~= nil
   end

   local function is_binop(token)
      return precedences[2][token.tk] ~= nil
   end

   local function prec(op)
      if op == sentinel then
         return -9999
      end
      return precedences[op.arity][op.op]
   end

   local function pop_operator(operators, operands)
      if operators[#operators].arity == 2 then
         local t2 = table.remove(operands)
         local t1 = table.remove(operands)
         if not t1 or not t2 then
            return false
         end
         local operator = table.remove(operators)
         table.insert(operands, { y = t1.y, x = t1.x, kind = "op", op = operator, e1 = t1, e2 = t2 })
      else
         local t1 = table.remove(operands)
         table.insert(operands, { y = t1.y, x = t1.x, kind = "op", op = table.remove(operators), e1 = t1 })
      end
      return true
   end

   local function push_operator(op, operators, operands)
      while #operands > 0 and prec(operators[#operators]) >= prec(op) do
         local ok = pop_operator(operators, operands)
         if not ok then
            return false
         end
      end
      op.prec = assert(precedences[op.arity][op.op])
      table.insert(operators, op)
      return true
   end

   local P
   local E

   P = function(tokens, i, errs, operators, operands)
      if tokens[i].kind == "$EOF$" then
         return i
      end
      if is_unop(tokens[i]) then
         local ok = push_operator({ y = tokens[i].y, x = tokens[i].x, arity = 1, op = tokens[i].tk }, operators, operands)
         if not ok then
            return fail(tokens, i, errs)
         end
         i = i + 1
         i = P(tokens, i, errs, operators, operands)
         return i
      elseif tokens[i].tk == "(" then
         i = i + 1
         table.insert(operators, sentinel)
         i = E(tokens, i, errs, operators, operands)
         i = verify_tk(tokens, i, errs, ")")
         table.remove(operators)
         return i
      else
         local leaf
         i, leaf = parse_literal(tokens, i, errs)
         if leaf then
            table.insert(operands, leaf)
         end
         return i
      end
   end

   local function push_arguments(tokens, i, errs, operands)
      local args
      local node = new_node(tokens, i, "expression_list")
      i, args = parse_bracket_list(tokens, i, errs, node, "(", ")", true, parse_expression)
      table.insert(operands, args)
      return i
   end

   local function push_index(tokens, i, errs, operands)
      local arg
      i = verify_tk(tokens, i, errs, "[")
      i, arg = parse_expression(tokens, i, errs)
      i = verify_tk(tokens, i, errs, "]")
      table.insert(operands, arg)
      return i
   end

   E = function(tokens, i, errs, operators, operands)
      if tokens[i].kind == "$EOF$" then
         return i
      end
      i = P(tokens, i, errs, operators, operands)
      while tokens[i].kind ~= "$EOF$" do
         if tokens[i].tk == "(" then
            local ok = push_operator({ y = tokens[i].y, x = tokens[i].x, arity = 2, op = "@funcall" }, operators, operands)
            if not ok then
               return fail(tokens, i, errs)
            end
            i = push_arguments(tokens, i, errs, operands)
         elseif tokens[i].tk == "[" then
            local ok = push_operator({ y = tokens[i].y, x = tokens[i].x, arity = 2, op = "@index" }, operators, operands)
            if not ok then
               return fail(tokens, i, errs)
            end
            i = push_index(tokens, i, errs, operands)
         elseif is_binop(tokens[i]) then
            local ok = push_operator({ y = tokens[i].y, x = tokens[i].x, arity = 2, op = tokens[i].tk }, operators, operands)
            if not ok then
               return fail(tokens, i, errs)
            end
            i = i + 1
            i = P(tokens, i, errs, operators, operands)
         else
            break
         end
      end
      while operators[#operators] ~= sentinel do
         local ok = pop_operator(operators, operands)
         if not ok then
            return fail(tokens, i, errs)
         end
      end
      return i
   end

   parse_expression = function(tokens, i, errs)
      local operands = {}
      local operators = {}
      table.insert(operators, sentinel)
      i = E(tokens, i, errs, operators, operands)
      return i, operands[#operands], 0
   end
end


function formulas.parse(formula)
   local errs = {}
--print(require'inspect'(lex(formula)))
   local i, ast = parse_expression(lexer.lex(formula), 1, errs)
   if next(errs) then
      return nil, errs
   end
   return ast
end

--------------------------------------------------------------------------------
-- Formula evaluator
--------------------------------------------------------------------------------

function formulas.eval(ast, cell_value)
   if ast.kind == "op" then
      local e1, e2
      e1 = formulas.eval(ast.e1, cell_value)
      if ast.op.arity == 2 then
         e2 = formulas.eval(ast.e2, cell_value)
      end
      if ast.op.op == ".." then
         return tostring(e1) .. tostring(e2)
      end
      e1 = tonumber(e1)
      if not e1 then
         return "?ERR"
      end
      e2 = tonumber(e2)
      if not e2 then
         return "?ERR"
      end
      if ast.op.op == "+" then
         return e1 + e2
      elseif ast.op.op == "-" then
         return e1 - e2
      elseif ast.op.op == "*" then
         return e1 * e2
      elseif ast.op.op == "/" then
         return e1 / e2
      end
   elseif ast.kind == "variable" then
      return cell_value(ast.tk)
   elseif ast.kind == "number" then
      return tonumber(ast.tk)
   end
   return 0
end

return formulas
