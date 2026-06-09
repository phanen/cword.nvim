-- cjk backend: each CJK character is its own word.
-- ASCII letters/digits/underscore form one word (vim's default `iskeyword`).
-- CJK punctuation and fullwidth forms are each their own non-word token.
-- ASCII punctuation is its own non-word token.
-- Whitespace runs are one non-word token.
--
-- This is the default behavior expected by Chinese editor users: each CJK
-- character is a "word" for `w`/`b` motion. Compare to `icu` backend which
-- groups consecutive CJK characters into one run.
--
-- Char classification (Unicode ranges):
--   space    : U+0009..U+000D, U+0020
--   cjk      : CJK Unified Ideographs (4E00-9FFF, 3400-4DBF),
--              Hiragana (3040-309F), Katakana (30A0-30FF),
--              Hangul Syllables (AC00-D7A3)
--   punct    : CJK Symbols and Punctuation (3000-303F),
--              Halfwidth and Fullwidth Forms (FF00-FFEF),
--              everything else (ASCII punctuation, symbols)
--   ascii    : ASCII letters (41-5A, 61-7A), digits (30-39), underscore (5F)

local utf8 = require('cword.util.utf8')

local M = {}

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
    -- CJK Symbols and Punctuation (includes fullwidth space U+3000)
    return 'punct'
  end
  if
    (cp >= 0x41 and cp <= 0x5A)
    or (cp >= 0x61 and cp <= 0x7A)
    or (cp >= 0x30 and cp <= 0x39)
    or cp == 0x5F
  then
    return 'ascii'
  end
  return 'punct'
end

local function is_word(k)
  return k == 'cjk' or k == 'ascii'
end

---@param str string
---@return table[] tokens -- {{text, byte_start, byte_end, is_word_like}, ...}
function M.cut(str)
  local tokens = {}
  local i = 1
  local len = #str
  while i <= len do
    local k = kind(utf8.codepoint(str, i))
    local clen = utf8.char_len(string.byte(str, i))
    local start = i

    if k == 'space' or k == 'ascii' then
      -- group consecutive runs of the same kind
      i = i + clen
      while i <= len do
        local k2 = kind(utf8.codepoint(str, i))
        if k2 ~= k then
          break
        end
        i = i + utf8.char_len(string.byte(str, i))
      end
      tokens[#tokens + 1] = {
        text = string.sub(str, start, i - 1),
        byte_start = start,
        byte_end = i - 1,
        is_word_like = is_word(k),
      }
    else
      -- cjk or punct: exactly one code point per token
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
