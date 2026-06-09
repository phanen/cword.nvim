-- Word motion on top of a Segmenter.
--
-- Cursor and column arguments/returns are 1-indexed byte offsets into
-- the line (matches Vim's column model); the line excludes the
-- trailing newline.

local M = {}

---@param opts { segmenter: table, nvim?: table }
---@return table
function M.new(opts)
  opts = opts or {}
  if not opts.segmenter then
    error('cword.Motion.new: opts.segmenter is required')
  end
  return setmetatable({
    segmenter = opts.segmenter,
    nvim = opts.nvim,
  }, { __index = M })
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

-- Helpers: scan tokens once, return either the current word (cursor
-- inside a word), the previous word, or nil. Used by b/ge to
-- disambiguate "cursor at start of a word" from "cursor inside a word".

---@param tokens table[]
---@param cursor integer
---@return table? current word whose [start, end] contains cursor strictly
---@return table? latest word whose end < cursor
local function scan_prev(tokens, cursor)
  local current, prev
  for _, t in ipairs(tokens) do
    if t.is_word_like and t.byte_start < cursor then
      if cursor <= t.byte_end then
        current = t
      else
        prev = t
      end
    end
  end
  return current, prev
end

---@param line string
---@param cursor integer 1-indexed byte offset
---@return integer column of next word start, or #line
function M:forward(line, cursor)
  cursor = clamp(line, cursor)
  for _, t in ipairs(self.segmenter:cut(line)) do
    if t.is_word_like and t.byte_start > cursor then
      return t.byte_start
    end
  end
  return #line
end

---@param line string
---@param cursor integer
---@return integer column of previous word start, or 1
function M:backward(line, cursor)
  cursor = clamp(line, cursor)
  local current, prev = scan_prev(self.segmenter:cut(line), cursor)
  return (current or prev or { byte_start = 1 }).byte_start
end

---@param line string
---@param cursor integer
---@return integer column of next word end, or #line
function M:end_forward(line, cursor)
  cursor = clamp(line, cursor)
  for _, t in ipairs(self.segmenter:cut(line)) do
    if t.is_word_like and t.byte_end > cursor then
      return t.byte_end
    end
  end
  return #line
end

---@param line string
---@param cursor integer
---@return integer column of previous word end, or 1
function M:end_backward(line, cursor)
  cursor = clamp(line, cursor)
  local prev
  for _, t in ipairs(self.segmenter:cut(line)) do
    if t.is_word_like and t.byte_end < cursor then
      prev = t
    end
  end
  return (prev or { byte_end = 1 }).byte_end
end

-- Bind w/b/e/ge in normal mode to call the corresponding motion method.
-- Call from inside Neovim; for nvim-test specs, invoke via
-- helpers.exec_lua so the callback lives in the embedded session's
-- Lua context (msgpack can't serialize closures).
function M:set_keymaps()
  local function go(method)
    local win = vim.api.nvim_get_current_win()
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local cursor = col0 + 1
    local line = vim.api.nvim_get_current_line()
    local target = method(self, line, cursor)
    vim.api.nvim_win_set_cursor(win, { row, math.max(0, target - 1) })
  end

  local function bind(key, method)
    vim.api.nvim_set_keymap('n', key, '', {
      noremap = true,
      silent = true,
      callback = function()
        go(method)
      end,
    })
  end
  bind('w', self.forward)
  bind('b', self.backward)
  bind('e', self.end_forward)
  bind('ge', self.end_backward)
end

return M
