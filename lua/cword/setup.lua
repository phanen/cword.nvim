-- Default keymap wiring. Calls setup({}) to bind w/b/e/ge using the
-- CJK-aware word motion; users can override or extend.
--
-- Wrap behavior matches Vim's built-in w/b/e/ge: forward motions at
-- the end of a line continue into the next non-empty line; backward
-- motions from column 1 (col 0 in 0-indexed terms) on a non-empty
-- line continue into the previous line. Empty lines stop the motion
-- rather than jump through them.

local M = {}

local DEFAULTS = {
  backend = 'cjk',
  keys = {
    word_forward = 'w',
    word_backward = 'b',
    word_end_forward = 'e',
    word_end_backward = 'ge',
  },
}

---Detect the best available backend at runtime. Prefers icu_ffi when
---libicuuc is loadable (matches JS Intl.Segmenter behavior), falls
---back to the pure-Lua cjk backend otherwise.
---@return string
local function detect_default_backend()
  local ok = pcall(function()
    require('ffi').load('icuuc')
  end)
  if ok then
    return 'icu_ffi'
  end
  return 'cjk'
end

M.detect_default_backend = detect_default_backend

-- Find the first word-start in `line`, 1-indexed byte offset. Returns
-- nil if the line has no word.
---@param segmenter table
---@param line string
---@return integer|nil
local function first_word_start(segmenter, line)
  for _, t in ipairs(segmenter:cut(line)) do
    if t.is_word_like then
      return t.byte_start
    end
  end
  return nil
end

-- Find the last word-end in `line`, 1-indexed byte offset. Returns
-- nil if the line has no word.
---@param segmenter table
---@param line string
---@return integer|nil
local function last_word_end(segmenter, line)
  local last
  for _, t in ipairs(segmenter:cut(line)) do
    if t.is_word_like then
      last = t.byte_end
    end
  end
  return last
end

local function make_handler(segmenter, method)
  local motion = require('cword.motion')
  local is_forward = method == motion.forward or method == motion.end_forward
  local is_backward = method == motion.backward or method == motion.end_backward

  return function()
    local win = vim.api.nvim_get_current_win()
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local cursor = col0 + 1
    local line = vim.api.nvim_get_current_line()
    local target = method(segmenter, line, cursor)
    local new_row, new_col1 = row, target

    -- Wrap forward past the end of the current line into the next
    -- non-empty line. Empty lines stop the wrap (matches Vim's
    -- built-in w which halts at the start of an empty line).
    if is_forward and target >= #line then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for r = row + 1, #lines do
        local start = first_word_start(segmenter, lines[r] or '')
        if start then
          new_row, new_col1 = r, start
          break
        elseif #(lines[r] or '') == 0 then
          new_row, new_col1 = r, 1
          break
        end
      end
    elseif is_backward and target <= 1 and col0 == 0 then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for r = row - 1, 1, -1 do
        local last = last_word_end(segmenter, lines[r] or '')
        if last then
          new_row, new_col1 = r, last
          break
        elseif #(lines[r] or '') == 0 then
          new_row, new_col1 = r, 1
          break
        end
      end
    end

    vim.api.nvim_win_set_cursor(win, { new_row, math.max(0, new_col1 - 1) })
  end
end

---@param opts table? { backend = "cjk"|"icu_ffi", keys = { ... } }
function M.setup(opts)
  opts = opts or {}
  if not opts.backend then
    opts.backend = detect_default_backend()
  end
  opts = vim.tbl_deep_extend('force', DEFAULTS, opts)
  local Segmenter = require('cword.segmenter')
  local segmenter = Segmenter.new({ backend = opts.backend })

  local keymap_opts = { noremap = true, silent = true }
  local motion = require('cword.motion')
  vim.keymap.set('n', opts.keys.word_forward, make_handler(segmenter, motion.forward), keymap_opts)
  vim.keymap.set(
    'n',
    opts.keys.word_backward,
    make_handler(segmenter, motion.backward),
    keymap_opts
  )
  vim.keymap.set(
    'n',
    opts.keys.word_end_forward,
    make_handler(segmenter, motion.end_forward),
    keymap_opts
  )
  vim.keymap.set(
    'n',
    opts.keys.word_end_backward,
    make_handler(segmenter, motion.end_backward),
    keymap_opts
  )
end

return M
