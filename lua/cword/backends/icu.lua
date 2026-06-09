-- ICU-compatible CJK run grouping without the dictionary.
--
-- Mirrors UAX #29 word break rules: consecutive CJK code points merge
-- into one word (`$KanaKanji $KanaKanji`), consecutive ASCII letters
-- merge (`$ALetterPlus $ALetterPlus`), and the two rules never cross
-- a script boundary because `$ALetterPlus` excludes CJK.
--
-- Skips ICU's dictionary engine (cjdict.txt + Viterbi DP), so the
-- output is predictable instead of "[你好, 世界] because both happen
-- to be in the corpus".

local utf8 = require('cword.util.utf8')
local cjk = require('cword.backends.cjk')

local M = {}

---@param tok table
---@return string "cjk" | "ascii" | "other"
local function script(tok)
  local b = string.byte(tok.text, 1)
  if not b then
    return 'other'
  end
  if b < 0x80 then
    if
      (b >= 0x41 and b <= 0x5A)
      or (b >= 0x61 and b <= 0x7A)
      or (b >= 0x30 and b <= 0x39)
      or b == 0x5F
    then
      return 'ascii'
    end
    return 'other'
  end
  local cp = utf8.codepoint(tok.text, 1)
  if
    (cp >= 0x4E00 and cp <= 0x9FFF)
    or (cp >= 0x3400 and cp <= 0x4DBF)
    or (cp >= 0x3040 and cp <= 0x309F)
    or (cp >= 0x30A0 and cp <= 0x30FF)
    or (cp >= 0xAC00 and cp <= 0xD7A3)
  then
    return 'cjk'
  end
  return 'other'
end

function M.cut(str)
  local tokens = cjk.cut(str)
  if #tokens <= 1 then
    return tokens
  end

  local merged = {}
  for _, tok in ipairs(tokens) do
    if not tok.is_word_like then
      merged[#merged + 1] = tok
    else
      local last = merged[#merged]
      if last and last.is_word_like and script(last) == script(tok) then
        last.text = last.text .. tok.text
        last.byte_end = tok.byte_end
      else
        merged[#merged + 1] = tok
      end
    end
  end
  return merged
end

return M
