-- Spec helpers. Re-exports nvim-test.helpers and adds cword domain
-- helpers on top. Pattern after gitsigns.nvim/test/gs_helpers.lua.

local M = require('nvim-test.helpers')

-- After helpers.clear() spawns a fresh --embed session, that session
-- has its own package.path that does not include the project's lua/
-- tree. Push the current package.path into it so require inside
-- exec_lua can find cword modules.
function M.setup_path()
  M.exec_lua(function(path)
    package.path = path
  end, package.path)
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
