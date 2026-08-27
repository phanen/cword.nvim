-- Word segmentation via ICU (libicuuc) + LuaJIT FFI. Output matches
-- V8's `Intl.Segmenter`, e.g. "你好世界" -> [你好, 世界],
-- "南京市长江大桥" -> [南京市, 长江, 大, 桥].
--
-- Token shape: { text, byte_start, byte_end, is_word_like }.
-- byte_start/byte_end are 1-indexed and inclusive so that
-- string.sub(s, byte_start, byte_end) recovers the text exactly.

local M = {}

local ffi = require('ffi')

local function detect_icu_version()
  local ok, icu = pcall(ffi.load, 'icuuc')
  if not ok then
    return nil, icu
  end

  -- Probe via the loaded userdata (not ffi.C, which is the default
  -- C namespace, not dlopen'd libraries). Scan high-to-low so the
  -- newest installed version wins.
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

local function utf16_to_byte(str, target_u16)
  return vim.str_byteindex(str, 'utf-16', target_u16, false)
end

local iskeyword = require('cword.util.iskeyword')

-- Codepoint ranges always considered word-like, regardless of iskeyword.
local CJK_RANGES = {
  { 0x3400, 0x4DBF }, -- CJK Extension A
  { 0x4E00, 0x9FFF }, -- CJK ideographs
  { 0x3040, 0x309F }, -- Hiragana
  { 0x30A0, 0x30FF }, -- Katakana
  { 0xAC00, 0xD7A3 }, -- Hangul syllables
}

local function is_cjk(cp)
  for _, r in ipairs(CJK_RANGES) do
    if cp >= r[1] and cp <= r[2] then
      return true
    end
  end
  return false
end

---@param s string
---@param byte_idx integer 1-indexed byte column
---@return boolean
local function is_word_like_at(s, byte_idx)
  local b1 = string.byte(s, byte_idx)
  if not b1 then
    return false
  end

  -- CJK symbols & punctuation (U+3000..U+303F) and fullwidth forms
  -- (U+FF00..U+FFEF) are never word-like.
  if b1 == 0xE3 and string.byte(s, byte_idx + 1) == 0x80 then
    return false
  end
  if b1 == 0xEF then
    local b2 = string.byte(s, byte_idx + 1) or 0
    if (b2 >= 0xBC and b2 <= 0xBF) or b2 == 0xBD then
      return false
    end
  end

  if b1 < 0x80 then
    return iskeyword.is_keyword(b1)
  end

  -- Multi-byte: decode the codepoint in place. nvim's vim.fn.strcharpart
  -- is char-indexed and vim.str_utfindex is O(n) per call, so for this
  -- per-byte helper the in-line decoder is faster.
  local cp
  if b1 < 0xE0 then
    cp = ((b1 - 0xC0) * 0x40) + (string.byte(s, byte_idx + 1) - 0x80)
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
  return is_cjk(cp) or iskeyword.is_keyword(cp)
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

-- ICU's UAX#29 splits ASCII lines on chars like '-' even when the
-- user has included them in 'iskeyword', and the per-ICU-token
-- post-processing above can only refine within a token — it can't
-- merge across them. Pure-ASCII spans therefore need a second
-- pass driven by is_word_like_at. Spans touching any multi-byte
-- byte are left to ICU: its cjdict / Viterbi is authoritative
-- (e.g. "你好世界" -> "你好|世界"), and is_word_like_at would
-- collapse all CJK into one run anyway.
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
          -- Non-word run: split on a word-like char OR on a ws/non-ws
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
