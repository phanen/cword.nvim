local M = {}

M.Segmenter = require('cword.segmenter')
M.motion = require('cword.motion')

local text = require('cword.util.text')
local is_whitespace = text.is_whitespace
local char_start = text.char_start
local char_end = text.char_end
local is_multi_codepoint_grapheme = text.is_multi_codepoint_grapheme
local has_vs16 = text.has_vs16
local whitespace_between = text.whitespace_between
local next_non_whitespace_end = text.next_non_whitespace_end

local _cut = M.Segmenter.cut

---@param toks table[]
---@param line string
---@param col_0 integer 0-indexed cursor byte
---@param dir 'fwd'|'bwd'
---@return integer?
local function _next_word_col(toks, line, col_0, dir)
  if dir == 'fwd' then
    for _, t in ipairs(toks) do
      if t.byte_start > col_0 + 1 and not is_whitespace(t) then
        return char_start(line, t.byte_end) - 1
      end
    end
  else
    for i = #toks, 1, -1 do
      local t = toks[i]
      if t.byte_end < col_0 + 1 and not is_whitespace(t) then
        return char_start(line, t.byte_end) - 1
      end
    end
  end
end

-- Mirrors nvim's `Insstart_orig`: tracks the leftmost cursor column
-- of the current insert session so `<c-w>` doesn't cross pre-insert
-- text. Per-buffer so multiple buffers don't share state.
vim.api.nvim_create_autocmd('InsertEnter', {
  callback = function()
    vim.b.cword_ins_start = vim.api.nvim_win_get_cursor(0)[2]
  end,
})
-- TextChangedI doesn't fire on pure cursor motion (arrows, <Left>),
-- matching stock nvim's Insstart_orig behavior.
vim.api.nvim_create_autocmd('TextChangedI', {
  callback = function()
    local pos = vim.api.nvim_win_get_cursor(0)
    if vim.b.cword_ins_start and pos[2] < vim.b.cword_ins_start then
      vim.b.cword_ins_start = pos[2]
    end
  end,
})

function M.setup() end

-- nvim clamps any cursor inside a multi-codepoint grapheme cluster
-- to the cluster edges. The edge we choose:
--   * U+FE0F in token (⚠️, ZWJ ending in a VS-joined char): byte_start,
--     matching stock vim. A subsequent 'e' advances via the
--     snap-forward fallback below.
--   * No U+FE0F (flags, skin-tone): skip past the cluster to the next
--     word's end when whitespace separates cursor and cluster, so
--     the cursor doesn't look stuck on byte_start.
---@param line string
---@param col0 integer 0-indexed entry column
---@param new_col integer 0-indexed post-motion column
---@param is_end_fwd boolean
---@return integer 0-indexed column
local function snap_end_motion_col(line, col0, new_col, is_end_fwd)
  local sn = char_start(line, new_col + 1)
  local toks = _cut(line)
  local grapheme_tok
  for _, t in ipairs(toks) do
    if t.byte_start <= sn and sn <= t.byte_end + 1 and is_multi_codepoint_grapheme(t.text) then
      grapheme_tok = t
      break
    end
  end
  if grapheme_tok then
    local target = grapheme_tok.byte_start
    if
      is_end_fwd
      and not has_vs16(grapheme_tok.text)
      and col0 + 1 < grapheme_tok.byte_start
      and whitespace_between(toks, col0 + 1, grapheme_tok.byte_start)
    then
      local nxt = next_non_whitespace_end(toks, grapheme_tok.byte_end)
      if nxt then
        target = nxt
      end
    end
    sn = target
  end
  new_col = sn - 1
  if new_col <= col0 then
    new_col = _next_word_col(toks, line, col0, is_end_fwd and 'fwd' or 'bwd') or new_col
  end
  return new_col
end

-- Wrap-scan helpers shared by cursor_move, run_op, insert_move.
-- Each returns (line_nr, byte_start, byte_end) of the first/last
-- non-whitespace token across adjacent lines, or (line_nr, 1, 0)
-- for the last empty line seen. nil means no line at all in the
-- requested direction.

---@param lines string[]
---@param start_r integer
---@return integer?, integer?, integer?
local function _find_wrap_forward(lines, start_r)
  local last_empty
  for nr = start_r, #lines do
    local s = lines[nr]
    if not s then
      break
    end
    if #s == 0 then
      last_empty = nr
    else
      for _, t in ipairs(_cut(s)) do
        if not is_whitespace(t) then
          return nr, t.byte_start, t.byte_end
        end
      end
    end
  end
  if last_empty then
    return last_empty, 1, 0
  end
