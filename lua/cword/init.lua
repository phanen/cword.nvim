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

-- Bound at require-time; no lazy-init needed.
local _cut = M.Segmenter.cut

---@param tok table
---@return boolean
local function is_whitespace(tok)
  return tok.text:match('^%s+$') ~= nil
end

-- No-op kept for backward compatibility with existing configs.
function M.setup() end

-- Wrap-aware cursor mover used by all four directions. `direction` is
-- 'forward' | 'backward' | 'end_forward' | 'end_backward'.
local function cursor_move(method, direction)
  local is_fwd = direction == 'forward'
  local is_bwd = direction == 'backward'
  local is_end_fwd = direction == 'end_forward'
  local is_end_bwd = direction == 'end_backward'

  return function()
    local win = vim.api.nvim_get_current_win()
    local count = math.max(1, vim.v.count1)
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local r, c = row, col0 + 1

    for _ = 1, count do
      local found = false
      local line = vim.api.nvim_get_current_line()
      c = method(_cut, line, c)

      if is_fwd and c >= #line then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for nr = r + 1, #lines do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_cut(s)) do
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
          for _, t in ipairs(_cut(s)) do
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
      elseif is_end_fwd and c >= #line then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local found = false
        for nr = r + 1, #lines do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_cut(s)) do
            if not is_whitespace(t) then
              r, c = nr, t.byte_end
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
      elseif is_end_bwd and c <= 1 and col0 == 0 then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local found = false
        for nr = r - 1, 1, -1 do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_cut(s)) do
            if not is_whitespace(t) then
              r, c = nr, t.byte_end
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

    local new_col = math.max(0, c - 1)
    -- Snap the column to a valid code-point start so that nvim
    -- does not clamp it back to a different position on the next
    -- read.  If the snap lands at or before the entry cursor,
    -- nvim clamped us back; skip to the next token's char start.
    if is_end_fwd or is_end_bwd then
      local line = vim.api.nvim_get_current_line()
      local sn = new_col + 1
      local b = string.byte(line, sn)
      while b and b >= 0x80 and b < 0xC0 do
        sn = sn - 1
        b = string.byte(line, sn)
      end
      new_col = sn - 1
      if new_col <= col0 then
        local toks = _cut(line)
        if is_end_fwd then
          for _, t in ipairs(toks) do
            if t.byte_start > col0 + 1 and not is_whitespace(t) then
              new_col = sn - 1
              -- resnap t.byte_end
              sn = t.byte_end
              b = string.byte(line, sn)
              while b and b >= 0x80 and b < 0xC0 do
                sn = sn - 1
                b = string.byte(line, sn)
              end
              new_col = sn - 1
              break
            end
          end
        else
          for i = #toks, 1, -1 do
            local t = toks[i]
            if t.byte_end < col0 + 1 and not is_whitespace(t) then
              sn = t.byte_end
              b = string.byte(line, sn)
              while b and b >= 0x80 and b < 0xC0 do
                sn = sn - 1
                b = string.byte(line, sn)
              end
              new_col = sn - 1
              break
            end
          end
        end
      end
    end
    vim.api.nvim_win_set_cursor(win, { r, new_col })
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
    local count = math.max(1, vim.v.count1)
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
    local r, c = row, col0 + 1
    local orig_line = vim.api.nvim_get_current_line()
    local orig_line_len = #orig_line
    for _ = 1, count do
      local line = vim.api.nvim_get_current_line()
      c = method(_cut, line, c)
      -- Forward: when there is no next word on the current line,
      -- only wrap to the next line when the count loop hasn't
      -- finished (i.e. more motions are pending). The final
      -- iteration that runs out of content stays at #line + 1
      -- (past the last character) without crossing the newline,
      -- matching stock Vim's operator-pending w semantics.
      if direction == 'forward' and c >= #line then
        if _ < count then
          local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
          local found = false
          for nr = r + 1, #lines do
            local s = lines[nr]
            if not s then
              break
            end
            for _, t in ipairs(_cut(s)) do
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
            c = #line + 1
            break
          end
        else
          c = #line + 1
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
          for _, t in ipairs(_cut(s)) do
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
      elseif direction == 'end_backward' and c <= 1 and col0 == 0 then
        -- Stock nvim's ge from BOL wraps to the last character of
        -- the previous non-empty line (not the last word's start).
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local found = false
        for nr = r - 1, 1, -1 do
          local s = lines[nr]
          if not s then
            break
          end
          if #s > 0 then
            -- Target the START of the last character on the line
            -- so the visual endpoint is always on a char boundary.
            local last_col = #s - 1
            local sn = last_col + 1
            local b = string.byte(s, sn)
            while b and b >= 0x80 and b < 0xC0 do
              sn = sn - 1
              b = string.byte(s, sn)
            end
            r, c, found = nr, sn - 1, true
            break
          end
        end
        if not found then
          break
        end
      elseif direction == 'end_forward' and c >= #line then
        -- TODO: count > 1 wraps on every iteration; the forward
        -- (w) wrap guards with `_ < count` so the final iteration
        -- stays at EOL.  Match that here for d2e/d3e parity.
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local found = false
        for nr = r + 1, #lines do
          local s = lines[nr]
          if not s then
            break
          end
          for _, t in ipairs(_cut(s)) do
            if not is_whitespace(t) then
              r, c, found = nr, t.byte_end, true
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
      -- For end_backward, snap col0 forward past the current
      -- multi-byte character so the visual endpoint covers the
      -- full character width (capped at line end - 1 to avoid
      -- including the trailing newline).
      if direction == 'end_backward' and col0 > 0 and col0 < orig_line_len then
        local sn = col0 + 1
        local b = string.byte(orig_line, sn)
        if b and b >= 0xC0 then
          sn = sn + 1
          while sn <= orig_line_len do
            b = string.byte(orig_line, sn)
            if not b or b < 0x80 or b >= 0xC0 then
              break
            end
            sn = sn + 1
          end
          col0 = math.min(sn - 1, orig_line_len - 1)
        end
      end
      s_row, s_col = row - 1, col0
      if r > row then
        if direction == 'end_forward' then
          -- Cross-line end_forward: c is byte_end (1-indexed).
          -- Use c - 1 as 0-indexed visual endpoint to land on the
          -- last byte of the target word (consistent with
          -- non-cross-line end_forward).
          e_row, e_col = r - 1, math.max(0, c - 1)
        else
          -- Cross-line forward: the visual end is on the target
          -- line at c - 2 (exclusive of the next word's first
          -- byte).  This matches stock Vim's exclusive motion
          -- boundary: d deletes from cursor to just before the
          -- motion target.
          e_row, e_col = r - 1, math.max(0, c - 2)
        end
      elseif direction == 'end_backward' and r < row then
        -- Cross-line end_backward: visual from (target_line,
        -- c) to (cursor_line, 0).  c is the char start of the
        -- last character on the target line (set by the cross-
        -- line wrapping block).  This captures the target char,
        -- the trailing newline, and the first char of the
        -- cursor's line -- matching stock nvim's dge at BOL.
        s_row, s_col = r - 1, c
        e_row, e_col = row - 1, 0
      elseif direction == 'end_forward' then
        -- end_forward returns byte_end (1-indexed, inclusive).
        -- Convert to 0-indexed column by subtracting 1.
        e_row, e_col = r - 1, math.max(0, c - 1)
      elseif direction == 'end_backward' then
        -- end_backward returns byte_end (1-indexed, inclusive) of
        -- the previous word. Convert to 0-indexed by subtracting 1.
        -- Snap to character boundary to avoid splitting multi-byte chars.
        local target_col = math.max(0, c - 1)
        if target_col > 0 and target_col < orig_line_len then
          local sn = target_col + 1
          local b = string.byte(orig_line, sn)
          if b and b >= 0x80 and b < 0xC0 then
            -- In the middle of a multi-byte char, snap backward
            while sn > 1 do
              sn = sn - 1
              b = string.byte(orig_line, sn)
              if b and b >= 0xC0 then
                break
              end
            end
            target_col = sn - 1
          end
        end
        e_row, e_col = r - 1, target_col
      else
        -- forward returns byte_start of the next word.
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

-- Textobject handlers for `iw` (inner word) and `aw` (a word).
-- Same pattern as op_motion: return a `<Cmd>lua ...<CR>` snippet
-- that builds a visual selection under `virtualedit=onemore`
-- and then runs the pending operator. In visual mode the same
-- Lua code is run synchronously and the operator branch is
-- skipped (the selection just extends the existing visual range).
local function textobject(ai_type)
  return function()
    local op = vim.v.operator
    local in_visual = (vim.api.nvim_get_mode().mode:sub(1, 1) == 'v')

    local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    if #line == 0 then
      return in_visual and '' or '<Esc>'
    end
    local c = col0 + 1 -- 1-indexed byte cursor

    -- Walk the tokens once to find the word the cursor is on
    -- (or the whitespace if it sits between words). Going through
    -- the segmenter directly avoids the motion module's "go to
    -- the previous word at a boundary" behavior, which would
    -- mis-select when the cursor lands on the first byte of a
    -- word.
    local toks = _cut(line)
    local word_tok = nil
    for _, t in ipairs(toks) do
      if t.byte_start <= c and t.byte_end >= c then
        if not is_whitespace(t) then
          word_tok = t
        end
        break
      end
    end
    if not word_tok then
      -- Cursor is on whitespace or past the last token. Abort
      -- rather than mis-select the previous word.
      return in_visual and '' or '<Esc>'
    end

    local start_c = word_tok.byte_start
    local end_c = word_tok.byte_end + 1

    -- For `aw`, extend the right edge over the trailing
    -- whitespace run if one immediately follows the word.
    if ai_type == 'a' then
      for i, t in ipairs(toks) do
        if t == word_tok then
          local nxt = toks[i + 1]
          if nxt and is_whitespace(nxt) then
            end_c = nxt.byte_end + 1
          end
          break
        end
      end
    end

    -- Convert to 0-indexed visual coordinates. `nvim_win_set_cursor`
    -- plus the visual mode that follows in the operator-pending
    -- branch uses "on the char" semantics, so the end column is
    -- `end_c - 2` (one past the last byte in 1-indexed form minus
    -- one for 0-indexing). The visual mode branch below uses the
    -- live visual mode's "between chars" semantics instead, so
    -- it shifts the end column by one.
    local s_row = row - 1
    local s_col = start_c - 1
    local e_row = row - 1
    local e_col = end_c - 2

    if in_visual then
      -- Visual mode: drop out of visual, park the cursor at the
      -- new anchor, then re-enter visual and walk to the end
      -- column with a single `normal!` so the live visual mode
      -- motion (which is "between chars", unlike the `<Cmd>lua`
      -- branch's nvim_win_set_cursor "on the char" semantics)
      -- covers exactly the intended byte range.
      local cache_ve = vim.o.virtualedit
      vim.o.virtualedit = 'onemore'
      vim.cmd('normal! v') -- exit visual
      vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
      vim.cmd('normal! v') -- re-enter at the new anchor
      vim.api.nvim_win_set_cursor(0, { e_row + 1, end_c - 1 })
      vim.cmd('redraw')
      vim.schedule(function()
        vim.o.virtualedit = cache_ve
      end)
      return ''
    end

    if op ~= 'd' and op ~= 'c' and op ~= 'y' then
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
      op,
      cache_ve
    )
  end
end

M.op_forward = op_motion(M.motion.forward, 'forward')
M.op_backward = op_motion(M.motion.backward, 'backward')
M.op_end_forward = op_motion(M.motion.end_forward, 'end_forward')
M.op_end_backward = op_motion(M.motion.end_backward, 'end_backward')

-- Textobjects: bind these in 'x' (visual) and 'o' (operator-
-- pending) mode. In 'o' mode, `expr = true` is required.
M.textobject_inner_word = textobject('i')
M.textobject_a_word = textobject('a')

-- Insert-mode word motions (readline-style).

local function insert_move(method, direction)
  local is_fwd = direction == 'forward' or direction == 'end_forward'
  return function()
    local win = vim.api.nvim_get_current_win()
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local cursor = col0 + 1
    local line = vim.api.nvim_get_current_line()
    local target = method(_cut, line, cursor)

    -- If forward returned past-end and the cursor is not yet at end
    -- of line, move to end first. Only wrap on a subsequent call.
    if is_fwd and target > #line and cursor <= #line then
      target = #line + 1
    elseif is_fwd and target > #line and cursor > #line then
      -- Scan forward lines for the first non-whitespace token.
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local found = false
      local r = row
      for nr = r + 1, #lines do
        local s = lines[nr]
        if not s then
          break
        end
        for _, t in ipairs(_cut(s)) do
          if not is_whitespace(t) then
            row, target, found = nr, t.byte_start, true
            break
          end
        end
        if found then
          break
        end
        if #s == 0 then
          row, target, found = nr, 1, true
          break
        end
      end
      if not found then
        return
      end
    elseif not is_fwd and target <= 1 and col0 == 0 then
      -- Scan backward lines for the last non-whitespace token.
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local found = false
      for nr = row - 1, 1, -1 do
        local s = lines[nr]
        if not s then
          break
        end
        for _, t in ipairs(_cut(s)) do
          if not is_whitespace(t) then
            row, target, found = nr, t.byte_end + 1, true
          end
        end
        if found then
          break
        end
        if #s == 0 then
          row, target, found = nr, 1, true
          break
        end
      end
      if not found then
        return
      end
    end

    local target_col = math.max(0, target - 1)
    pcall(vim.api.nvim_win_set_cursor, win, { row, target_col })
  end
end

M.insert_forward = insert_move(M.motion.forward, 'forward')
M.insert_backward = insert_move(M.motion.backward, 'backward')
M.insert_end_forward = insert_move(M.motion.end_forward, 'end_forward')
M.insert_end_backward = insert_move(M.motion.end_backward, 'end_backward')

-- Insert-mode delete word backward (<c-w>).
M.insert_delete_word = function()
  local win = vim.api.nvim_get_current_win()
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
  local cursor = col0 + 1
  local line = vim.api.nvim_get_current_line()

  -- Empty line at col 0: delete the newline, joining with the
  -- previous line (matching Vim's built-in <c-w>).
  if col0 == 0 and row > 1 then
    local prev = vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1] or ''
    local prev_len = #prev
    vim.fn.setreg('-', '\n')
    vim.o.undolevels = vim.o.undolevels
    vim.api.nvim_buf_set_lines(0, row - 2, row, false, { prev .. line })
    pcall(vim.api.nvim_win_set_cursor, 0, { row - 1, prev_len })
    return
  end

  local target = M.motion.backward(_cut, line, cursor)
  if target >= cursor then
    return
  end

  -- Eat the word before cursor plus any following whitespace.
  local toks = _cut(line)
  local eat_to = col0 -- 0-indexed exclusive end
  local seen_word = false
  for _, t in ipairs(toks) do
    if t.byte_start >= target then
      if not seen_word then
        if not is_whitespace(t) then
          seen_word = true
        end
      elseif is_whitespace(t) then
        eat_to = t.byte_end
      else
        break
      end
    end
  end
  local eat_from = target - 1
  local row1 = row - 1
  -- Yank into the small-delete register now, then schedule
  -- the buffer mutation with an undo breakpoint.
  vim.fn.setreg('-', (vim.api.nvim_buf_get_text(0, row1, eat_from, row1, eat_to, {})[1] or ''))
  vim.o.undolevels = vim.o.undolevels
  vim.api.nvim_buf_set_text(0, row1, eat_from, row1, eat_to, { '' })
  return
end

-- Command-line mode word motions.

M.cmdline_forward = function()
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local target = M.motion.forward(_cut, line, pos)
  if target > pos then
    vim.fn.setcmdline(line, target)
  end
end

M.cmdline_backward = function()
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local target = M.motion.backward(_cut, line, pos)
  if target < pos then
    vim.fn.setcmdline(line, target)
  end
end

M.cmdline_delete_word = function()
  local line = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local target = M.motion.backward(_cut, line, pos)
  if target < pos then
    vim.fn.setcmdline(line:sub(1, target - 1) .. line:sub(pos), target)
  end
end

-- Exposed for spec probing.

return M
