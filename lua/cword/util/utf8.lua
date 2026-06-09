-- UTF-8 byte-level helpers. No external dependency.
-- Codepoint is decoded from bytes (big-endian, network order).
-- We do NOT handle grapheme clusters (ZWJ emoji sequences are treated as
-- multiple code points); that is a separate concern and is intentionally
-- out of scope for word motion segmentation.

local M = {}

---Length in bytes of the UTF-8 character starting at byte `b`.
---@param b integer
---@return integer
function M.char_len(b)
  if b < 0x80 then
    return 1
  elseif b < 0xC0 then
    return 1 -- stray continuation byte; treat as 1
  elseif b < 0xE0 then
    return 2
  elseif b < 0xF0 then
    return 3
  else
    return 4
  end
end

---Decode the Unicode codepoint of the UTF-8 char starting at byte index `i`
---(1-indexed) in `str`.
---@param str string
---@param i integer
---@return integer
function M.codepoint(str, i)
  local b1 = string.byte(str, i)
  if not b1 then
    return -1
  end
  if b1 < 0x80 then
    return b1
  end
  if b1 < 0xE0 then
    local b2 = string.byte(str, i + 1) or 0
    return ((b1 - 0xC0) * 0x40) + (b2 - 0x80)
  elseif b1 < 0xF0 then
    local b2 = string.byte(str, i + 1) or 0
    local b3 = string.byte(str, i + 2) or 0
    return ((b1 - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80)
  else
    local b2 = string.byte(str, i + 1) or 0
    local b3 = string.byte(str, i + 2) or 0
    local b4 = string.byte(str, i + 3) or 0
    return ((b1 - 0xF0) * 0x40000) + ((b2 - 0x80) * 0x1000) + ((b3 - 0x80) * 0x40) + (b4 - 0x80)
  end
end

---Advance `i` by one UTF-8 character.
---@param str string
---@param i integer
---@return integer
function M.next(str, i)
  return i + M.char_len(string.byte(str, i))
end

return M
