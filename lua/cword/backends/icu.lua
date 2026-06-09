-- icu backend: ICU-compatible CJK run grouping, without the dictionary.
--
-- ICU's word segmenter (V8/Node uses `icu::BreakIterator::createWordInstance`)
-- merges consecutive CJK code points into one word using the UAX #29 rule
-- `$KanaKanji $KanaKanji {400}` and then passes the chain to its CJK
-- dictionary engine (cjdict.txt, ~316k entries) which picks a minimum-cost
-- segmentation via Viterbi DP. The dictionary lookups make ICU's output
-- non-deterministic for editor use: e.g. `你好世界` becomes `[你好, 世界]`
-- just because both entries happen to be in the dictionary.
--
-- This backend implements the *run grouping* part but skips the dictionary
-- AND skips merging across scripts. Two rules from UAX #29 drive this:
--   - `$KanaKanji $KanaKanji`: consecutive CJK stay together
--   - `$ALetterPlus $ALetterPlus`: consecutive ASCII letters stay together
--   - `$ALetterPlus` excludes CJK code points (see word.txt rule definitions),
--     so the ASCII rule never fires across a CJK/ASCII boundary
-- Therefore: a CJK run and an ASCII run never merge. Punctuation and
-- whitespace always break.
--
-- Examples:
--   "你好世界"   -> [你好世界]     (one CJK run)
--   "你好，世界" -> [你好, ，, 世界]
--   "你好hello"  -> [你好, hello]  (script change breaks merge)
--   "hello world"-> [hello, ' ', world]

local utf8 = require('cword.util.utf8')
local cjk = require('cword.backends.cjk')

local M = {}

---Determine the "script" of a token by inspecting its first codepoint.
---Returns "cjk", "ascii", or "other". Used to decide whether two adjacent
---word-like tokens should be merged.
---@param tok table token from cjk backend
---@return string
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
