-- Word segmentation via ICU (libicuuc) + LuaJIT FFI.
--
-- Calls the real ICU library — the same code path V8 uses for
-- `Intl.Segmenter` — so the output matches JavaScript's
-- Intl.Segmenter byte-for-byte:
--
--   "你好世界"      -> [你好, 世界]          (cjdict.txt merge)
--   "南京市长江大桥" -> [南京市, 长江, 大, 桥] (Viterbi DP result)
--
-- The icu major version is detected at load time by probing for
-- versioned symbol names (`ubrk_close_80` down to `ubrk_close_50`)
-- via the FFI loader. The binding follows whatever major version
-- libicuuc.so happens to expose.
--
-- UTF-16 -> UTF-8 byte conversion prefers vim.str_byteindex when it
-- is available in the running Lua context, and falls back to a
-- pure-Lua walker otherwise. The fallback matters under nvim-test's
-- runner harness, where `vim.str_byteindex` is nil but the target
-- nvim has it (and vice versa for plain Lua + busted runs).
--
-- Token shape:
--   { text, byte_start, byte_end, is_word_like }
--
-- byte_start/byte_end are 1-indexed and inclusive so that
-- string.sub(s, byte_start, byte_end) recovers the text exactly.

local M = {}

local ffi = require('ffi')

-- ---------------------------------------------------------------------------
-- Version probe
-- ---------------------------------------------------------------------------

