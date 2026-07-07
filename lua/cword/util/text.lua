---@param tok table
---@return boolean
local function is_whitespace(tok)
  return tok.text:match('^%s+$') ~= nil
end

return { is_whitespace = is_whitespace }