end

---@param lines string[]
---@param start_r integer
---@return integer?, integer?, integer?
local function _find_wrap_backward(lines, start_r)
  local last_empty
  local found_nr, found_bs, found_be
  for nr = start_r, 1, -1 do
    local s = lines[nr]
    if not s then
      break
    end
    if #s == 0 then
      last_empty = nr
    else
      for _, t in ipairs(_cut(s)) do
        if not is_whitespace(t) then
          last_empty = nil
          found_nr = nr
          found_bs = t.byte_start
          found_be = t.byte_end
        end
      end
    end
  end
  if last_empty then
    return last_empty, 1, 0
  end
  if found_nr then
    return found_nr, found_bs, found_be
  end
end

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
        local nr, bs = _find_wrap_forward(lines, r + 1)
        if nr then
          r, c = nr, bs
          found = true
        else
          break
        end
      elseif is_bwd and c <= 1 and col0 == 0 then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local nr, _, be = _find_wrap_backward(lines, r - 1)
        if nr then
          r, c = nr, be
          found = true
        else
          break
        end
      elseif is_end_fwd and c >= #line then
        if col0 == 0 then
          c = #line
          break
        end
        -- 'e' from the start of the last char wraps, but from any
        -- other position it stops on the current line.
        if c < #line + 1 then
          local on_ws = false
          local inside_word = false
          local motion_found_next = false
          for _, t in ipairs(_cut(line)) do
            if t.byte_start - 1 <= col0 and col0 <= t.byte_end - 1 then
              if is_whitespace(t) then
                on_ws = true
              elseif not is_whitespace(t) and t.byte_end == c then
                inside_word = true
              end
            end
            if not is_whitespace(t) and t.byte_end == c and t.byte_start - 1 > col0 then
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
            if col0 + 1 == char_start(line, #line) then
              -- cursor on last char's start byte → wrap
            else
              break
            end
          end
        end
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local nr, _, be = _find_wrap_forward(lines, r + 1)
        if nr then
          r, c = nr, be
        else
          break
        end
      elseif is_end_bwd and c <= 1 and col0 == 0 then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local nr, _, be = _find_wrap_backward(lines, r - 1)
        if nr then
          r, c = nr, be
        else
          break
        end
      end
    end

    local new_col = math.max(0, c - 1)
    if is_end_fwd or is_end_bwd then
      local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ''
      new_col = snap_end_motion_col(line, col0, new_col, is_end_fwd)
    end
    vim.api.nvim_win_set_cursor(win, { r, new_col })
    -- nvim's grapheme clamp runs on the next redraw, not
    -- synchronously with nvim_win_set_cursor. Re-read and advance
    -- if it stuck.
    if is_end_fwd then
      vim.cmd('redraw')
      local actual = vim.api.nvim_win_get_cursor(win)[2]
      if actual < new_col then
        local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ''
        local toks = _cut(line)
        for _, t in ipairs(toks) do
          if t.byte_start > actual + 1 and not is_whitespace(t) then
            vim.api.nvim_win_set_cursor(win, { r, char_start(line, t.byte_end) - 1 })
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
-- Split into two pieces so dot-repeat works correctly:
--   * op_motion runs while nvim is still in operator-pending mode
--     (where vim.v.operator is readable) and returns a
--     `<Cmd>lua require("cword")._run_op(dir, op)<CR>` string.
--     nvim aborts the pending operator and runs the Lua code.
--   * run_op does the actual work and is also re-invoked by the
--     same literal string on `.` (where vim.v.operator is no
--     longer set, so op is passed as an argument).
--
-- The Lua snippet builds a visual selection under
-- virtualedit=onemore (so the cursor can sit one cell past the
-- last byte of a line — required for CJK end-of-line motion) and
-- then applies the operator. Pattern from mini.ai's select_textobject.
--
-- Cross-line wrap is the tricky case: with virtualedit=onemore the
-- cursor at (line, 0) is "on the first char" of that line, so a
-- visual range from (line1, 0) to (line2, 0) eats the first char
-- of line2 ("hello\nworld" becomes "orld" after `dw`). The fix is
-- to anchor the visual end on the *previous* line at its byte
-- length: that's past the last char of line1 (allowed by onemore)
-- and the range then includes the trailing newline without
-- grabbing line2.
local function op_motion(method, direction)
  return function()
    local op = vim.v.operator
    if not op or op == '' then
      return '<Esc>'
    end
    return string.format('<Cmd>lua require("cword")._run_op(%q, %q)<CR>', direction, op)
  end
end

-- Wrap the motion target to the next non-empty line's first word
-- end, or to the last empty line's col 0 if only empty lines follow.
---@param cut fun(line: string): table[]
---@param r integer 1-indexed line
---@param c integer 1-indexed byte (byte_end of the target word)
---@return integer?, integer?
local function _wrap_op_forward(cut, r, c)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local nr, _, be = _find_wrap_forward(lines, r + 1)
  if nr then
    return nr, be
  end
end

-- True when nvim has clamped the cursor to the start byte of the
-- last char of `line` (it does this when the cursor was originally
-- on the end of the last word).
---@param line string
---@param col0 integer
---@return boolean
local function _cursor_at_last_char_start(line, col0)
  if #line == 0 then
    return col0 == 0
  end
  return col0 + 1 == char_start(line, #line)
end

local function run_op(direction, op)
  local count = math.max(1, vim.v.count1)
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  local method = ({
    forward = M.motion.forward,
    backward = M.motion.backward,
    end_forward = M.motion.end_forward,
    end_backward = M.motion.end_backward,
  })[direction]
  assert(method, 'unknown direction: ' .. tostring(direction))
  -- `c` with `w` (forward) is `ce`: delete the current word
  -- including its last char, but not trailing whitespace. Use
  -- end_forward so the visual range covers the current word only.
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
    -- Forward wrap only fires while more motions are pending; the
    -- final iteration that runs out of content stays at #line + 1
    -- (past the last character) without crossing the newline,
    -- matching stock Vim's operator-pending w semantics.
    if direction == 'forward' and c > #line then
      -- nvim's `dw` wraps past empty lines (joining them) but
      -- `cw` doesn't (it would be "change nothing to nothing").
      local is_empty = #line == 0
      local is_delete = op == 'd'
      if _ < count or (is_empty and is_delete) then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local nr, bs = _find_wrap_forward(lines, r + 1)
        if nr then
          r, c = nr, bs
        else
          if is_empty and is_delete then
            -- Special case for `dw` on an empty line: advance to
            -- the next line and clear `c` so the visual range
            -- spans the empty line(s). The actual deletion happens
            -- in the dw-on-empty-line block below.
            r = r + 1
            c = 0
            if r > #lines then
              -- dw on the very last line is a stock no-op.
              return
            end
          else
            c = #line + 1
            break
          end
        end
      else
        c = #line + 1
        break
      end
    elseif direction == 'backward' and c <= 1 and col0 == 0 then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local nr, bs = _find_wrap_backward(lines, r - 1)
      if nr then
        r, c = nr, bs
      else
        break
      end
    elseif direction == 'end_backward' and c <= 1 then
      -- Stock nvim's `ge` from the end of the first word (or from
      -- BOL) wraps to the previous line, even if empty. Non-empty
      -- lines land on the start of the last char; empty lines on
      -- col 0.
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local found = false
      for nr = r - 1, 1, -1 do
        local s = lines[nr]
        if not s then
          break
        end
        if #s > 0 then
          -- Target the lead byte of the last char so the visual
          -- endpoint is always on a char boundary.
          r, c, found = nr, char_start(s, #s) - 1, true
        else
          r, c, found = nr, 0, true
        end
        break
      end
      if not found then
        break
      end
    elseif effective_direction == 'end_forward' and c > #line then
      local new_r, new_c = _wrap_op_forward(_cut, r, c)
      if not new_r then
        break
      end
      r, c = new_r, new_c
    elseif
      effective_direction == 'end_forward'
      and c == #line
      and #line > 0
      and _cursor_at_last_char_start(line, col0)
    then
      -- nvim clamps the cursor to the last char's start byte
      -- whenever it was originally on the end of the last word;
      -- wrap here to match stock `de`/`ce` join behavior.
      local new_r, new_c = _wrap_op_forward(_cut, r, c)
      if not new_r then
        break
      end
      r, c = new_r, new_c
    end
  end
  if r == row and c - 1 == col0 then
    -- Motion didn't advance. `d` aborts; `c` still enters insert
    -- mode (changing "nothing" to "nothing" is valid, e.g. `cw`
    -- on an empty line).
    if op ~= 'c' then
      return
    end
  end
  local s_row, s_col
  local e_row, e_col
  if direction == 'backward' then
    s_row, s_col = r - 1, c - 1
    -- Cross-line backward: anchor the visual end on the previous
    -- line at its byte length so the range stops at the trailing
    -- newline without grabbing the first char of the cursor's line.
    if r < row then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      e_row, e_col = r - 1, #(lines[r] or '')
    else
      e_row, e_col = row - 1, math.max(0, col0 - 1)
    end
  else
    -- For end_backward, if col0 lands mid-multi-byte-char, snap
    -- forward to the next char boundary so the visual start
    -- covers the full char width (capped at line end - 1 to
    -- avoid including the trailing newline).
    if direction == 'end_backward' and col0 > 0 and col0 < orig_line_len then
      local b = string.byte(orig_line, col0 + 1)
      if b and b >= 0x80 and b < 0xC0 then
        col0 = math.min(char_end(orig_line, col0 + 2, orig_line_len) - 1, orig_line_len - 1)
      end
    end
    s_row, s_col = row - 1, col0
    if r > row then
      if effective_direction == 'end_forward' then
        -- Cross-line end_forward: c is byte_end (1-indexed);
        -- c - 1 is the 0-indexed visual endpoint on the last byte
        -- of the target word. c = 0 means empty line.
        e_row, e_col = r - 1, (c == 0) and 0 or math.max(0, c - 1)
      else
        -- Cross-line forward: visual end is c - 2 (exclusive of
        -- the next word's first byte) — stock Vim's exclusive
        -- motion boundary.
        e_row, e_col = r - 1, math.max(0, c - 2)
      end
    elseif direction == 'end_backward' and r < row then
      -- Cross-line end_backward: with virtualedit=onemore, cursor
      -- at e_col+1 includes the target char, so the delete covers
      -- from cursor through the end of the target word plus the
      -- newline — stock nvim's dge cross-line behaviour.
      e_row, e_col = r - 1, c
    elseif effective_direction == 'end_forward' then
      local target_col = math.max(0, c - 1)
      -- `cw`/`ce` on leading whitespace should consume the ws
      -- (e.g. '   abc' -> 'abc') instead of jumping to the end
      -- of the next word.
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
      local target_col = math.max(0, c - 1)
      -- Snap to char boundary to avoid splitting multi-byte chars.
      if target_col > 0 and target_col < orig_line_len then
        local b = string.byte(orig_line, target_col + 1)
        if b and b >= 0x80 and b < 0xC0 then
          target_col = char_start(orig_line, target_col + 1) - 1
        end
      end
      e_row, e_col = r - 1, target_col
    else
      e_row, e_col = r - 1, math.max(0, c - 2)
    end
  end
  if s_row > e_row or (s_row == e_row and s_col > e_col) then
    s_row, s_col, e_row, e_col = e_row, e_col, s_row, s_col
  end
  -- Empty visual range under `c`: just enter insert mode
  -- (matching nvim's `cw` on an empty line or `ce` at a word's end).
  if op == 'c' and s_row == e_row and s_col == e_col then
    vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
    vim.schedule(function()
      vim.cmd('startinsert')
    end)
    return
  end
  -- `dw` on an empty line: nvim --clean joins with the next line.
  -- Visual mode doesn't work here because the cursor at col 0 of
  -- the next line gets clamped; use :delete _ via normal! instead.
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
  -- Same-line ops use e_col directly (cursor at (row, col) is on
  -- the byte). Cross-line ops need virtualedit=onemore so the
  -- cursor can sit one cell past the last byte of a line.
  if s_row ~= e_row then
    vim.o.virtualedit = 'onemore'
  end
  vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { e_row + 1, e_col })
  -- vim.schedule defers to the next tick so the visual selection
  -- stabilises before `normal! <op>` operates on it.
  vim.schedule(function()
    vim.cmd('normal! ' .. op)
    if op == 'c' then
      -- Place the cursor at the start of the deleted range; newly
      -- typed text is inserted there.
      vim.api.nvim_win_set_cursor(0, { s_row + 1, s_col })
    end
    vim.o.virtualedit = cache_ve
  end)
end

-- Textobject handlers for `iw` (inner word) and `aw` (a word).
-- Same pattern as op_motion: return a `<Cmd>lua ...<CR>` snippet
-- that builds a visual selection under virtualedit=onemore and
-- runs the pending operator. In visual mode the same Lua code
-- runs synchronously and the operator branch is skipped.

-- Returns nil when the cursor is on whitespace or past the last
-- token, so callers can bail rather than mis-selecting the
-- previous word.
---@param line string
---@param col_1 integer 1-indexed byte column (1-based; `#line + 1` is valid EOL)
---@param ai_type 'i'|'a'
---@return integer|nil start_c 1-indexed byte_start (inclusive)
---@return integer|nil end_c 1-indexed byte_end (exclusive)
local function find_text_object(line, col_1, ai_type)
  if #line == 0 then
    return nil
  end
  if col_1 < 1 then
    return nil
  end
  if col_1 > #line + 1 then
    return nil
  end
  -- nvim reports mouse column at `#line + 1` when the cursor sits
  -- exactly at the end of a line in insert mode; treat that as
  -- "on the last token".
  if col_1 == #line + 1 then
    col_1 = #line
  end

  local toks = _cut(line)
  local word_tok = nil
  for _, t in ipairs(toks) do
    if t.byte_start <= col_1 and t.byte_end >= col_1 then
      if not is_whitespace(t) then
        word_tok = t
      end
      break
    end
  end
  if not word_tok then
    return nil
  end

  local start_c = word_tok.byte_start
  local end_c = word_tok.byte_end + 1

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

  return start_c, end_c
end

local function textobject(ai_type)
  return function()
    local op = vim.v.operator
    local in_visual = (vim.api.nvim_get_mode().mode:sub(1, 1) == 'v')

    local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    if #line == 0 then
      return in_visual and '' or '<Esc>'
    end
    local start_c, end_c = find_text_object(line, col0 + 1, ai_type)
    if not start_c then
      return in_visual and '' or '<Esc>'
    end

    -- nvim's live visual mode uses "between chars" semantics: cursor
    -- at 0-indexed col C selects bytes [anchor, C]. So the end col
    -- for 'hello' (bytes 1-5) is col 4 (= end_c - 2), not col 5;
    -- end_c - 1 would eat the byte right after the word.
    local s_row = row - 1
    local s_col_0 = start_c - 1
    local e_row = row - 1
    local e_col_0 = end_c - 2

    if in_visual then
      -- `viw`/`vaw` rebuild the selection via setpos('<, `>) + gv.
      -- `find_text_object` returns end_c as an exclusive end (= 1
      -- past the last byte of the word); snap back to the lead byte
      -- of the previous char before setpos. Without this snap Vim
      -- keeps end_c when it lands on a valid next-char boundary
      -- (the CJK case) and `gv` extends the visual area one char
      -- too far.
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes('<Esc>', true, false, true),
        'mtx',
        false
      )
      vim.fn.setpos("'<", { 0, s_row + 1, start_c, 0 })
      vim.fn.setpos("'>", { 0, e_row + 1, char_start(line, end_c - 1), 0 })
      vim.cmd('normal! gv')
      return ''
    end

    if op ~= 'd' and op ~= 'c' and op ~= 'y' then
      return '<Esc>'
    end
    -- Empty visual range under `c`: just enter insert mode
    -- (matching nvim's `cw` on an empty line or `ce` at a word's end).
    if op == 'c' and s_row == e_row and s_col_0 == e_col_0 then
      local cache_ve = vim.o.virtualedit
      return string.format(
        '<Cmd>lua vim.api.nvim_win_set_cursor(0, {%d, %d})<CR>i'
          .. '<Cmd>lua vim.o.virtualedit=%q<CR>',
        s_row + 1,
        s_col_0,
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
      s_col_0,
      e_row + 1,
      e_col_0,
      op,
      cache_ve
    )
  end
end

M.op_forward = op_motion(M.motion.forward, 'forward')
M.op_backward = op_motion(M.motion.backward, 'backward')
M.op_end_forward = op_motion(M.motion.end_forward, 'end_forward')
M.op_end_backward = op_motion(M.motion.end_backward, 'end_backward')
-- Exposed so the `<Cmd>lua ...<CR>` snippet can dispatch into the
-- same body without baking positions into the string — what makes
-- dot-repeat recompute the visual range against the current cursor
-- instead of replaying stale coordinates.
M._run_op = run_op

-- Bind in 'x' (visual) and 'o' (operator-pending). In 'o' mode,
-- `expr = true` is required.
M.textobject_inner_word = textobject('i')
M.textobject_a_word = textobject('a')

-- CJK-aware text-object lookup. Returns nil on whitespace / past
-- last token (same bail-on-fail behaviour as the operator-pending
-- textobject).
---@class cword.TextObject
---@field buf integer buffer handle
---@field row integer 1-indexed row
---@field start integer 1-indexed byte (inclusive)
---@field end_excl integer 1-indexed byte (exclusive)
---@field text string the selected text
---@field ai 'i'|'a'

---@param buf integer buffer handle (0 for current)
---@param row integer 1-indexed line number
---@param col integer 0-indexed byte column
---@param ai 'i'|'a'| `'i'` for inner word, `'a'` for a word (+ trailing ws)
---@return cword.TextObject?
function M.text_object(buf, row, col, ai)
  ai = ai or 'i'
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  if row < 1 or row > line_count then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
  local col_1 = col + 1
  if col_1 < 1 then
    return nil
  end
  -- Past-EOL (beyond `#line + 1`) is invalid; nil so callers bail.
  -- `find_text_object` itself handles the AT-EOL case (`#line + 1`).
  if col_1 > #line + 1 then
    return nil
  end
  local start_c, end_c = find_text_object(line, col_1, ai)
  if not start_c then
    return nil
  end
  return {
    buf = buf,
    row = row,
    start = start_c,
    end_excl = end_c,
    text = line:sub(start_c, end_c - 1),
    ai = ai,
  }
end

-- Double-click word-selection helper. Bind it to `<2-LeftMouse>`
-- Bind to `<2-LeftMouse>` to select the CJK-aware word under the
-- click (matching Vim's built-in ASCII behaviour, but using
-- iskeyword + cjdict instead of \w). Like find_start_of_word +
-- find_end_of_word in src/nvim/mouse.c, but CJK-aware.
---@param buf integer buffer handle (0 for current)
---@param row integer 1-indexed line number
---@param col integer 0-indexed byte column
---@param ai 'i'|'a'| selection type (`'a'` includes trailing ws, like `aw`)
---@return boolean true if a word was selected
function M.double_click_select(buf, row, col, ai)
  local obj = M.text_object(buf, row, col, ai)
  if not obj then
    return false
  end
  vim.cmd('normal! \\<Esc>')
  -- '> is the first byte of the last CHAR (`:help '">`), not 1
  -- past the last byte of the word. end_excl is the latter, which
  -- for CJK is the lead byte of the NEXT char; snap back to the
  -- previous char's lead byte so the visual area covers exactly
  -- the word.
  local line = vim.api.nvim_buf_get_lines(obj.buf, obj.row - 1, obj.row, false)[1] or ''
  vim.fn.setpos("'<", { obj.buf, obj.row, obj.start, 0 })
  vim.fn.setpos("'>", { obj.buf, obj.row, char_start(line, obj.end_excl - 1), 0 })
  vim.cmd('normal! gv')
  return true
end

-- Insert-mode word motions (readline-style).

local function insert_move(method, direction)
  local is_fwd = direction == 'forward' or direction == 'end_forward'
  return function()
    local win = vim.api.nvim_get_current_win()
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(win))
    local cursor = col0 + 1
    local line = vim.api.nvim_get_current_line()
    local target = method(_cut, line, cursor)

    -- Forward past-end: snap to EOL first; only wrap on a
    -- subsequent call.
    if is_fwd and target > #line and cursor <= #line then
      target = #line + 1
    elseif is_fwd and target > #line and cursor > #line then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local nr, bs = _find_wrap_forward(lines, row + 1)
      if nr then
        row, target = nr, bs
      else
        return
      end
    elseif not is_fwd and target <= 1 and col0 == 0 then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local nr, _, be = _find_wrap_backward(lines, row - 1)
      if nr then
        row, target = nr, be + 1
      else
        return
      end
    end

    local target_col = math.max(0, target - 1)
    pcall(vim.api.nvim_win_set_cursor, win, { row, target_col })
  end
end

M.insert_forward = insert_move(M.motion.forward, 'forward')
M.insert_backward = insert_move(M.motion.backward, 'backward')

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

  -- Stock nvim deletes the word before cursor plus any trailing
  -- whitespace between the word and cursor. The insert start
  -- (where this session began typing) is a hard stop: appending
  -- `def` to `abc` removes only `def`, not the combined `abcdef`
  -- (nvim's `ins_bs` enforces this via `Insstart_orig`).
  local tokens = _cut(line)
  local word_start = nil
  local delete_end = col0

  -- Only treat the insert start as a boundary when the cursor
  -- has actually moved past it (chars were typed in this session).
  -- Without this, <c-w> fired the instant insert mode opens would
  -- refuse to delete the pre-existing text under the cursor.
  local ins_col = -1
  if vim.b.cword_ins_start and col0 > vim.b.cword_ins_start then
    ins_col = vim.b.cword_ins_start
  end

  for i = #tokens, 1, -1 do
    local t = tokens[i]
    local t_end_0 = t.byte_end - 1

    if t_end_0 < col0 then
      if is_whitespace(t) then
        -- skip whitespace, keep looking
      else
        word_start = t.byte_start - 1
        if ins_col > word_start then
          word_start = ins_col
        end
        break
      end
    elseif t.byte_start - 1 < col0 and t_end_0 >= col0 then
      if not is_whitespace(t) then
        word_start = t.byte_start - 1
        if ins_col > word_start then
          word_start = ins_col
        end
        break
      end
    end
  end

  if word_start == nil then
    -- Cursor at the start of a word or in leading whitespace before
    -- any word: delete the leading whitespace up to the cursor.
    for _, t in ipairs(_cut(line)) do
      if t.byte_start - 1 == col0 and not is_whitespace(t) then
        word_start = 0
        break
      end
    end
    if word_start == nil and col0 > 0 then
      for _, t in ipairs(_cut(line)) do
        if not is_whitespace(t) and t.byte_start - 1 > 0 then
          word_start = 0
          break
        end
      end
    end
    if word_start == nil and col0 >= #line then
      -- Cursor on a whitespace-only line: delete the whole line.
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

  local row1 = row - 1
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
  local tokens = _cut(line)
  local target = pos - 1 -- 0-indexed byte to delete from

  for i = #tokens, 1, -1 do
    local t = tokens[i]
    if t.byte_end < pos then
      target = t.byte_start - 1
      if is_whitespace(t) then
        -- keep looking for the word, but eat the whitespace
      else
        break
      end
    elseif t.byte_start < pos and t.byte_end >= pos then
      if not is_whitespace(t) then
        target = t.byte_start - 1
        break
      end
    end
  end

  if target >= pos - 1 then
    return
  end

  -- Mirror insert_delete_word's yank into the small-delete register.
  vim.fn.setreg('-', line:sub(target + 1, pos - 1))
  vim.fn.setcmdline(line:sub(1, target) .. line:sub(pos), target + 1)
end

-- CJK-aware cword lookup.
--
-- `expand('<cword>')` only sees `iskeyword` bytes, so on a CJK line it
-- returns one character and search tools like vim-asterisk highlight
-- one char at a time. These walk the same token stream w/b/e/ge use,
-- so "the current word" matches what `w` would treat as a word — a
-- merged CJK run for "你好世界", a single identifier for "hello".

---@return table?
local function token_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col0 = vim.api.nvim_win_get_cursor(0)[2]
  local c = col0 + 1
  local last_word
  for _, t in ipairs(_cut(line)) do
    if t.byte_start <= c and t.byte_end >= c then
      if is_whitespace(t) or not t.is_word_like then
        return nil
      end
      return t
    end
    if t.byte_start <= c and not is_whitespace(t) and t.is_word_like then
      last_word = t
    end
  end
  -- Cursor one cell past the last byte (virtualedit allows this):
  -- if the line ends on a word, return that word to match
  -- expand('<cword>').
  if last_word and last_word.byte_end == #line then
    return last_word
  end
  return nil
end

---CJK-aware word under the cursor. Mirrors `expand('<cword>')` (empty
---string when not on a word token); the difference is CJK content,
---where it returns the merged run instead of one char.
---@return string
function M.get_cword()
  local tok = token_at_cursor()
  if not tok then
    return ''
  end
  return tok.text
end

---Full token under the cursor. Nil on whitespace or non-word non-ws.
---@return { text: string, byte_start: integer, byte_end: integer, is_word_like: boolean }?
function M.get_token()
  return token_at_cursor()
end

return M
