-- Keyword character predicate powered by vim.regex('\\k').
-- The regex object is cached until vim.o.iskeyword changes.
local M = {}

local _re = nil
local _last_ik = nil

---@param cp integer
---@return boolean
function M.is_keyword(cp)
  local ik = vim.o.iskeyword
  if ik ~= _last_ik then
    _re = vim.regex('\\k')
    _last_ik = ik
  end
  return _re:match_str(vim.fn.nr2char(cp)) ~= nil
end

return M
