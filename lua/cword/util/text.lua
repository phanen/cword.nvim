local M = {}

M.is_whitespace = function(tok)
  return tok.text:match('^%s+$') ~= nil
end

local is_lead_byte = function(b)
  return b == nil or b < 0x80 or b >= 0xC0
end

---@param line string
---@param col integer 1-indexed byte column
---@return integer 1-indexed byte column of the multi-byte char's lead byte.
---If `col` is already on a character boundary, returns it unchanged.
M.char_start = function(line, col)
  while col >= 1 and not is_lead_byte(line:byte(col)) do
    col = col - 1
  end
  return col
end

---@param line string
---@param col integer 1-indexed byte column
---@param max_col integer inclusive upper bound; pass #line to allow snap to EOL.
---@return integer 1-indexed byte column of the byte just past the multi-byte
---char's trail byte (i.e. the next char's lead byte, or max_col+1 at EOL).
---If `col` is already on a character boundary, returns it unchanged.
M.char_end = function(line, col, max_col)
  while col <= max_col and not is_lead_byte(line:byte(col)) do
    col = col + 1
  end
  return col
end

return M
