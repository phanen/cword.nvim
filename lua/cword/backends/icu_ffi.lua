-- ICU-backed word segmentation via LuaJIT FFI on libicuuc.
--
-- This backend calls the real ICU library (the same code path V8 uses
-- for `Intl.Segmenter`) and therefore matches the output of
-- JavaScript's Intl.Segmenter byte-for-byte:
--
--   "你好世界"      -> [你好, 世界]          (cjdict.txt merge)
--   "南京市长江大桥" -> [南京市, 长江, 大, 桥] (Viterbi DP result)
--
-- Requires libicuuc at runtime. The shared object symbol names carry
-- the ICU major-version suffix; this file is hard-wired to `_78`
-- (Arch's current icu package). Update the suffix if the host system
-- upgrades ICU.
--
-- The FFI plumbing: ICU's BreakIterator takes UTF-16, so we
--   (a) convert input UTF-8 -> UTF-16 via ucnv_toUChars,
--   (b) ask ICU for word boundaries (positions in UTF-16 code units),
--   (c) convert each position back to a UTF-8 byte index with a
--       pure-Lua walker. We avoid vim.str_byteindex because the
--       function is unavailable in the nvim-test runner's harness,
--       and routing each call through helpers.exec_lua per token
--       would be needlessly slow.

local M = {}

local ffi = require('ffi')

local ICU_VER = '78'

ffi.cdef([[
typedef struct UBreakIterator UBreakIterator;
typedef struct UConverter UConverter;
typedef int32_t UErrorCode;

UConverter* ucnv_open_]] .. ICU_VER .. [[(const char* name, void* err);
void ucnv_close_]] .. ICU_VER .. [[(UConverter* cnv);
int32_t ucnv_toUChars_]] .. ICU_VER .. [[(UConverter* cnv, uint16_t* dest, int32_t destLen,
                         const char* src, int32_t srcLen, void* err);

UBreakIterator* ubrk_open_]] .. ICU_VER .. [[(int32_t type, const char* locale,
                         const uint16_t* text, int32_t textLength, void* err);
void ubrk_close_]] .. ICU_VER .. [[(UBreakIterator* bi);
int32_t ubrk_first_]] .. ICU_VER .. [[(UBreakIterator* bi);
int32_t ubrk_next_]] .. ICU_VER .. [[(UBreakIterator* bi);
]])

local icu = ffi.load('icuuc')

-- Convert UTF-8 -> UTF-16. Returns the buffer plus its length in
-- code units (not bytes).
local function to_utf16(s)
  local status = ffi.new('int32_t[1]', 0)
  local cnv = icu.ucnv_open_78('utf-8', status)
  -- Worst case: every input byte becomes a surrogate pair (2 units).
  local buf = ffi.new('uint16_t[?]', #s * 2 + 2)
  local n = icu.ucnv_toUChars_78(cnv, buf, #s * 2 + 2, s, #s, status)
  icu.ucnv_close_78(cnv)
  return buf, n
end

-- Convert a 0-indexed UTF-16 code unit position to a 0-indexed UTF-8
-- byte offset. BMP codepoints consume 1 UTF-16 unit, supplementary
-- plane codepoints consume 2. Returns `#str` when target_u16 is at or
-- past the end.
local function utf16_to_byte(str, target_u16)
  local i = 1
  local u = 0
  local len = #str
  while i <= len and u < target_u16 do
    local b1 = string.byte(str, i)
    if b1 < 0x80 then
      u = u + 1
      i = i + 1
    elseif b1 < 0xE0 then
      u = u + 1
      i = i + 2
    elseif b1 < 0xF0 then
      u = u + 1
      i = i + 3
    else
      -- 4-byte UTF-8: codepoint >= U+10000, takes 2 UTF-16 units
      u = u + 2
      i = i + 4
    end
  end
  return i - 1
end

-- Decode the first UTF-8 codepoint of `s` starting at byte index
-- `byte_idx` (1-indexed). Returns -1 when out of range.
local function first_codepoint(s, byte_idx)
  if byte_idx > #s then
    return -1
  end
  local b1 = string.byte(s, byte_idx)
  if not b1 then
    return -1
  end
  if b1 < 0x80 then
    return b1
  end
  if b1 < 0xE0 then
    local b2 = string.byte(s, byte_idx + 1) or 0
    return ((b1 - 0xC0) * 0x40) + (b2 - 0x80)
  end
  if b1 < 0xF0 then
    local b2 = string.byte(s, byte_idx + 1) or 0
    local b3 = string.byte(s, byte_idx + 2) or 0
    return ((b1 - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80)
  end
  local b2 = string.byte(s, byte_idx + 1) or 0
  local b3 = string.byte(s, byte_idx + 2) or 0
  local b4 = string.byte(s, byte_idx + 3) or 0
  return ((b1 - 0xF0) * 0x40000) + ((b2 - 0x80) * 0x1000) + ((b3 - 0x80) * 0x40) + (b4 - 0x80)
end

-- Mirrors JS Intl.SegmentData.isWordLike: a token is word-like when
-- its first code point is ASCII letter/digit/underscore or a
-- non-ASCII non-punctuation code point.
local function is_word_like_char(cp)
  if cp < 0 then
    return false
  end
  if cp < 0x80 then
    return (cp >= 0x41 and cp <= 0x5A) -- A-Z
      or (cp >= 0x61 and cp <= 0x7A) -- a-z
      or (cp >= 0x30 and cp <= 0x39) -- 0-9
      or cp == 0x5F -- _
  end
  if cp >= 0x3000 and cp <= 0x303F then
    return false
  end -- CJK Symbols
  if cp >= 0xFF00 and cp <= 0xFFEF then
    return false
  end -- fullwidth
  return true
end

---@param str string
---@return table[]
function M.cut(str)
  if #str == 0 then
    return {}
  end

  local utf16, n = to_utf16(str)
  local status = ffi.new('int32_t[1]', 0)
  local bi = icu.ubrk_open_78(1, 'en_US', utf16, n, status) -- 1 = UBRK_WORD
  if bi == nil then
    return {}
  end

  -- ICU returns break positions in UTF-16 code units.
  local positions = { icu.ubrk_first_78(bi) }
  while true do
    local p = icu.ubrk_next_78(bi)
    if p == -1 then
      break
    end
    table.insert(positions, p)
  end
  icu.ubrk_close_78(bi)

  local tokens = {}
  for i = 1, #positions - 1 do
    local u_start = positions[i]
    local u_end = positions[i + 1]
    local byte_start = utf16_to_byte(str, u_start) + 1 -- 1-indexed
    local byte_end = utf16_to_byte(str, u_end) -- 0-indexed; convert below
    -- `utf16_to_byte` returns the 0-indexed byte offset of the FIRST
    -- byte whose preceding UTF-16 index is u_end. For a boundary
    -- between two code points, that equals the start of the NEXT
    -- code point, which is the byte AFTER the last byte of this
    -- token's text. So byte_end in 1-indexed inclusive form is the
    -- same value.
    if byte_end >= byte_start then
      local cp = first_codepoint(str, byte_start)
      tokens[#tokens + 1] = {
        text = string.sub(str, byte_start, byte_end),
        byte_start = byte_start,
        byte_end = byte_end,
        is_word_like = is_word_like_char(cp),
      }
    end
  end
  return tokens
end

return M
