-- Word motion utilities. Each function takes a `cut` function plus a
-- line and a 1-indexed byte cursor, and returns the next/previous
-- column as a 1-indexed byte offset. The line excludes the trailing
-- newline.
--
-- These are building blocks: bind them to keys yourself, or call
-- require('cword').setup() for the default w/b/e/ge wiring.

local M = {}

---@param tok table
---@return boolean
local function is_whitespace(tok)
  return tok.text:match('^%s+$') ~= nil
end

-- ZWJ (Zero Width Joiner) is U+200D, encoded as E2 80 8D in UTF-8.
-- Nvim treats ZWJ sequences as single grapheme clusters, so the cursor
-- cannot land in the middle of them. Motion functions must skip over
-- ZWJ tokens to avoid returning positions that nvim will clamp.
local ZWJ = '\226\128\141'

---@param tok table
---@return boolean
local function is_zwj(tok)
  return tok.text == ZWJ
end

-- Split a token into sub-tokens based on character class boundaries.
-- This mimics stock nvim's behavior where ASCII and emoji are separate words.
-- ZWJ sequences are kept together as a single token.
local function split_token_by_class(t)
  local result = {}
  local current_start = t.byte_start
  local current_text = {}
  local current_class = nil -- 'ascii', 'emoji', 'other'

  local i = t.byte_start
  while i <= t.byte_end do
    local byte = t.text:byte(i - t.byte_start + 1)
    local char_class
    local char_len = 1

    if byte < 0x80 then
      char_class = 'ascii'
      char_len = 1
    elseif byte < 0xE0 then
      char_class = 'emoji'
      char_len = 2
    elseif byte < 0xF0 then
      char_class = 'emoji'
      char_len = 3
    else
      char_class = 'emoji'
      char_len = 4
    end

    -- Add the character to the current text
    local char_text = t.text:sub(i - t.byte_start + 1, i - t.byte_start + char_len)
    table.insert(current_text, char_text)

    -- Check if we need to split
    if current_class and current_class ~= char_class then
      -- Class changed, emit the current token (without the new character)
      table.remove(current_text) -- Remove the new character
      if #current_text > 0 then
        -- All non-whitespace tokens are word-like for motion purposes.
        -- Nvim treats emoji as word characters for w/b/e/ge motions.
        table.insert(result, {
          text = table.concat(current_text),
          byte_start = current_start,
          byte_end = i - 1,
          is_word_like = true,
        })
      end
      -- Start a new token with the new character
      current_start = i
      current_text = { char_text }
    end

    current_class = char_class
    i = i + char_len
  end

  -- Emit the last token
  if #current_text > 0 then
    -- All non-whitespace tokens are word-like for motion purposes.
    -- Nvim treats emoji as word characters for w/b/e/ge motions.
    table.insert(result, {
      text = table.concat(current_text),
      byte_start = current_start,
      byte_end = t.byte_end,
      is_word_like = true,
    })
  end

  return result
end

-- Post-process tokens to split on character class boundaries.
local function postprocess_tokens(tokens)
  local result = {}
  for _, t in ipairs(tokens) do
    if not is_whitespace(t) and not is_zwj(t) then
      -- Split non-whitespace, non-ZWJ tokens by character class
      local split = split_token_by_class(t)
      for _, sub in ipairs(split) do
        table.insert(result, sub)
      end
    elseif is_zwj(t) then
      -- Mark ZWJ tokens as word-like so they're treated as part of the word
      table.insert(result, {
        text = t.text,
        byte_start = t.byte_start,
        byte_end = t.byte_end,
        is_word_like = true,
      })
    else
      table.insert(result, t)
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
      -- Check if this token is part of a ZWJ sequence (preceded by
      -- ZWJ). If so, skip it and continue looking for the next
      -- non-ZWJ token.
      if i > 1 and is_zwj(tokens[i - 1]) then
        -- This token is part of a ZWJ sequence, skip it
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
        inside = t
        -- Check if this token is part of a ZWJ sequence (preceded
        -- by ZWJ) and skip to the start of the sequence.
        local j = i
        while j > 1 and is_zwj(tokens[j - 1]) do
          j = j - 1
          if j > 1 then
            j = j - 1
            inside = tokens[j]
          end
        end
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
  local has_ascii = line:find('[%g%s]') ~= nil

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
      if i < #tokens and is_zwj(tokens[i + 1]) and t.byte_start == cursor then
        local j = i
        while j < #tokens and is_zwj(tokens[j + 1]) do
          j = j + 2
        end
        i = j + 1
      else
        local end_pos
        local should_nudge = false
        if not has_ascii and t.byte_start == cursor and cursor > 1 then
          -- CJK: cursor at start of a char (not the first char)
          should_nudge = true
        elseif has_ascii and col0 == t.byte_end - 1 then
          -- ASCII: cursor at the last byte of a word
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
        while i < #tokens and is_zwj(tokens[i + 1]) do
          i = i + 1
          if i < #tokens then
            i = i + 1
            end_pos = tokens[i].byte_end
          end
        end
        return end_pos
      end
    end
  end

  -- Cursor is not inside a word, find the next word
  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    if t.byte_start >= cursor then
      -- Skip whitespace
      if is_whitespace(t) then
        i = i + 1
      -- Skip ZWJ tokens
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
        if i < #tokens and is_zwj(tokens[i + 1]) then
          -- This is the start of a ZWJ sequence
          if t.byte_start == cursor then
            -- Cursor is already at the start of the ZWJ sequence,
            -- skip to the end and find the next word
            local j = i
            while j < #tokens and is_zwj(tokens[j + 1]) do
              j = j + 2 -- Skip ZWJ and the following token
            end
            i = j + 1
          else
            -- Return the first byte of the ZWJ sequence
            return t.byte_start
          end
        -- Check if this token is preceded by a ZWJ (part of a ZWJ sequence)
        elseif i > 1 and is_zwj(tokens[i - 1]) then
          -- This is part of a ZWJ sequence, skip to the end of the sequence
          local j = i
          while j < #tokens and is_zwj(tokens[j + 1]) do
            j = j + 2 -- Skip ZWJ and the following token
          end
          -- Return the first byte of the next word after the ZWJ sequence
          i = j + 1
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
      prev = t
      -- Check if this token is part of a ZWJ sequence (followed
      -- by ZWJ) and use the end of the entire sequence.
      local j = i
      while j < #tokens and is_zwj(tokens[j + 1]) do
        j = j + 1
        if j < #tokens then
          j = j + 1
          prev = tokens[j]
        end
      end
    end
  end
  return (prev or { byte_end = 1 }).byte_end
end

-- Export for testing
M._postprocess_tokens = postprocess_tokens

return M
