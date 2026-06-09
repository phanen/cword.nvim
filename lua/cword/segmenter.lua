-- Segmenter: turn a string into a list of tokens.
--
-- Token shape:
--   {
--     text        = string,   -- the token's text (UTF-8 byte sequence)
--     byte_start  = integer,  -- 1-indexed, inclusive (matches string.sub)
--     byte_end    = integer,  -- 1-indexed, inclusive
--     is_word_like = boolean, -- true if this token is a "word" (CJK char,
--                              -- ASCII identifier, etc.); false if it is
--                              -- whitespace or punctuation
--   }
--
-- The byte offsets are inclusive on both ends so that `string.sub(s,
-- byte_start, byte_end)` recovers the token's text exactly. This matches
-- Lua's native string indexing and avoids off-by-one traps.
--
-- Backends:
--   "cjk"  : default, each CJK char is its own word (predictable, no deps)
--   "icu"  : CJK runs grouped like ICU (no dictionary lookups)
--   "char" : every UTF-8 code point is its own token
--
-- A backend is just a module exposing `cut(str) -> token[]`. Adding a new
-- backend means dropping a file under `cword/backends/` and registering
-- the name in BACKENDS below.

local M = {}

local BACKENDS = {
  cjk = 'cword.backends.cjk',
  icu = 'cword.backends.icu',
  char = 'cword.backends.char',
}

---Create a new Segmenter.
---@param opts table? { backend = "cjk"|"icu"|"char" }
---@return table segmenter
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

---Cut a string into tokens.
---@param str string
---@return table[] tokens
function M:cut(str)
  return self.backend.cut(str)
end

---List known backend names.
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
