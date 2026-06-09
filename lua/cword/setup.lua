-- Default keymap wiring. Calls setup({}) to bind w/b/e/ge using the
-- CJK-aware word motion; users can override or extend.

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

local function make_handler(segmenter, method)
  return function()
    local win = vim.api.nvim_get_current_win()
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local line = vim.api.nvim_get_current_line()
    local target = method(segmenter, line, col0 + 1)
    vim.api.nvim_win_set_cursor(win, { row, math.max(0, target - 1) })
  end
end

---@param opts table? { backend = "cjk"|"icu"|"icu_ffi"|"char", keys = { ... } }
function M.setup(opts)
  opts = vim.tbl_deep_extend('force', DEFAULTS, opts or {})
  local Segmenter = require('cword.segmenter')
  local segmenter = Segmenter.new({ backend = opts.backend })
  local motion = require('cword.motion')

  local keymap_opts = { noremap = true, silent = true }
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
