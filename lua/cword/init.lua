-- Public entry point.
--
--   local cword = require('cword')
--   cword.setup({ backend = 'cjk' }) -- default; binds w/b/e/ge
--
--   -- Or build your own binding on top of the motion utilities:
--   local seg = cword.Segmenter.new({ backend = 'icu_ffi' })
--   vim.keymap.set('n', '<leader>w', function()
--     local line = vim.api.nvim_get_current_line()
--     local cur = vim.api.nvim_win_get_cursor(0)[2] + 1
--     local col = cword.motion.forward(seg, line, cur)
--     vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], col - 1 })
--   end)

local M = {}

M.Segmenter = require('cword.segmenter')
M.motion = require('cword.motion')
M.setup = require('cword.setup').setup

M.version = '0.2.0'

return M