local function detect_icu_version()
  local ok, icu = pcall(ffi.load, 'icuuc')
  if not ok then
    return nil, icu
  end

  -- Scan high-to-low so the newest installed version wins. We probe
  -- ubrk_close_<N> via the loaded library userdata, not ffi.C (the
  -- latter is for the default C namespace, not dlopen'd libraries).
  for v = 80, 50, -1 do
    local sym = 'ubrk_close_' .. v
    pcall(function()
      ffi.cdef('void ' .. sym .. '(void*);')
    end)
    local ok_bind, fn = pcall(function()
      return icu[sym]
    end)
    if ok_bind and type(fn) == 'cdata' then
      return v, icu
    end
  end
  return nil, 'libicuuc found but no ubrk_close_<N> symbol in 50..80'
end

local ICU_VER, icu_or_err = detect_icu_version()
if not ICU_VER then
  error('cword: ' .. tostring(icu_or_err))
end

local icu = icu_or_err

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

M._icu_version = ICU_VER

-- ---------------------------------------------------------------------------
-- UTF-16 -> UTF-8 byte conversion
-- ---------------------------------------------------------------------------

-- vim.str_byteindex is available in Neovim >= 0.10 but not in plain
-- Lua / busted / nvim-test's runner harness. Fall back to a pure-Lua
-- walker when it's missing.
local HAS_STR_BYTEINDEX = type(vim) == 'table' and type(vim.str_byteindex) == 'function'

local function utf16_to_byte_native(str, target_u16)
  return vim.str_byteindex(str, 'utf-16', target_u16, false)
end

local function utf16_to_byte_fallback(str, target_u16)
  -- Walk the string, counting UTF-16 code units (ASCII = 1, BMP = 1,
  -- surrogate pair = 2). Stop when we reach the target code unit.
  -- Returns 0-indexed byte offset (matches vim.str_byteindex strict=false).
  local i = 1
  local u = 0
  local len = #str
  while i <= len and u < target_u16 do
    local b1 = string.byte(str, i)
    if b1 < 0x80 then
      i = i + 1
    elseif b1 < 0xE0 then
      i = i + 2
    elseif b1 < 0xF0 then
      i = i + 3
    else
      i = i + 4
    end
    if b1 >= 0xF0 then
      u = u + 2
    else
      u = u + 1
    end
  end
  if u == target_u16 then
    return i - 1
  end
  -- target_u16 is past end
  return len
end

local utf16_to_byte = HAS_STR_BYTEINDEX and utf16_to_byte_native or utf16_to_byte_fallback

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local iskeyword = require('cword.util.iskeyword')

local function is_word_like_at(s, byte_idx)
  local b1 = string.byte(s, byte_idx)
  if not b1 then
    return false
  end

  -- CJK symbols & punctuation: never word-like (U+3000..U+303F).
  if b1 == 0xE3 then
    local b2 = string.byte(s, byte_idx + 1) or 0
    if b2 == 0x80 then
      local b3 = string.byte(s, byte_idx + 2) or 0
      if b3 >= 0x80 and b3 <= 0xBF then
        return false
      end
    end
  end

  -- Fullwidth forms: never word-like (U+FF00..U+FFEF).
  if b1 == 0xEF then
    local b2 = string.byte(s, byte_idx + 1) or 0
    if (b2 >= 0xBC and b2 <= 0xBF) or b2 == 0xBD then
      return false
    end
  end

  -- Decode codepoint for the CJK and iskeyword checks.
  local cp
  if b1 < 0x80 then
    cp = b1
  elseif b1 < 0xE0 then
    local b2 = string.byte(s, byte_idx + 1) or 0
    cp = ((b1 - 0xC0) * 0x40) + (b2 - 0x80)
  elseif b1 < 0xF0 then
    local b2 = string.byte(s, byte_idx + 1) or 0
    local b3 = string.byte(s, byte_idx + 2) or 0
    cp = ((b1 - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80)
  else
    local b2 = string.byte(s, byte_idx + 1) or 0
    local b3 = string.byte(s, byte_idx + 2) or 0
    local b4 = string.byte(s, byte_idx + 3) or 0
    cp = ((b1 - 0xF0) * 0x40000) + ((b2 - 0x80) * 0x1000) + ((b3 - 0x80) * 0x40) + (b4 - 0x80)
  end

  -- CJK ideographs, hiragana/katakana, hangul: always word-like.
  if
    (cp >= 0x4E00 and cp <= 0x9FFF)
    or (cp >= 0x3400 and cp <= 0x4DBF)
    or (cp >= 0x3040 and cp <= 0x309F)
    or (cp >= 0x30A0 and cp <= 0x30FF)
    or (cp >= 0xAC00 and cp <= 0xD7A3)
  then
    return true
  end

  return iskeyword.is_keyword(cp)
end

local function to_utf16(s)
  local open_fn = icu['ucnv_open_' .. ICU_VER]
  local to_fn = icu['ucnv_toUChars_' .. ICU_VER]
  local close_fn = icu['ucnv_close_' .. ICU_VER]
  if not (open_fn and to_fn and close_fn) then
    error('cword: icu version ' .. ICU_VER .. ' converter symbols not bound')
  end
  local status = ffi.new('int32_t[1]', 0)
  local cnv = open_fn('utf-8', status)
  local buf = ffi.new('uint16_t[?]', #s * 2 + 2)
  local n = to_fn(cnv, buf, #s * 2 + 2, s, #s, status)
  close_fn(cnv)
  return buf, n
end

-- ICU's UAX#29 word segmentation splits ASCII lines on chars like '-'
-- even when the user has included them in 'iskeyword'. The
-- per-ICU-token post-processing above can only refine within an ICU
-- token, not merge across them, so spans covering nothing but ASCII
-- need a second pass driven by is_word_like_at. Spans that touch any
-- multi-byte byte (CJK, kana, hangul, Latin extended, etc.) are left
-- alone — ICU's cjdict / Viterbi is authoritative for them (e.g.
-- "你好世界" -> "你好|世界"), and is_word_like_at would collapse all
-- CJK into a single run anyway.
---@param line string
---@param tokens table[]
---@return table[]
local function resegment_ascii(line, tokens)
  local len = #line
  if len == 0 then
    return tokens
  end

  local spans = {}
  do
    local pos = 1
    while pos <= len do
      if string.byte(line, pos) >= 0x80 then
        pos = pos + 1
      else
        local start = pos
        while pos <= len and string.byte(line, pos) < 0x80 do
          pos = pos + 1
        end
        spans[#spans + 1] = { start, pos - 1 }
      end
    end
  end
  if #spans == 0 then
    return tokens
  end

  local out = {}
  local n = #tokens
  local i = 1
  local span_idx = 1
  while i <= n do
    local t = tokens[i]
    while span_idx <= #spans and spans[span_idx][2] < t.byte_start do
      span_idx = span_idx + 1
    end
    local span = span_idx <= #spans and spans[span_idx] or nil
    local in_span = span ~= nil and t.byte_start >= span[1] and t.byte_end <= span[2]
    if in_span then
      local pos = span[1]
      while pos <= span[2] do
        local wl = is_word_like_at(line, pos)
        local run_start = pos
        if wl then
          while pos <= span[2] and is_word_like_at(line, pos) do
            pos = pos + 1
          end
        else
          -- Non-word run: walk until a word-like char or a ws/non-ws
          -- boundary inside the run. This mirrors the merge pass's
          -- "don't merge across whitespace" rule: `->` stays one
          -- token, but the spaces between two `->` runs are not
          -- absorbed into either side.
          local first_is_ws = line:sub(pos, pos):match('%s') ~= nil
          while pos <= span[2] do
            if is_word_like_at(line, pos) then
              break
            end
            local cur_is_ws = line:sub(pos, pos):match('%s') ~= nil
            if cur_is_ws ~= first_is_ws then
              break
            end
            pos = pos + 1
          end
        end
        out[#out + 1] = {
          text = line:sub(run_start, pos - 1),
          byte_start = run_start,
          byte_end = pos - 1,
          is_word_like = wl,
        }
      end
      while i <= n and tokens[i].byte_end <= span[2] do
        i = i + 1
      end
    else
      out[#out + 1] = t
      i = i + 1
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param str string
---@return table[]
function M.cut(str)
  if #str == 0 then
    return {}
  end

  local utf16, n = to_utf16(str)
  local status = ffi.new('int32_t[1]', 0)
  local open_fn = icu['ubrk_open_' .. ICU_VER]
  local first_fn = icu['ubrk_first_' .. ICU_VER]
  local next_fn = icu['ubrk_next_' .. ICU_VER]
  local close_fn = icu['ubrk_close_' .. ICU_VER]
  local bi = open_fn(1, 'en_US', utf16, n, status) -- 1 = UBRK_WORD
  if bi == nil then
    return {}
  end

  local positions = { first_fn(bi) }
  while true do
    local p = next_fn(bi)
    if p == -1 then
      break
    end
    table.insert(positions, p)
  end
  close_fn(bi)

  local tokens = {}
  for i = 1, #positions - 1 do
    local u_start = positions[i]
    local u_end = positions[i + 1]
    local byte_start = utf16_to_byte(str, u_start) + 1
    local byte_end = utf16_to_byte(str, u_end)
    if byte_end >= byte_start then
      tokens[#tokens + 1] = {
        text = str:sub(byte_start, byte_end),
        byte_start = byte_start,
        byte_end = byte_end,
        is_word_like = is_word_like_at(str, byte_start),
      }
    end
  end

  return resegment_ascii(str, tokens)
end

return M
