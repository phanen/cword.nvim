-- Shared helpers for cword specs.
-- Run via: busted --lpath='lua/?.lua;lua/?/init.lua' test/
-- or:      make test

local M = {}

---Format a value for display in error messages. Avoids depending on
---`vim.inspect` so this also works when specs are run with plain Lua
---+ busted (no Neovim).
---@param v any
---@return string
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

---Strict equality with a clear failure message.
---Argument order matches gitsigns.nvim convention: expected, actual, msg.
---@param expected any
---@param actual any
---@param msg string?
function M.eq(expected, actual, msg)
  if expected ~= actual then
    local prefix = msg and (msg .. ': ') or ''
    error(string.format('%sexpected %s, got %s', prefix, inspect(expected), inspect(actual)), 2)
  end
end

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

---Pretty-print a token list. Useful for debugging.
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
