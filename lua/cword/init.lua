-- Public entry point.
--
--   local cword = require('cword')
--   local seg   = cword.Segmenter.new({ backend = 'cjk' })
--   local m     = cword.Motion.new({ segmenter = seg })

local M = {}

M.Segmenter = require('cword.segmenter')
M.Motion = require('cword.motion')

M.version = '0.1.0'

return M
