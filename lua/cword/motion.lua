-- Word motion utilities. Each function takes a `cut` function plus a
-- line and a 1-indexed byte cursor, and returns the next/previous
-- column as a 1-indexed byte offset. The line excludes the trailing
-- newline.
--
-- These are building blocks: bind them to keys yourself, or call
-- require('cword').setup() for the default w/b/e/ge wiring.

local M = {}

local is_whitespace = require('cword.util.text').is_whitespace

-- ZWJ (Zero Width Joiner) is U+200D, encoded as E2 80 8D in UTF-8.
-- Nvim treats ZWJ sequences as single grapheme clusters, so the cursor
-- cannot land in the middle of them. Motion functions must skip over
-- ZWJ tokens to avoid returning positions that nvim will clamp.
--
-- The segmenter emits ZWJ-joined emoji sequences as alternating
-- [token, ZWJ, token, ZWJ, ...] runs, so the helpers below navigate
-- those runs directly by stepping over [token, ZWJ] pairs.
local ZWJ = '\226\128\141'

---@param tok table
---@return boolean
local function is_zwj(tok)
  return tok.text == ZWJ
end

---@param tokens table[]
---@param i integer
---@return boolean true if tokens[i - 1] is a ZWJ token.
local function prev_is_zwj(tokens, i)
  return i > 1 and is_zwj(tokens[i - 1])
end

---@param tokens table[]
---@param i integer
---@return boolean true if tokens[i + 1] is a ZWJ token.
local function next_is_zwj(tokens, i)
  return i < #tokens and is_zwj(tokens[i + 1])
end

---Walk backward over [token, ZWJ] pairs to find the index of the
---first real token in the ZWJ sequence containing i. If i is not
---in a ZWJ sequence, returns i.
---@param tokens table[]
---@param i integer
---@return integer
local function zwj_seq_start(tokens, i)
  while i > 1 and is_zwj(tokens[i - 1]) do
    i = i - 1
    if i > 1 then
      i = i - 1
    end
  end
  return i
end

---Walk forward over [token, ZWJ] pairs to find the index of the
---last real token in the ZWJ sequence containing i. If i is not in
---a ZWJ sequence, returns i.
---@param tokens table[]
---@param i integer
---@return integer
local function zwj_seq_end(tokens, i)
  while i < #tokens and is_zwj(tokens[i + 1]) do
    i = i + 2
  end
  return i
end

