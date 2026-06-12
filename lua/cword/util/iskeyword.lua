-- Keyword character predicate powered by vim.regex('\k') when
-- available (Neovim). \k is evaluated at match time against the
-- live iskeyword option, so the regex never needs recompilation.
--
-- When run under the nvim-test runner harness (pure Lua, no
-- vim.regex) we fall back to parsing vim.o.iskeyword at load time
-- into a set of codepoints. This is a snapshot, not live, but it's
-- enough to drive the icu_ffi tests.
local M = {}

local _re = nil
local _fallback_set = nil

local function build_fallback_set()
  local opt = type(vim) == 'table' and type(vim.o) == 'table' and vim.o.iskeyword
  if not opt or opt == '' then
    return nil
  end
  -- Parse iskeyword options like "@,48-57,_,192-255,+-".
  local set = {}
  for token in string.gmatch(opt, '([^,]+)') do
    local range = token:match('^(%d+)-(%d+)$')
    if range then
      for cp = tonumber(range), tonumber(token:match('-(%d+)$')) do
        set[cp] = true
      end
    else
      local cp = token:match('^(%d+)$')
      if cp then
        set[tonumber(cp)] = true
      elseif #token == 1 then
        -- Bare character (e.g. `@`, `_`, `+`).
        set[string.byte(token)] = true
      end
    end
  end
  return set
end

---@param cp integer
---@return boolean
function M.is_keyword(cp)
  if type(vim) == 'table' and type(vim.regex) == 'function' then
    if not _re then
      _re = vim.regex('\\k')
    end
    return _re:match_str(vim.fn.nr2char(cp)) ~= nil
  end
  if not _fallback_set then
    _fallback_set = build_fallback_set() or {}
  end
  return _fallback_set[cp] == true
end

return M
