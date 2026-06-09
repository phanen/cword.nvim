-- Word motion on top of a Segmenter. Phase 2 implementation lives here.
-- Cursor and column arguments/returns are 1-indexed byte offsets into
-- the line (matches Vim's column model); the line excludes the
-- trailing newline.

local M = {}

---@param opts { segmenter: table }
---@return table
function M.new(opts)
  opts = opts or {}
  if not opts.segmenter then
    error('cword.Motion.new: opts.segmenter is required')
  end
  return setmetatable({
    segmenter = opts.segmenter,
  }, { __index = M })
end

-- Phase 2 placeholders. Replaced by real implementations in the
-- motion commit.
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
