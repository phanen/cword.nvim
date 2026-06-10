-- Public entry point.
--
--   require('cword').setup()       -- init (auto-called on first move_* if omitted)
--   vim.keymap.set('n', 'w',  require('cword').move_forward)
--   vim.keymap.set('n', 'b',  require('cword').move_backward)
--   vim.keymap.set('n', 'e',  require('cword').move_end_forward)
--   vim.keymap.set('n', 'ge', require('cword').move_end_backward)
--
-- Visual mode: bind the same move_* in 'x' mode. Visual selection
-- auto-extends from the '< mark to the new cursor.

local M = {}

M.Segmenter = require('cword.segmenter')
M.motion = require('cword.motion')

-- Lazy-init state. _seg is set on the first call to setup() or to
-- any move_* handler.
local _seg ---@type table

---@param tok table
---@return boolean
local function is_whitespace(tok)
  return tok.text:match('^%s+$') ~= nil
end

---@return string
local function default_backend()
  local ok = pcall(function()
    require('ffi').load('icuuc')
  end)
  return ok and 'icu_ffi' or 'cjk'
end

---@param opts? { backend?: string }
function M.setup(opts)
  if _seg then
    return
  end
  opts = opts or {}
  _seg = M.Segmenter.new({ backend = opts.backend or default_backend() })
end

-- Wrap-aware cursor mover used by all four directions. `direction` is
-- 'forward' | 'backward' | 'end_forward' | 'end_backward'.
local function cursor_move(method, direction)
  local is_fwd = direction == 'forward'
  local is_bwd = direction == 'backward'

  return function()
    if not _seg then
      M.setup()
    end

    local win = vim.api.nvim_get_current_win()
    local count = math.max(1, vim.v.count1)
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local r, c = row, col0 + 1

    for _ = 1, count do
      local found = false
      local line = vim.api.nvim_get_current_line()
      c = method(_seg, line, c)

      if is_fwd and c >= #line then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for nr = r + 1, #lines do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_seg:cut(s)) do
            if not is_whitespace(t) then
              r, c = nr, t.byte_start
              found = true
              break
            end
          end
          if found then
            break
          end
          if #s == 0 then
            r, c = nr, 1
            found = true
            break
          end
        end
        if not found then
          c = #line
          break
        end
      elseif is_bwd and c <= 1 and col0 == 0 then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for nr = r - 1, 1, -1 do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_seg:cut(s)) do
            if not is_whitespace(t) then
              r, c = nr, t.byte_end
              found = true
            end
          end
          if found then
            break
          end
          if #s == 0 then
            r, c = nr, 1
            found = true
            break
          end
        end
        if not found then
          c = 1
          break
        end
      end
    end

    vim.api.nvim_win_set_cursor(win, { r, math.max(0, c - 1) })
  end
end

M.move_forward = cursor_move(M.motion.forward, 'forward')
M.move_backward = cursor_move(M.motion.backward, 'backward')
M.move_end_forward = cursor_move(M.motion.end_forward, 'end_forward')
M.move_end_backward = cursor_move(M.motion.end_backward, 'end_backward')

-- Insert-mode word motions (readline-style).

local function insert_move(method, direction)
  local is_fwd = direction == 'forward' or direction == 'end_forward'
  return function()
    if not _seg then
      M.setup()
    end
    local win = vim.api.nvim_get_current_win()
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local cursor = col0 + 1
    local line = vim.api.nvim_get_current_line()
    -- In insert mode, cursor is between chars (col0). Move to
    -- col0+1 for forward, col0 for backward (exclusive).
    local target
    if is_fwd then
      target = method(_seg, line, cursor)
    else
      -- backward: use cursor as-is (exclusive bound)
      target = method(_seg, line, cursor)
    end
    vim.api.nvim_win_set_cursor(win, { row, math.max(0, target - 1) })
  end
end

M.insert_forward = insert_move(M.motion.forward, 'forward')
M.insert_backward = insert_move(M.motion.backward, 'backward')
M.insert_end_forward = insert_move(M.motion.end_forward, 'end_forward')
M.insert_end_backward = insert_move(M.motion.end_backward, 'end_backward')

-- Insert-mode delete word backward (<c-w>).

M.insert_delete_word = function()
  if not _seg then
    M.setup()
  end
  local win = vim.api.nvim_get_current_win()
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
  local cursor = col0 + 1
  local line = vim.api.nvim_get_current_line()
  local target = M.motion.backward(_seg, line, cursor)
  if target < cursor then
    vim.api.nvim_buf_set_text(0, row - 1, target - 1, row - 1, col0, { '' })
  end
end

-- Command-line mode word motions.

M.cmdline_forward = function()
  if not _seg then
    M.setup()
  end
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local target = M.motion.forward(_seg, line, pos)
  if target > pos then
    vim.fn.setcmdpos(target)
  end
end

M.cmdline_backward = function()
  if not _seg then
    M.setup()
  end
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local target = M.motion.backward(_seg, line, pos)
  if target < pos then
    vim.fn.setcmdpos(target)
  end
end

M.cmdline_delete_word = function()
  if not _seg then
    M.setup()
  end
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local target = M.motion.backward(_seg, line, pos)
  if target < pos then
    vim.fn.setcmdline(line:sub(1, target - 1) .. line:sub(pos))
    vim.fn.setcmdpos(target)
  end
end

-- Direct operator replacements (dw/cw/de/ce/db/cb). Bypass
-- operator-pending mode and Neovim's cursor-API clamping by
-- using nvim_buf_set_text with the motion's 1-indexed target.
local function op_range(method)
  if not _seg then
    M.setup()
  end
  local win = vim.api.nvim_get_current_win()
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
  local line = vim.api.nvim_get_current_line()
  local target = method(_seg, line, col0 + 1)
  return row, col0, target
end

-- Forward: target is 1-idx next-word-start or #line+1.
-- end_col = target - 1 is the 0-idx exclusive end.

M.delete_forward = function()
  local row, col0, target = op_range(M.motion.forward)
  if target - 1 > col0 then
    vim.api.nvim_buf_set_text(0, row - 1, col0, row - 1, target - 1, { '' })
  end
end

M.delete_end_forward = function()
  local row, col0, target = op_range(M.motion.end_forward)
  if target - 1 > col0 then
    vim.api.nvim_buf_set_text(0, row - 1, col0, row - 1, target - 1, { '' })
  end
end

M.change_forward = function()
  local row, col0, target = op_range(M.motion.forward)
  if target - 1 > col0 then
    vim.api.nvim_buf_set_text(0, row - 1, col0, row - 1, target - 1, { '' })
  end
  vim.cmd('startinsert')
end

M.change_end_forward = function()
  local row, col0, target = op_range(M.motion.end_forward)
  if target - 1 > col0 then
    vim.api.nvim_buf_set_text(0, row - 1, col0, row - 1, target - 1, { '' })
  end
  vim.cmd('startinsert')
end

-- Backward: target (byte_start) = 1-idx of previous word.
-- Delete from target-1 (beginning of the word) to col0 (cursor).

M.delete_backward = function()
  local row, col0, target = op_range(M.motion.backward)
  if target <= col0 then
    vim.api.nvim_buf_set_text(0, row - 1, target - 1, row - 1, col0, { '' })
  end
end

M.change_backward = function()
  local row, col0, target = op_range(M.motion.backward)
  if target <= col0 then
    vim.api.nvim_buf_set_text(0, row - 1, target - 1, row - 1, col0, { '' })
  end
  vim.cmd('startinsert')
end

-- Exposed for spec probing.
M._default_backend = default_backend

return M
