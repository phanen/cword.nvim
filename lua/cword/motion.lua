-- Word motion on top of a Segmenter.
--
-- Phase 2 stub. The API is sketched so that Phase 1's segmentation work can
-- be exercised end-to-end, but the actual w/b/e/ge implementations will
-- land in the next step. The contract:
--
--   local motion = require("cword").Motion.new({ segmenter = seg })
--   local col    = motion:forward(line, cursor)   -- next word start
--   local col    = motion:backward(line, cursor)  -- prev word start
--   local col    = motion:end_forward(line, cursor) -- next word end
--   local col    = motion:end_backward(line, cursor) -- prev word end
--
-- All cursor and column arguments/returns are 1-indexed byte offsets into
-- `line` (matching Vim's column model). `line` does NOT include the
-- trailing newline; pass `vim.api.nvim_get_current_line()` style.

local M = {}

function M.new(opts)
  opts = opts or {}
  if not opts.segmenter then
    error('cword.Motion.new: opts.segmenter is required')
  end
  return setmetatable({
    segmenter = opts.segmenter,
  }, { __index = M })
end

-- TODO(phase 2): implement forward/backward/end_forward/end_backward.
-- Reference: packages/wordmotion.nvim/lua/wordmotion/word.lua and
-- packages/wordmotion.nvim/lua/wordmotion/sentence.lua for the
-- Vim-compatible semantics.
function M:forward(_line, _cursor)
  error('cword.Motion:forward is not implemented yet (phase 2)')
end

function M:backward(_line, _cursor)
  error('cword.Motion:backward is not implemented yet (phase 2)')
end

function M:end_forward(_line, _cursor)
  error('cword.Motion:end_forward is not implemented yet (phase 2)')
end

function M:end_backward(_line, _cursor)
  error('cword.Motion:end_backward is not implemented yet (phase 2)')
end

return M
