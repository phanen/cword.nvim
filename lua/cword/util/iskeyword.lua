-- Parse vim.o.iskeyword into a set of codepoint rules and provide
-- a predicate. Cached per module load (iskeyword rarely changes at
-- runtime).

local M = {}

---@param opt string  vim.o.iskeyword value (e.g. "@,48-57,_,192-255")
---@return table
local function parse(opt)
  local rules = {}
  for part in (opt or ''):gmatch('[^,]+') do
    part = part:gsub('^%s+', ''):gsub('%s+$', '')
    if part == '@' then
      rules[#rules + 1] = { kind = 'alpha' }
    elseif part:match('^%d+%-%d+$') then
      local lo, hi = part:match('^(%d+)-(%d+)$')
      rules[#rules + 1] = { kind = 'range', lo = tonumber(lo), hi = tonumber(hi) }
    elseif #part > 0 then
      -- Vim's iskeyword can hold multi-byte literal chars per comma
      -- segment. Each byte in the segment is a codepoint.
      for i = 1, #part do
        rules[#rules + 1] = { kind = 'range', lo = string.byte(part, i), hi = string.byte(part, i) }
      end
    end
  end
  return rules
end

---The parsed iskeyword rules, frozen at module init. iskeyword rarely
---changes; call M.reload() if you mutate it at runtime.
M.rules = vim and vim.o and parse(vim.o.iskeyword) or parse('@,48-57,_,192-255')

---Parse vim.o.iskeyword again. Call after the user toggles iskeyword.
function M.reload()
  if vim and vim.o then
    M.rules = parse(vim.o.iskeyword)
  else
    M.rules = parse('@,48-57,_,192-255')
  end
end

---@param cp integer
---@return boolean
function M.is_keyword(cp)
  for _, r in ipairs(M.rules) do
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
