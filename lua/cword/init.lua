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

      if is_fwd and c > #line then
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
        if col0 == 0 then
          c = #line
          break
        end
        -- If the motion already advanced c to the end of a word
        -- on the same line, do not wrap. This happens when:
        --   1. the cursor was on a whitespace token and the
        --      motion found the next word, or
        --   2. the cursor was inside a word (including at its
        --      first byte) and the motion returned byte_end.
        -- Exception: if the cursor is at the start of the last
        -- character of the line, do wrap (vim's 'e' at the last
        -- char crosses to the next line).
        if c < #line + 1 then
          local on_ws = false
          local inside_word = false
          local motion_found_next = false
          for _, t in ipairs(_cut(line)) do
            if t.byte_start - 1 <= col0 and col0 <= t.byte_end - 1 then
              if is_whitespace(t) then
                on_ws = true
              elseif t.is_word_like and t.byte_end == c then
                inside_word = true
              end
            end
            if t.is_word_like and t.byte_end == c and t.byte_start - 1 > col0 then
              motion_found_next = true
            end
          end
          if on_ws then
            break
          end
          if motion_found_next then
            break
          end
          if inside_word then
            -- Check if cursor is at the start of the last char
            -- by finding the start of the last char and comparing.
            local last_char_start = #line
            while last_char_start > 1 do
              local b = string.byte(line, last_char_start)
              if b and (b < 0x80 or b >= 0xC0) then
                break
              end
              last_char_start = last_char_start - 1
            end
            if col0 + 1 == last_char_start then
              -- cursor is at the start of the last char, wrap
            else
              break
            end
          end
        end
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
      local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ''
      local sn = new_col + 1
      local b = string.byte(line, sn)
      -- Snap backward to the start of the current char. Then,
      -- if we're inside a multi-codepoint grapheme token (e.g.
      -- ⚠️ = U+26A0 U+FE0F), snap further to the start of the
      -- token. This handles the case where nvim clamps the
      -- cursor back to the start of the grapheme.
      while b and b >= 0x80 and b < 0xC0 do
        sn = sn - 1
        b = string.byte(line, sn)
      end
      -- Check if the snapped position is inside a grapheme token
      -- (a token that contains U+FE0F variation selector).
      local toks = _cut(line)
      for _, t in ipairs(toks) do
        if t.byte_start <= sn and sn <= t.byte_end + 1 and t.text:find('\239\184\143') then
          -- Snap to the start of the grapheme token
          sn = t.byte_start
          break
        end
      end
      new_col = sn - 1
      if new_col <= col0 then
        local toks = _cut(line)
        if is_end_fwd then
          for _, t in ipairs(toks) do
            if t.byte_start > col0 + 1 and not is_whitespace(t) then
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
    -- nvim clamps the cursor for multi-codepoint graphemes (e.g.
    -- ⚠️ = U+26A0 U+FE0F) back to the start of the grapheme.
    -- The clamp doesn't happen immediately -- it happens during
    -- a subsequent screen update. We can force a redraw and
    -- check the result.
    if is_end_fwd then
      vim.cmd('redraw')
      local actual = vim.api.nvim_win_get_cursor(win)[2]
      if actual < new_col then
        local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ''
        local toks = _cut(line)
        for _, t in ipairs(toks) do
          if t.byte_start > actual + 1 and not is_whitespace(t) then
            sn = t.byte_end
            b = string.byte(line, sn)
            while b and b >= 0x80 and b < 0xC0 do
              sn = sn - 1
              b = string.byte(line, sn)
            end
            vim.api.nvim_win_set_cursor(win, { r, sn - 1 })
            break
          end
        end
      end
    end
  end
end

M.move_forward = cursor_move(M.motion.forward, 'forward')
M.move_backward = cursor_move(M.motion.backward, 'backward')
M.move_end_forward = cursor_move(M.motion.end_forward, 'end_forward')
M.move_end_backward = cursor_move(M.motion.end_backward, 'end_backward')