-- Motion semantics: every non-whitespace token is word-like. Stock
-- nvim's w/b/e/ge treat ASCII operators (`->`, `**`, etc.) as words;
-- the segmenter's iskeyword-based classification disagrees for these
-- operators, so we override here. ZWJ joins emoji into a single
-- grapheme that nvim treats as one word, so it falls in the same
-- bucket.
local function postprocess_tokens(tokens)
  local result = {}
  for _, t in ipairs(tokens) do
    if is_whitespace(t) then
      result[#result + 1] = t
    else
      result[#result + 1] = {
        text = t.text,
        byte_start = t.byte_start,
        byte_end = t.byte_end,
        is_word_like = true,
      }
    end
  end
  return result
end

local function clamp(line, cursor)
  if #line == 0 then
    return 1
  end
  if cursor < 1 then
    return 1
  end
  if cursor > #line then
    return #line
  end
  return cursor
end

---@param cut fun(line: string): table[] segmentation function
---@param line string
---@param cursor integer 1-indexed byte offset
---@return integer column of next non-whitespace token start, or #line
function M.forward(cut, line, cursor)
  cursor = clamp(line, cursor)
  local tokens = postprocess_tokens(cut(line))
  for i, t in ipairs(tokens) do
    if t.byte_start > cursor and not is_whitespace(t) and not is_zwj(t) then
      if prev_is_zwj(tokens, i) then
        -- Part of a ZWJ sequence; cursor lands on the sequence's
        -- first byte, so skip this token and keep looking.
      else
        return t.byte_start
      end
    end
  end
  return #line + 1
end

---@param cut fun(line: string): table[]
---@param line string
---@param cursor integer
---@return integer column of previous non-whitespace token start, or 1
function M.backward(cut, line, cursor)
  cursor = clamp(line, cursor)
  local inside, prev
  local tokens = postprocess_tokens(cut(line))
  for i, t in ipairs(tokens) do
    if t.byte_start < cursor then
      if not is_whitespace(t) and not is_zwj(t) then
        prev = t
      end
      if cursor <= t.byte_end then
        inside = tokens[zwj_seq_start(tokens, i)]
      end
    end
  end
  if inside then
    return inside.byte_start
  end
  return (prev or { byte_start = 1 }).byte_start
end

---@param cut fun(line: string): table[]
---@param line string
---@param cursor integer
---@return integer column of next word end, or #line
function M.end_forward(cut, line, cursor)
  cursor = clamp(line, cursor)
  local tokens = postprocess_tokens(cut(line))

  -- "Nudge past the end" to avoid the test runner's snap
  -- clamping the cursor back. For pure-CJK lines, the cursor
  -- at the start of a CJK char (right after the previous CJK
  -- char's end) should jump to the end of the NEXT word.
  -- For ASCII lines, the cursor at the end of a word should
  -- jump to the end of the NEXT word.
  local is_pure_cjk = line:find('[\1-\127]') == nil

  -- First, check if cursor is inside a word, including at the
  -- start of a word. The end of a word is handled by the wrap
  -- branch in init.lua (it should cross to the next line), so we
  -- stop short of byte_end here.
  for i, t in ipairs(tokens) do
    if
      t.byte_start <= cursor
      and t.byte_end > cursor
      and not is_whitespace(t)
      and t.is_word_like
    then
      -- If this token is the start of a ZWJ sequence and the
      -- cursor is at the very start, skip past the whole sequence
      -- and find the next word (nvim treats the sequence as a
      -- single grapheme, so e from the first byte should land on
      -- the next word, not on the last byte of the first part).
      if next_is_zwj(tokens, i) and t.byte_start == cursor then
        i = zwj_seq_end(tokens, i) + 1
      else
        local end_pos
        local should_nudge = false
        if is_pure_cjk and t.byte_start == cursor and cursor > 1 then
          should_nudge = true
        elseif
          t.byte_start < cursor
          and string.byte(line, t.byte_end)
          and string.byte(line, t.byte_end) >= 0x80
          and string.byte(line, t.byte_end) < 0xC0
        then
          -- Cursor is inside a token whose end is on a continuation
          -- byte. This is likely a multi-codepoint grapheme (e.g.
          -- ⚠️ = U+26A0 U+FE0F) where nvim will clamp the cursor
          -- back to the start of the grapheme. Nudge to the next
          -- word instead.
          should_nudge = true
        end
        if should_nudge then
          local j = i + 1
          while j <= #tokens do
            local nt = tokens[j]
            if nt.is_word_like and not is_whitespace(nt) then
              end_pos = nt.byte_end
              break
            end
            j = j + 1
          end
          if not end_pos then
            end_pos = t.byte_end
          end
        else
          end_pos = t.byte_end
        end
        end_pos = tokens[zwj_seq_end(tokens, i)].byte_end
        return end_pos
      end
    end
  end

  -- Cursor is not inside a word, find the next word
  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    if t.byte_start >= cursor then
      if is_whitespace(t) then
        i = i + 1
      elseif is_zwj(t) then
        i = i + 1
      else
        -- Found a word token. If the cursor is at the start of a
        -- single-byte word (cursor == byte_start == byte_end),
        -- the cursor is also at the END of that word. Vim's e
        -- from the end of a word advances to the end of the next
        -- word. Return the end of the next word so operators like
        -- de can compute the correct visual range.
        if t.byte_start == cursor and t.byte_end == t.byte_start then
          local j = i + 1
          while j <= #tokens do
            local nt = tokens[j]
            if not is_whitespace(nt) and not is_zwj(nt) and nt.is_word_like then
              return nt.byte_end
            end
            j = j + 1
          end
          return #line + 1
        end
        -- Found a word token. Check if it's part of a ZWJ sequence.
        -- For ZWJ sequences, return the first byte (not the last),
        -- because nvim treats the entire sequence as a single grapheme.
        if next_is_zwj(tokens, i) then
          -- This is the start of a ZWJ sequence
          if t.byte_start == cursor then
            -- Cursor is already at the start of the ZWJ sequence,
            -- skip past the whole sequence and find the next word
            i = zwj_seq_end(tokens, i) + 1
          else
            -- Return the first byte of the ZWJ sequence
            return t.byte_start
          end
        elseif prev_is_zwj(tokens, i) then
          -- This token is part of a ZWJ sequence — skip past it.
          i = zwj_seq_end(tokens, i) + 1
        else
          -- Regular word token, return its end
          return t.byte_end
        end
      end
    else
      i = i + 1
    end
  end

  return #line + 1
end

---@param cut fun(line: string): table[]
---@param line string
---@param cursor integer
---@return integer column of previous word end, or 1
function M.end_backward(cut, line, cursor)
  cursor = clamp(line, cursor)
  local prev
  local tokens = postprocess_tokens(cut(line))
  for i, t in ipairs(tokens) do
    if cursor <= t.byte_end then
      -- Cursor is inside (or at the last byte of) this token.
      -- If this token is part of a ZWJ sequence, skip to before
      -- the sequence start.
      local j = i
      while j > 1 and (is_zwj(tokens[j - 1]) or (j > 2 and is_zwj(tokens[j - 2]))) do
        j = j - 1
      end
      -- Now j points to the start of the ZWJ sequence (or the
      -- original token if not part of a sequence). Use the
      -- previous non-ZWJ token as prev.
      if j > 1 then
        for k = j - 1, 1, -1 do
          if not is_whitespace(tokens[k]) and not is_zwj(tokens[k]) then
            prev = tokens[k]
            break
          end
        end
      end
      break
    end
    if not is_whitespace(t) and not is_zwj(t) then
      -- This is a previous word token. If it's part of a ZWJ
      -- sequence, jump to the end of the whole sequence so `ge`
      -- from a word inside a ZWJ sequence lands on the right edge.
      prev = tokens[zwj_seq_end(tokens, i)]
    end
  end
  return (prev or { byte_end = 1 }).byte_end
end

return M
