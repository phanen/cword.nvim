-- Keyword character predicate powered by vim.regex('\k'). \k is
-- evaluated at match time against the live iskeyword option, so the
-- regex never needs recompilation.
local M = {}

local _re = vim.regex('\\k')

---@param cp integer
---@return boolean
function M.is_keyword(cp)
  return _re:match_str(vim.fn.nr2char(cp)) ~= nil
end

return M
