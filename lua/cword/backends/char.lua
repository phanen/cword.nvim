-- Every UTF-8 code point is its own token. Strictest possible cut.

local utf8 = require('cword.util.utf8')

local M = {}

local function is_space(cp)
  return cp == 0x09 or cp == 0x0A or cp == 0x0B or cp == 0x0C or cp == 0x0D or cp == 0x20
end

---@param str string
---@return table[]
function M.cut(str)
  local tokens = {}
  local i = 1
  local len = #str
  while i <= len do
    local clen = utf8.char_len(string.byte(str, i))
    local cp = utf8.codepoint(str, i)
    tokens[#tokens + 1] = {
      text = string.sub(str, i, i + clen - 1),
      byte_start = i,
      byte_end = i + clen - 1,
      is_word_like = not is_space(cp),
    }
    i = i + clen
  end
  return tokens
end

return M
