-- Default backend. Each CJK code point is its own word;
-- word-ness for everything else is determined by vim.o.iskeyword.
-- Whitespace and punctuation are their own non-word tokens.
--
-- Ranges used by `kind`:
--   space  : 0x09..0x0D, 0x20
--   cjk    : CJK Unified (4E00-9FFF, 3400-4DBF),
--            Hiragana (3040-309F), Katakana (30A0-30FF),
--            Hangul Syllables (AC00-D7A3)
--   punct  : CJK Symbols (3000-303F), Halfwidth/Fullwidth (FF00-FFEF),
--            everything not matched by iskeyword
--   ascii  : iskeyword hit (typically @,48-57,_,192-255)

local iskeyword = require('cword.util.iskeyword')

local M = {}

local function codepoint(str, idx)
  local b1 = string.byte(str, idx)
  if not b1 then
    return -1
  end
  if b1 < 0x80 then
    return b1
  end
  if b1 < 0xE0 then
    local b2 = string.byte(str, idx + 1) or 0
    return ((b1 - 0xC0) * 0x40) + (b2 - 0x80)
  end
  if b1 < 0xF0 then
    local b2 = string.byte(str, idx + 1) or 0
    local b3 = string.byte(str, idx + 2) or 0
    return ((b1 - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80)
  end
  local b2 = string.byte(str, idx + 1) or 0
  local b3 = string.byte(str, idx + 2) or 0
  local b4 = string.byte(str, idx + 3) or 0
  return ((b1 - 0xF0) * 0x40000) + ((b2 - 0x80) * 0x1000) + ((b3 - 0x80) * 0x40) + (b4 - 0x80)
end

local function kind(cp)
  if cp == 0x09 or cp == 0x0A or cp == 0x0B or cp == 0x0C or cp == 0x0D or cp == 0x20 then
    return 'space'
  end
  if
    (cp >= 0x4E00 and cp <= 0x9FFF)
    or (cp >= 0x3400 and cp <= 0x4DBF)
    or (cp >= 0x3040 and cp <= 0x309F)
    or (cp >= 0x30A0 and cp <= 0x30FF)
    or (cp >= 0xAC00 and cp <= 0xD7A3)
  then
    return 'cjk'
  end
  if cp >= 0x3000 and cp <= 0x303F then
    return 'punct'
  end
  if cp >= 0xFF00 and cp <= 0xFFEF then
    return 'punct'
  end
  if iskeyword.is_keyword(cp) then
    return 'ascii'
  end
  return 'punct'
end

local function is_word(k)
  return k == 'cjk' or k == 'ascii'
end

---@param str string
---@return table[]
function M.cut(str)
  local tokens = {}
  local i = 1
  local len = #str
  while i <= len do
    local k = kind(codepoint(str, i))
    local b1 = string.byte(str, i)
    local clen
    if b1 < 0x80 then
      clen = 1
    elseif b1 < 0xE0 then
      clen = 2
    elseif b1 < 0xF0 then
      clen = 3
    else
      clen = 4
    end
    local start = i

    if k == 'space' or k == 'ascii' or k == 'punct' then
      i = i + clen
      while i <= len do
        if kind(codepoint(str, i)) ~= k then
          break
        end
        local b = string.byte(str, i)
        if b < 0x80 then
          i = i + 1
        elseif b < 0xE0 then
          i = i + 2
        elseif b < 0xF0 then
          i = i + 3
        else
          i = i + 4
        end
      end
      tokens[#tokens + 1] = {
        text = string.sub(str, start, i - 1),
        byte_start = start,
        byte_end = i - 1,
        is_word_like = is_word(k),
      }
    else
      local end_byte = i + clen - 1
      tokens[#tokens + 1] = {
        text = string.sub(str, start, end_byte),
        byte_start = start,
        byte_end = end_byte,
        is_word_like = is_word(k),
      }
      i = end_byte + 1
    end
  end
  return tokens
end

return M
