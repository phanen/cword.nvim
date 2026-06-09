-- Spec helpers. Aliases itself to nvim-test.helpers when the runner
-- provides it (Phase 2 e2e), with a fallback eq for plain busted
-- (Phase 1). Domain helpers are added on top either way.

local M = {}

local ok, nvim_test = pcall(require, 'nvim-test.helpers')
if ok then
  M = nvim_test
end

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

---@param tokens table[]
---@return string
function M.text_of(tokens)
  local out = {}
  for i, t in ipairs(tokens) do
    out[i] = t.text
  end
  return table.concat(out, '|')
end

---@param tok table
---@return string
function M.slice(tok)
  return string.format('%d-%d', tok.byte_start, tok.byte_end)
end

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
