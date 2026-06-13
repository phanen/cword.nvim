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
  for _, t in ipairs(cut(line)) do
    if t.byte_start > cursor and not is_whitespace(t) then
      return t.byte_start
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
  for _, t in ipairs(cut(line)) do
    if t.byte_start < cursor then
      if not is_whitespace(t) then
        prev = t
      end
      if cursor <= t.byte_end then
        inside = t
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
  -- If the cursor is inside a word, return that word's end.
  -- Otherwise, return the end of the next word.
  local first
  for _, t in ipairs(cut(line)) do
    if t.byte_start <= cursor and t.byte_end > cursor and not is_whitespace(t) then
      return t.byte_end
    end
    if not first and t.byte_start > cursor and not is_whitespace(t) then
      first = t
    end
  end
  if first then
    return first.byte_end
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
  for _, t in ipairs(cut(line)) do
    if t.byte_end < cursor and not is_whitespace(t) then
      prev = t
    end
    if cursor <= t.byte_end then
      break
    end
  end
  return (prev or { byte_end = 1 }).byte_end
end

return M
