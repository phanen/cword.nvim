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
  -- The icu_ffi backend is mandatory: every supported platform
  -- ships libicuuc and the LuaJIT FFI binding loads it eagerly
  -- at require time. The pcall probe is only there so a clean
  -- import does not hard-crash if libicuuc is somehow missing
  -- (e.g. a test harness that fakes the FFI module).
  local ok = pcall(function()
    require('ffi').load('icuuc')
  end)
  assert(ok, 'cword: libicuuc is required but could not be loaded')
  return 'icu_ffi'
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

-- Operator-pending motion handlers. Registered in 'o' mode with
-- `expr = true`; the returned `<Cmd>lua ...<CR>` string aborts the
-- pending operator and switches to normal-mode for the Lua snippet.
-- The Lua snippet builds a visual selection (`virtualedit=onemore`
-- so the cursor may sit one cell past the last byte of a line — this
-- is what makes CJK end-of-line motion work) and then applies the
-- operator. Pattern from 'mini.ai' (select_textobject).
--
-- Cross-line wrap is the tricky case. With virtualedit=onemore and
-- `nvim_win_set_cursor`, the cursor at (line, 0) is "on the first
-- char" of that line, so a visual range from (line1, 0) to (line2, 0)
-- eats the first character of line2 ("hello\nworld" becomes "orld"
-- after `dw`). The fix is to anchor the visual end on the *previous*
-- line at its byte length: that position is past the last char of
-- line1 (allowed by onemore) and the visual range then includes the
-- trailing newline without grabbing line2.
local function op_motion(method, direction)
  return function()
    if not _seg then
      M.setup()
    end
    local count = math.max(1, vim.v.count1)
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
    local r, c = row, col0 + 1
    for _ = 1, count do
      local line = vim.api.nvim_get_current_line()
      c = method(_seg, line, c)
      if direction == 'forward' and c >= #line then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local found = false
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
        end
        if not found then
          break
        end
      elseif direction == 'backward' and c <= 1 and col0 == 0 then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local found = false
        for nr = r - 1, 1, -1 do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_seg:cut(s)) do
            if not is_whitespace(t) then
              r, c = nr, t.byte_start
              found = true
            end
          end
          if found then
            break
          end
        end
        if not found then
          break
        end
      end
    end
    if r == row and c - 1 == col0 then
      return '<Esc>'
    end
    local s_row, s_col
    local e_row, e_col
    if direction == 'backward' then
      s_row, s_col = r - 1, c - 1
      -- For cross-line backward, anchor the visual end on the
      -- line where the motion landed (col = byte length) so the
      -- visual range stops at the trailing newline without
      -- grabbing the first char of the cursor's line.
      if r < row then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        e_row, e_col = r - 1, #(lines[r] or '')
      else
        e_row, e_col = row - 1, math.max(0, col0 - 1)
      end
    else
      s_row, s_col = row - 1, col0
      -- For cross-line forward we anchor the visual end on the
      -- line *before* the wrap target (col = byte length) so the
      -- visual range stops at the trailing newline instead of
      -- including the first char of the next line.
      if r > row then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        e_row, e_col = r - 2, #(lines[r - 1] or '')
      else
        e_row, e_col = r - 1, math.max(0, c - 2)
      end
    end
    if s_row > e_row or (s_row == e_row and s_col > e_col) then
      s_row, s_col, e_row, e_col = e_row, e_col, s_row, s_col
    end
    local op = vim.v.operator
    local cmd
    if op == 'd' then
      cmd = 'd'
    elseif op == 'c' then
      cmd = 'c'
    elseif op == 'y' then
      cmd = 'y'
    else
      return '<Esc>'
    end
    local cache_ve = vim.o.virtualedit
    return string.format(
      '<Cmd>lua vim.o.virtualedit="onemore";'
        .. 'vim.api.nvim_win_set_cursor(0, {%d, %d});'
        .. 'vim.cmd("normal! v");'
        .. 'vim.api.nvim_win_set_cursor(0, {%d, %d})<CR>'
        .. '<Cmd>lua vim.cmd("normal! %s");vim.o.virtualedit=%q<CR>',
      s_row + 1,
      s_col,
      e_row + 1,
      e_col,
      cmd,
      cache_ve
    )
  end
end

M.op_forward = op_motion(M.motion.forward, 'forward')
M.op_backward = op_motion(M.motion.backward, 'backward')
M.op_end_forward = op_motion(M.motion.end_forward, 'end_forward')
M.op_end_backward = op_motion(M.motion.end_backward, 'end_backward')

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

-- Exposed for spec probing.
M._default_backend = default_backend

return M
