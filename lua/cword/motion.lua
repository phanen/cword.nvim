-- Word motion utilities. Each takes a `cut` function plus a line
-- (without trailing newline) and a 1-indexed byte cursor, returning
-- the next/previous column as a 1-indexed byte offset. Bind them
-- yourself, or call require('cword').setup() for default w/b/e/ge.

local M = {}

local text = require('cword.util.text')
local is_whitespace = text.is_whitespace

---@param tok table
---@return boolean
local function is_zwj(tok)
  return text.is_zwj_text(tok.text)
end

---@param tokens table[]
---@param i integer
---@return boolean
local function prev_is_zwj(tokens, i)
  return i > 1 and is_zwj(tokens[i - 1])
end

---@param tokens table[]
---@param i integer
---@return boolean
local function next_is_zwj(tokens, i)
  return i < #tokens and is_zwj(tokens[i + 1])
end

---Walk backward over [token, ZWJ] pairs to find the first real
---token in the ZWJ sequence containing i (returns i if not in one).
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

---Walk forward over [token, ZWJ] pairs to find the last real token
---in the ZWJ sequence containing i (returns i if not in one).
---@param tokens table[]
---@param i integer
---@return integer
local function zwj_seq_end(tokens, i)
  while i < #tokens and is_zwj(tokens[i + 1]) do
    i = i + 2
  end
  return i
end

-- Stock nvim's w/b/e/ge treat ASCII operators (`->`, `**`) as
-- words; the segmenter's iskeyword-based classification doesn't.
-- Override to mark every non-whitespace token word-like. ZWJ-joined
-- emoji are already handled by skipping ZWJ tokens above.
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
        -- Cursor lands on the sequence's first byte; skip this
        -- tail token and keep looking for the next word.
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

  -- Nudge past byte_end so a test runner's snap-back-to-grapheme-start
  -- doesn't undo the motion. For pure-CJK, cursor at a char start
  -- (right after the previous char's end) jumps to the NEXT word.
  -- For ASCII, cursor at a word's end jumps to the NEXT word.
  local is_pure_cjk = line:find('[\1-\127]') == nil

  -- Cursor is inside a word (including at its start). Wrap cases
  -- (byte_end → next line) are handled in init.lua, so we stop
  -- short of byte_end here.
  for i, t in ipairs(tokens) do
    if
      t.byte_start <= cursor
      and t.byte_end > cursor
      and not is_whitespace(t)
      and t.is_word_like
    then
      -- ZWJ-sequence start + cursor at first byte: skip the whole
      -- sequence. nvim treats it as one grapheme, so 'e' from its
      -- first byte should land on the NEXT word, not the last byte
      -- of the first part.
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
          -- Cursor inside a token whose last byte is a continuation
          -- byte — likely a multi-codepoint grapheme (e.g. ⚠️ =
          -- U+26A0 U+FE0F) where nvim will clamp back to the grapheme
          -- start. Jump to the next word instead.
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

  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    if t.byte_start >= cursor then
      if is_whitespace(t) then
        i = i + 1
      elseif is_zwj(t) then
        i = i + 1
      else
        -- 'e' on a single-byte word (cursor at its start AND end)
        -- should advance to the next word's end, matching Vim.
        -- ce/de then compute the correct visual range.
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
        -- For ZWJ sequences, return the sequence's first byte
        -- (not the last) — nvim treats the whole sequence as
        -- one grapheme and clamps the cursor there.
        if next_is_zwj(tokens, i) then
          if t.byte_start == cursor then
            -- Cursor already on sequence's first byte; jump past it.
            i = zwj_seq_end(tokens, i) + 1
          else
            return t.byte_start
          end
        elseif prev_is_zwj(tokens, i) then
          i = zwj_seq_end(tokens, i) + 1
        else
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
      -- Step back to before any ZWJ sequence it's part of.
      local j = i
      while j > 1 and (is_zwj(tokens[j - 1]) or (j > 2 and is_zwj(tokens[j - 2]))) do
        j = j - 1
      end
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
      -- 'ge' from a word inside a ZWJ sequence must land on the
      -- sequence's right edge, not on an intermediate token's end.
      prev = tokens[zwj_seq_end(tokens, i)]
    end
  end
  return (prev or { byte_end = 1 }).byte_end
end

return M
