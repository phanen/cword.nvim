-- Parse vim.o.iskeyword into a set of codepoint rules and provide
-- a predicate. The rules are parsed lazily and cached by the
-- raw `vim.o.iskeyword` string, so flipping the option at
-- runtime (e.g. from a filetype plugin) is picked up on the
-- next call without a separate reload hook.
--
-- Nothing in this module runs at load time: callers reach
-- `is_keyword` which resolves the current option. That keeps
-- the test harness from triggering a parse with whatever
-- `vim.o.iskeyword` happens to be set in the runner.

local M = {}

local DEFAULT = '@,48-57,_,192-255'

---@param opt string  vim.o.iskeyword value (e.g. "@,48-57,_,192-255")
---@return table
function M.parse(opt)
  local rules = {}
  for part in (opt or ''):gmatch('[^,]+') do
    part = part:gsub('^%s+', ''):gsub('%s+$', '')
    if part == '@' then
      rules[#rules + 1] = { kind = 'alpha' }
    elseif part:match('^%d+%-%d+$') then
      local lo, hi = part:match('^(%d+)-(%d+)$')
      rules[#rules + 1] = { kind = 'range', lo = tonumber(lo), hi = tonumber(hi) }
    elseif #part > 0 then
      -- Vim's iskeyword can hold multi-byte literal chars per
      -- comma segment. Each byte in the segment is a codepoint.
      for i = 1, #part do
        rules[#rules + 1] = { kind = 'range', lo = string.byte(part, i), hi = string.byte(part, i) }
      end
    end
  end
  return rules
end

---Resolve the live vim.o.iskeyword, falling back to a sane
---default when no Neovim is around. The result is cached by the
---raw option string so a filetype that changes iskeyword is
---reflected on the next call.
---@return string
function M.current_opt()
  if vim and vim.o and vim.o.iskeyword ~= nil then
    return vim.o.iskeyword
  end
  return DEFAULT
end

local cache_opt = nil
local cache_rules = nil

---@return table
function M.current_rules()
  local opt = M.current_opt()
  if opt ~= cache_opt then
    cache_opt = opt
    cache_rules = M.parse(opt)
  end
  return cache_rules
end

---@param cp integer
---@return boolean
function M.is_keyword(cp)
  for _, r in ipairs(M.current_rules()) do
    if r.kind == 'alpha' then
      if cp >= 0x41 and cp <= 0x5A then
        return true
      end -- A-Z
      if cp >= 0x61 and cp <= 0x7A then
        return true
      end -- a-z
      if cp >= 0xC0 then
        return true
      end -- non-ASCII letters (incl. CJK)
    elseif r.kind == 'range' then
      if cp >= r.lo and cp <= r.hi then
        return true
      end
    end
  end
  return false
end

return M
