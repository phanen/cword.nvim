local M = {}

M.is_whitespace = function(tok)
  return tok.text:match('^%s+$') ~= nil
end

-- Helpers below detect UTF-8 grapheme-cluster boundaries by matching
-- the byte sequences of the relevant codepoints, so we don't have
-- to walk multi-byte chars manually.

-- U+200D: joins adjacent codepoints into one cluster.
M.ZWJ = '\226\128\141'

---@param text string
M.is_zwj_text = function(text)
  return text == M.ZWJ
end

-- U+FE0F: pins the cluster's left cursor edge so nvim's clamp
-- lands on byte_start rather than mid-cluster. Stock vim's `e`
-- on ⚠️ relies on this.
M.VS16 = '\239\184\143'

---@param text string
M.has_vs16 = function(text)
  return text:find(M.VS16) ~= nil
end

-- True when a token is one grapheme cluster built from >=2 codepoints.
-- strchars(text, 1) returns grapheme-cluster count (skipcc=1 drops
-- combining marks); strchars(text) returns codepoint count. The two
-- differ iff the token contains a multi-codepoint grapheme that
-- nvim will clamp to the cluster edges.
---@param text string
---@return boolean
M.is_multi_codepoint_grapheme = function(text)
  if #text == 0 then
    return false
  end
  return vim.fn.strchars(text, 1) == 1 and vim.fn.strchars(text) > 1
end

---@param toks table[]
---@param from_byte int 1-indexed byte (inclusive)
---@param to_byte int 1-indexed byte (exclusive)
---@return boolean
M.whitespace_between = function(toks, from_byte, to_byte)
  for _, t in ipairs(toks) do
    if t.byte_end > from_byte and t.byte_start < to_byte and M.is_whitespace(t) then
      return true
    end
  end
  return false
end

---@param toks table[]
---@param after_byte int 1-indexed byte
---@return integer?
M.next_non_whitespace_end = function(toks, after_byte)
  for _, t in ipairs(toks) do
    if t.byte_end > after_byte and not M.is_whitespace(t) then
      return t.byte_end
    end
  end
  return nil
end

local is_lead_byte = function(b)
  return b == nil or b < 0x80 or b >= 0xC0
end

---@param line string
---@param col integer 1-indexed byte column
---@return integer 1-indexed byte column of the lead byte of the
---char at `col`. Returns `col` unchanged when already on a boundary.
M.char_start = function(line, col)
  while col >= 1 and not is_lead_byte(line:byte(col)) do
    col = col - 1
  end
  return col
end

---@param line string
---@param col integer 1-indexed byte column
---@param max_col integer inclusive upper bound; pass #line to allow snap to EOL.
---@return integer 1-indexed byte column just past the char at `col`
---(i.e. the next char's lead byte, or max_col+1 at EOL). Returns
---`col` unchanged when already on a boundary.
M.char_end = function(line, col, max_col)
  while col <= max_col and not is_lead_byte(line:byte(col)) do
    col = col + 1
  end
  return col
end

return M
