-- Turn a string into a list of tokens.
--
-- Token shape:
--   { text, byte_start, byte_end, is_word_like }
--
-- byte_start/byte_end are 1-indexed and inclusive so that
-- string.sub(s, byte_start, byte_end) recovers the text exactly.

local M = {}

local BACKENDS = {
  cjk = 'cword.backends.cjk',
  icu = 'cword.backends.icu',
  icu_ffi = 'cword.backends.icu_ffi',
  char = 'cword.backends.char',
}

---@param opts table? { backend = "cjk"|"icu"|"char" }
---@return table
function M.new(opts)
  opts = opts or {}
  local name = opts.backend or 'cjk'
  local path = BACKENDS[name]
  if not path then
    local known = {}
    for k in pairs(BACKENDS) do
      known[#known + 1] = k
    end
    table.sort(known)
    error(string.format('cword: unknown backend %q (known: %s)', name, table.concat(known, ', ')))
  end
  return setmetatable({
    backend_name = name,
    backend = require(path),
  }, { __index = M })
end

---@param str string
---@return table[]
function M:cut(str)
  return self.backend.cut(str)
end

---@return string[]
function M.backends()
  local out = {}
  for k in pairs(BACKENDS) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

return M
