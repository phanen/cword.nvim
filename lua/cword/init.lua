-- cword.nvim: CJK-aware word segmentation + word motion for Neovim.
--
-- Public entry point.
--
-- Phase 1 (this commit): segmentation API.
--   local cword    = require("cword")
--   local Segmenter = cword.Segmenter
--   local seg      = Segmenter.new({ backend = "cjk" })   -- default
--   local tokens   = seg:cut("你好，世界 hello")
--
-- Phase 2 (next): word motion on top of the segmenter.
--   local motion = cword.Motion.new({ segmenter = seg })
--   motion:forward(line, cursor)

local M = {}

M.Segmenter = require('cword.segmenter')
M.Motion = require('cword.motion')

M.version = '0.1.0'

return M
