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
  -- Track byte ranges separately so multi-byte chars whose
  -- first UTF-8 byte falls in such a range are also matched
  -- (matching nvim's live `\k` behavior).
  local byte_ranges = {}
  for token in string.gmatch(opt, '([^,]+)') do
    local range = token:match('^(%d+)-(%d+)$')
    if range then
      local lo, hi = tonumber(range), tonumber(token:match('-(%d+)$'))
      for cp = lo, hi do
        set[cp] = true
      end
      if lo >= 128 then
        byte_ranges[#byte_ranges + 1] = { lo, hi }
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
  return set, byte_ranges
end

-- Convert a codepoint to its UTF-8 first byte. Returns nil for
-- ASCII codepoints (no multi-byte first byte concept).
local function utf8_first_byte(cp)
  if cp < 0x80 then
    return nil
  elseif cp < 0x800 then
    return 0xC0 + math.floor(cp / 0x40)
  elseif cp < 0x10000 then
    return 0xE0 + math.floor(cp / 0x1000)
  else
    return 0xF0 + math.floor(cp / 0x40000)
  end
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
    local set, ranges = build_fallback_set()
    _fallback_set = set or {}
    _byte_ranges = ranges or {}
  end
  if _fallback_set[cp] == true then
    return true
  end
  -- Multi-byte char: check if its first UTF-8 byte falls in
  -- any of the configured byte ranges (e.g. 192-255).
  local fb = utf8_first_byte(cp)
  if fb then
    for _, r in ipairs(_byte_ranges) do
      if fb >= r[1] and fb <= r[2] then
        return true
      end
    end
  end
  return false
end

return M
