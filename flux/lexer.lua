local lexer = {}

--------------------------------------------------------------------------------
-- Lexer (taken from tl lexer)
--------------------------------------------------------------------------------

function lexer.lex(input)
   local tokens = {}

   local state = "any"
   local fwd = true
   local y = 1
   local x = 0
   local i = 0
   local lc_open_lvl = 0
   local lc_close_lvl = 0
   local ls_open_lvl = 0
   local ls_close_lvl = 0

   local function begin_token()
      table.insert(tokens, { x = x, y = y, i = i })
   end

   local function drop_token()
      table.remove(tokens)
   end

   local function end_token(kind, t, last)
      assert(type(kind) == "string")

      local token = tokens[#tokens]
      token.tk = t or input:sub(token.i, last or i) or ""
      token.kind = kind
   end

   while i <= #input do
      if fwd then
         i = i + 1
      end
      if i > #input then
         break
      end

      local c = input:sub(i, i)

      if fwd then
         if c == "\n" then
            y = y + 1
            x = 0
         else
            x = x + 1
         end
      else
         fwd = true
      end

      if state == "any" then
         if c == "-" then
            state = "maybecomment"
            begin_token()
         elseif c == "." then
            state = "maybedotdot"
            begin_token()
         elseif c == "\"" then
            state = "dblquote_string"
            begin_token()
         elseif c == "'" then
            state = "singlequote_string"
            begin_token()
         elseif c:match("[a-zA-Z_$]") then
            state = "word"
            begin_token()
         elseif c:match("[0-9]") then
            state = "number"
            begin_token()
         elseif c:match("[<>=~]") then
            state = "maybeequals"
            begin_token()
         elseif c == "[" then
            state = "maybelongstring"
            begin_token()
         elseif c:match("[+*/]") then
            begin_token()
            end_token("op", nil, nil)
         elseif c:match("%s") then
            -- do nothing
         else
            begin_token()
            end_token(c, nil, nil)
         end
      elseif state == "maybecomment" then
         if c == "-" then
            state = "maybecomment2"
         else
            end_token("op", "-")
            fwd = false
            state = "any"
         end
      elseif state == "maybecomment2" then
         if c == "[" then
            state = "maybelongcomment"
         else
            state = "comment"
            drop_token()
         end
      elseif state == "maybelongcomment" then
         if c == "[" then
            state = "longcomment"
         elseif c == "=" then
            lc_open_lvl = lc_open_lvl + 1
         else
            state = "comment"
            drop_token()
            lc_open_lvl = 0
         end
      elseif state == "longcomment" then
         if c == "]" then
            state = "maybelongcommentend"
         end
      elseif state == "maybelongcommentend" then
         if c == "]" and lc_close_lvl == lc_open_lvl then
            drop_token()
            state = "any"
            lc_open_lvl = 0
            lc_close_lvl = 0
         elseif c == "=" then
            lc_close_lvl = lc_close_lvl + 1
         else
            state = "longcomment"
            lc_close_lvl = 0
         end
      elseif state == "dblquote_string" then
         if c == "\\" then
            state = "escape_dblquote_string"
         elseif c == "\"" then
            end_token("string")
            state = "any"
         end
      elseif state == "escape_dblquote_string" then
         state = "dblquote_string"
      elseif state == "singlequote_string" then
         if c == "\\" then
            state = "escape_singlequote_string"
         elseif c == "'" then
            end_token("string")
            state = "any"
         end
      elseif state == "escape_singlequote_string" then
         state = "singlequote_string"
      elseif state == "maybeequals" then
         if c == "=" then
            end_token("op")
            state = "any"
         else
            end_token("=", nil, i - 1)
            fwd = false
            state = "any"
         end
      elseif state == "maybelongstring" then
         if c == "[" then
            state = "longstring"
         elseif c == "=" then
            ls_open_lvl = ls_open_lvl + 1
         else
            end_token("[", nil, i - 1)
            fwd = false
            state = "any"
            ls_open_lvl = 0
         end
      elseif state == "longstring" then
         if c == "]" then
            state = "maybelongstringend"
         end
      elseif state == "maybelongstringend" then
         if c == "]" and ls_close_lvl == ls_open_lvl then
            end_token("string")
            state = "any"
            ls_open_lvl = 0
            ls_close_lvl = 0
         elseif c == "=" then
            ls_close_lvl = ls_close_lvl + 1
         else
            state = "longstring"
            ls_close_lvl = 0
         end
      elseif state == "maybedotdot" then
         if c == "." then
            end_token("op")
            state = "maybedotdotdot"
         else
            end_token(".", nil, i - 1)
            fwd = false
            state = "any"
         end
      elseif state == "maybedotdotdot" then
         if c == "." then
            end_token("...")
            state = "any"
         else
            end_token("op", nil, i - 1)
            fwd = false
            state = "any"
         end
      elseif state == "comment" then
         if c == "\n" then
            state = "any"
         end
      elseif state == "word" then
         if not c:match("[a-zA-Z0-9_]") then
            end_token("word", nil, i - 1)
            fwd = false
            state = "any"
         end
      elseif state == "number" then
         if not c:match("[0-9]") then
            end_token("number", nil, i - 1)
            fwd = false
            state = "any"
         end
      end
   end

   if #tokens > 0 then
      local last = tokens[#tokens]
      if last.tk == nil then
         if state == "word" or state == "number" then
            end_token(state, nil, i - 1)
         else
            end_token("incomplete", nil, i - 1)
         end
      end
      table.insert(tokens, { y = last.y, x = last.x + #last.tk, tk = "$EOF$", kind = "$EOF$" })
   else
      table.insert(tokens, { y = 1, x = 1, tk = "$EOF$", kind = "$EOF$" })
   end

   return tokens
end

function lexer.tokenize(input)
   local tks = lexer.lex(input)
   local raw_tokens = {}
   for i = 1, #tks - 1 do
      raw_tokens[i] = tks[i].tk
   end
   return raw_tokens
end

return lexer