-- Operator-pending motion handlers.
--
-- The handler is split in two pieces:
--   * a thin `op_motion` wrapper that runs while nvim is still in
--     operator-pending mode (so it can read `vim.v.operator`),
--   * `_run_op` that does the actual work.
--
-- The wrapper returns a `<Cmd>lua require('cword')._run_op(dir, op)<CR>`
-- string; nvim aborts the pending operator and runs the Lua code.
-- For dot-repeat the literal string is replayed, so `_run_op` runs
-- again with the new cursor and recomputes everything dynamically.
-- This is what fixes the stale-position bug: the old implementation
-- baked the visual start/end columns into the returned string and so
-- re-ran the delete on the wrong range on `.`.
--
-- The Lua snippet builds a visual selection (`virtualedit=onemore` so
-- the cursor may sit one cell past the last byte of a line — this is
-- what makes CJK end-of-line motion work) and then applies the
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
    local op = vim.v.operator
    if not op or op == '' then
      return '<Esc>'
    end
    return string.format('<Cmd>lua require("cword")._run_op(%q, %q)<CR>', direction, op)
  end
end

-- Run the operator-pending motion for `direction` and apply `op`
-- (`'d'` / `'c'` / `'y'`). Called from the `<Cmd>lua ...<CR>` snippet
-- returned by `op_motion`; `op` is passed as an argument so this
-- function works the same way on the first call and on dot-repeat
-- (where `vim.v.operator` is no longer set).
local function run_op(direction, op)
  local count = math.max(1, vim.v.count1)
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  -- Select the motion method once: same as the original op_motion body.
  local method = ({
    forward = M.motion.forward,
    backward = M.motion.backward,
    end_forward = M.motion.end_forward,
    end_backward = M.motion.end_backward,
  })[direction]
  assert(method, 'unknown direction: ' .. tostring(direction))
  -- For `c` with `w` (forward) motion, nvim treats it as `ce`:
  -- delete the current word including its last char, but not
  -- trailing whitespace. Use end_forward so the visual range
  -- covers the current word only.
  local effective_method = method
  local effective_direction = direction
  if op == 'c' and direction == 'forward' then
    effective_method = M.motion.end_forward
    effective_direction = 'end_forward'
  end
  local r, c = row, col0 + 1
  local orig_line = vim.api.nvim_get_current_line()
  local orig_line_len = #orig_line
  for _ = 1, count do
    local line = vim.api.nvim_get_current_line()
    c = effective_method(_cut, line, c)
    -- Forward: when there is no next word on the current line,
    -- only wrap to the next line when the count loop hasn't
    -- finished (i.e. more motions are pending). The final
    -- iteration that runs out of content stays at #line + 1
    -- (past the last character) without crossing the newline,
    -- matching stock Vim's operator-pending w semantics.
    if direction == 'forward' and c > #line then
      -- For empty lines, nvim's `dw` wraps to the next line even on
      -- the final iteration, so `dw` deletes the empty line. But
      -- `cw` does NOT delete the line (it just changes "nothing"
      -- to "nothing"). So only wrap for empty lines when the
      -- operator is `d` (not `c`).
      local is_empty = #line == 0
      local is_delete = op == 'd'
      if _ < count or (is_empty and is_delete) then
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
    elseif direction == 'end_backward' and c <= 1 then
      -- Stock nvim's ge from the end of the first word (or
      -- from BOL) wraps to the previous line (even if empty).
      -- For non-empty lines, target the start of the last
      -- character. For empty lines, target col 0.
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
        else
          r, c, found = nr, 0, true
        end
        break
      end
      if not found then
        break
      end
    elseif effective_direction == 'end_forward' and c >= #line then
      -- If the cursor was at the end of a single-byte word (e.g.
      -- 'a' in 'a b'), end_forward jumps to the end of the NEXT
      -- word. Don't wrap to the next line in this case; stop at
      -- end of current line so de doesn't eat the next line.
      local cur_tok_at_cursor
      for _, t in ipairs(_cut(line)) do
        if t.byte_start - 1 <= col0 and col0 <= t.byte_end - 1 and not is_whitespace(t) then
          cur_tok_at_cursor = t
          break
        end
      end
      if
        cur_tok_at_cursor
        and cur_tok_at_cursor.byte_start == cur_tok_at_cursor.byte_end
        and col0 + 1 == cur_tok_at_cursor.byte_end
      then
        c = #line
        break
      end
      -- TODO: count > 1 wraps on every iteration; the forward
      -- (w) wrap guards with `_ < count` so the final iteration
      -- stays at EOL.  Match that here for d2e/d3e parity.
      -- If the motion already advanced c to the end of a word
      -- on the same line, do not wrap. This happens when:
      --   1. the cursor was on a whitespace token and the
      --      motion found the next word, or
      --   2. the cursor was inside a word (including at its
      --      first byte) and the motion returned byte_end.
      -- Exception: if the cursor is at the start of the last
      -- character of the line, do wrap (matching the normal
      -- 'e' motion at the last char).
      if c < #line + 1 then
        local on_ws = false
        local inside_word = false
        for _, t in ipairs(_cut(line)) do
          if t.byte_start - 1 <= col0 and col0 <= t.byte_end - 1 then
            if is_whitespace(t) then
              on_ws = true
            elseif t.is_word_like and t.byte_end == c then
              inside_word = true
            end
          end
        end
        if on_ws then
          c = #line
          break
        end
        if inside_word then
          local last_char_start = #line
          while last_char_start > 1 do
            local b = string.byte(line, last_char_start)
            if b and (b < 0x80 or b >= 0xC0) then
              break
            end
            last_char_start = last_char_start - 1
          end
          if col0 + 1 ~= last_char_start then
            c = #line
            break
          end
        end
      end
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local found = false
      local last_empty = nil
      for nr = r + 1, #lines do
        local s = lines[nr]
        if not s then
          break
        end
        if #s == 0 then
          -- Track empty lines for joining
          last_empty = nr
        else
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
      end
      if not found and last_empty then
        -- No non-whitespace token found, but there are empty
        -- lines. Wrap to the last empty line to join them.
        r, c, found = last_empty, 0, true
      end
      if not found then
        break
      end
    end
  end
  if r == row and c - 1 == col0 then
    -- Motion didn't advance. For `d` (delete), abort. For `c`
    -- (change), still enter insert mode (changing "nothing" to
    -- "nothing" is valid, e.g. `cw` on an empty line).
    if op ~= 'c' then
      return
    end
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
    -- For end_backward, if col0 lands in the middle of a
    -- multi-byte character, snap it forward to the end of that
    -- character so the visual endpoint covers the full char
    -- width (capped at line end - 1 to avoid including the
    -- trailing newline). Only snap when the cursor is actually
    -- inside a char (byte at col0+1 is a continuation byte).
    if direction == 'end_backward' and col0 > 0 and col0 < orig_line_len then
      local b = string.byte(orig_line, col0 + 1)
      if b and b >= 0x80 and b < 0xC0 then
        local sn = col0 + 2
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
      if effective_direction == 'end_forward' then
        -- Cross-line end_forward: c is byte_end (1-indexed).
        -- Use c - 1 as 0-indexed visual endpoint to land on the
        -- last byte of the target word (consistent with
        -- non-cross-line end_forward).
        -- Special case: if c = 0 (empty line), use 0 directly.
        e_row, e_col = r - 1, (c == 0) and 0 or math.max(0, c - 1)
      else
        -- Cross-line forward: the visual end is on the target
        -- line at c - 2 (exclusive of the next word's first
        -- byte).  This matches stock Vim's exclusive motion
        -- boundary: d deletes from cursor to just before the
        -- motion target.
        e_row, e_col = r - 1, math.max(0, c - 2)
      end
    elseif direction == 'end_backward' and r < row then
      -- Cross-line end_backward: visual from the cursor
      -- (s_row, s_col are already set to row-1, col0 above)
      -- to the motion target on the previous line. With
      -- virtualedit=onemore the cursor at e_col+1 includes
      -- the target char, so the delete covers from the cursor
      -- through the end of the target word, plus the newline.
      -- This matches stock nvim's dge cross-line behaviour.
      e_row, e_col = r - 1, c
    elseif effective_direction == 'end_forward' then
      -- end_forward returns byte_end (1-indexed, inclusive).
      -- Convert to 0-indexed column by subtracting 1.
      local target_col = math.max(0, c - 1)
      -- For `cw`/`ce` when the cursor is on leading whitespace, the
      -- motion normally jumps to the end of the next word. But the
      -- user wants `cw` to consume the leading whitespace (e.g.
      -- '   abc' -> 'abc'). Find the end of the leading whitespace
      -- and use that instead.
      if direction == 'forward' and op == 'c' and col0 < #orig_line then
        if string.byte(orig_line, col0 + 1) == 0x20 then
          local ws_end = col0
          while ws_end < #orig_line and string.byte(orig_line, ws_end + 1) == 0x20 do
            ws_end = ws_end + 1
          end
          if ws_end > col0 then
            target_col = ws_end - 1
          end
        end
      end
      e_row, e_col = r - 1, target_col
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
  -- Special case: change operator with empty visual range. Just
  -- enter insert mode without deleting anything (matching
  -- nvim's `cw` on an empty line or `ce` when cursor is already
  -- at the end of a word).
  if op == 'c' and s_row == e_row and s_col == e_col then
    vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
    vim.schedule(function()
      vim.cmd('startinsert')
    end)
    return
  end
  -- Special case: `dw` on an empty line. nvim --clean deletes the
  -- empty line (joining with the next line). The visual mode
  -- approach doesn't work well for empty lines because the
  -- cursor at col 0 of the next line gets clamped. Use `:delete _`
  -- via normal! mode to delete the line.
  if direction == 'forward' and #orig_line == 0 and op == 'd' then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines > 1 then
      vim.fn.setreg('-', '\n')
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, {})
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      return
    end
  end

  if op ~= 'd' and op ~= 'c' and op ~= 'y' then
    return
  end
  local cache_ve = vim.o.virtualedit
  -- For same-line operations, don't use virtualedit. The cursor
  -- at (row, col) is on the byte at that col. The visual range
  -- is from anchor to cursor, inclusive. With virtualedit=onemore,
  -- the cursor at col would be past the byte, including one
  -- extra char. Use e_col directly (without +1) for same-line.
  if s_row ~= e_row then
    vim.o.virtualedit = 'onemore'
  end
  vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { e_row + 1, e_col })
  -- The visual selection has to stabilize (via a screen update) before
  -- `normal! <op>` can operate on it correctly. The old implementation
  -- split this into two `<Cmd>lua ...<CR>` blocks for the same reason.
  -- vim.schedule defers the delete to the next event-loop tick.
  vim.schedule(function()
    vim.cmd('normal! ' .. op)
    vim.o.virtualedit = cache_ve
  end)
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
    -- Special case: change operator with empty visual range. Just
    -- enter insert mode without deleting anything (matching
    -- nvim's `cw` on an empty line or `ce` when cursor is already
    -- at the end of a word).
    if op == 'c' and s_row == e_row and s_col == e_col then
      local cache_ve = vim.o.virtualedit
      return string.format(
        '<Cmd>lua vim.api.nvim_win_set_cursor(0, {%d, %d})<CR>i'
          .. '<Cmd>lua vim.o.virtualedit=%q<CR>',
        s_row + 1,
        s_col,
        cache_ve
      )
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
-- Exposed so the `<Cmd>lua ...<CR>` snippet returned by op_motion can
-- dispatch into the same body without baking positions into the string.
-- This is what makes dot-repeat recompute the visual range against the
-- current cursor instead of replaying stale coordinates.
M._run_op = run_op

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

  -- Find the word before the cursor and delete it.
  -- col0 is 0-indexed, byte positions are 1-indexed.
  -- Stock nvim behavior: delete the word before cursor plus any
  -- trailing whitespace between the word and cursor.
  -- Stock nvim treats consecutive non-whitespace characters as a single word.
  local tokens = _cut(line)
  local word_start = nil
  local delete_end = col0

  -- First, skip any trailing whitespace before the cursor
  local word_end_idx = nil
  for i = #tokens, 1, -1 do
    local t = tokens[i]
    local t_end_0 = t.byte_end - 1

    if t_end_0 < col0 then
      -- This token is before the cursor
      if is_whitespace(t) then
        -- Skip whitespace, continue looking for word
      else
        -- Found a non-whitespace token, this is the end of the word
        word_end_idx = i
        word_start = t.byte_start - 1
        break
      end
    elseif t.byte_start - 1 < col0 and t_end_0 >= col0 then
      -- Cursor is inside this token
      if not is_whitespace(t) then
        -- This is the end of the word
        word_end_idx = i
        word_start = t.byte_start - 1
        break
      end
    end
  end

  if word_start == nil then
    -- No word found before the cursor. If the cursor is at the
    -- start of a word (e.g. '  hello|' where cursor is at start
    -- of 'hello'), or if the cursor is in whitespace before the
    -- first word, delete the leading whitespace up to the cursor.
    for _, t in ipairs(_cut(line)) do
      if t.byte_start - 1 == col0 and not is_whitespace(t) then
        word_start = 0
        break
      end
    end
    if word_start == nil and col0 > 0 then
      -- Cursor is in leading whitespace before any word. Delete
      -- the whitespace up to the cursor.
      for _, t in ipairs(_cut(line)) do
        if not is_whitespace(t) and t.byte_start - 1 > 0 then
          word_start = 0
          break
        end
      end
    end
    if word_start == nil and col0 >= #line then
      -- Cursor is at or past the end of a whitespace-only line.
      -- Delete the entire line content.
      local all_ws = true
      for _, t in ipairs(_cut(line)) do
        if not is_whitespace(t) then
          all_ws = false
          break
        end
      end
      if all_ws then
        word_start = 0
      end
    end
    if word_start == nil then
      return
    end
  end

  -- Set word_end_idx if not already set (leading whitespace case).
  if word_end_idx == nil then
    word_end_idx = 1
  end

  -- Now, merge consecutive ASCII word-like tokens backwards.
  -- Stop at whitespace, at non-word-like tokens (e.g. '-' when it
  -- is not in iskeyword), and at CJK boundaries. This matches
  -- stock nvim's <C-w> which treats each cjdict segment and each
  -- ASCII run as a separate word.
  for i = word_end_idx - 1, 1, -1 do
    local t = tokens[i]
    if is_whitespace(t) then
      break
    elseif not t.is_word_like then
      break
    else
      local has_cjk = false
      for j = t.byte_start, t.byte_end do
        if line:byte(j) >= 0x80 then
          has_cjk = true
          break
        end
      end
      if has_cjk then
        break
      end
      word_start = t.byte_start - 1
    end
  end

  -- Delete from word_start to col0 (including any whitespace between the word and cursor)
  local row1 = row - 1
  -- Yank into the small-delete register now, then schedule
  -- the buffer mutation with an undo breakpoint.
  vim.fn.setreg(
    '-',
    (vim.api.nvim_buf_get_text(0, row1, word_start, row1, delete_end, {})[1] or '')
  )
  vim.o.undolevels = vim.o.undolevels
  vim.api.nvim_buf_set_text(0, row1, word_start, row1, delete_end, { '' })
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

  -- pos is 1-indexed and points to the cursor position.
  -- We want to delete the word before the cursor.
  local tokens = _cut(line)
  local target = pos - 1 -- 0-indexed position to delete from

  -- Find the word before the cursor
  for i = #tokens, 1, -1 do
    local t = tokens[i]
    if t.byte_end < pos then
      -- Token is before cursor
      if is_whitespace(t) then
        -- Skip whitespace
        target = t.byte_start - 1
      else
        -- Found a word, delete from its start
        target = t.byte_start - 1
        break
      end
    elseif t.byte_start < pos and t.byte_end >= pos then
      -- Cursor is inside this token
      if not is_whitespace(t) then
        -- Delete from start of this word to cursor
        target = t.byte_start - 1
        break
      end
    end
  end

  if target >= pos - 1 then
    return
  end

  -- target is 0-indexed, pos is 1-indexed.
  -- Delete from target+1 to pos-1 (inclusive) in 1-indexed terms.
  vim.fn.setcmdline(line:sub(1, target) .. line:sub(pos), target + 1)
end

-- Exposed for spec probing.

return M
