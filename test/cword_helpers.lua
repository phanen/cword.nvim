-- Spec entry point. Pattern after gitsigns.nvim's test/gs_helpers.lua:
-- re-export `nvim-test.helpers` when the runner provides it, then layer
-- the cword domain helpers on top. Specs always go through this module,
-- so the same `describe`/`it`/`eq`/etc. surface works under plain
-- busted (Phase 1, no nvim-test) and under nvim-test (Phase 2 e2e).
--
-- Spec usage:
--
--   local helpers = require('test.cword_helpers')
--   helpers.eq('foo', helpers.text_of(seg:cut('foo')))
--
-- Under nvim-test, `helpers` transparently exposes everything
-- nvim-test.helpers does (`exec_lua`, `feed`, `clear`, `api`, `fn`,
-- `Screen`, etc.), so motion specs can call `helpers.feed('w')` and
-- `Screen.new(...):expect(...)` without a separate require.

local M = {}

local ok, nvim_test = pcall(require, 'nvim-test.helpers')
if ok then
  -- Direct aliasing instead of copy: same trick gitsigns uses. Mutating
  -- the shared nvim-test table is fine here because cword_helpers is
  -- the only consumer in this test tree.
  M = nvim_test
end

-- Fallback `eq` for plain busted (when nvim-test is not on the path).
-- Same semantics as `assert.are.same`: deep-equal with a clear failure
-- message that names both sides.
if not M.eq then
  local function inspect(v)
    if type(v) == 'string' then
      return string.format('%q', v)
    end
    if type(v) == 'table' then
      local parts = {}
      for i, x in ipairs(v) do
        parts[i] = inspect(x)
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end
    return tostring(v)
  end

  function M.eq(expected, actual, msg)
    if expected ~= actual then
      local prefix = msg and (msg .. ': ') or ''
      error(string.format('%sexpected %s, got %s', prefix, inspect(expected), inspect(actual)), 2)
    end
  end
end

-- Domain helpers for cword specs.

---Concatenate token texts with `|` as a separator.
---@param tokens table[]
---@return string
function M.text_of(tokens)
  local out = {}
  for i, t in ipairs(tokens) do
    out[i] = t.text
  end
  return table.concat(out, '|')
end

---Format a token's byte range as "start-end".
---@param tok table
---@return string
function M.slice(tok)
  return string.format('%d-%d', tok.byte_start, tok.byte_end)
end

---Pretty-print a token list. Useful for debugging a failing spec.
---@param tokens table[]
---@return string
function M.fmt_tokens(tokens)
  local parts = {}
  for _, t in ipairs(tokens) do
    parts[#parts + 1] =
      string.format('%s[%d-%d,w=%s]', t.text, t.byte_start, t.byte_end, tostring(t.is_word_like))
  end
  return '{' .. table.concat(parts, ' ') .. '}'
end

return M
