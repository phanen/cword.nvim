--- @diagnostic disable: undefined-global
-- E2E specs for operator-pending mode.
-- Insert mode lives in test/insert_spec.lua.
-- Command-line mode lives in test/cmdline_spec.lua.

local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

describe('operator-pending mode', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      require('cword').setup()
      local m = require('cword')
      local opts = { noremap = true, silent = true }
      vim.keymap.set({ 'n', 'x' }, 'w', m.move_forward, opts)
      vim.keymap.set({ 'n', 'x' }, 'b', m.move_backward, opts)
      vim.keymap.set('o', 'w', m.op_forward, { expr = true, noremap = true, silent = true })
      vim.keymap.set('o', 'b', m.op_backward, { expr = true, noremap = true, silent = true })
      vim.keymap.set('o', 'e', m.op_end_forward, { expr = true, noremap = true, silent = true })
      vim.keymap.set('o', 'ge', m.op_end_backward, { expr = true, noremap = true, silent = true })
    end)
    screen = Screen.new(40, 6)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('dw deletes to next word start', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world foo' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    screen:expect({
      grid = [[
  ^world foo                               |
  ~                                       |
  ~                                       |
  ~                                       |
  ~                                       |
                                          |
]],
    })
  end)

  it('dw on a b deletes a and space', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'a b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    eq('b', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de on a b deletes whole line but not next', function()
    -- nvim --clean behavior: de from 'a' in 'a b' deletes the
    -- whole line content ('a b') but not the newline.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'a b', 'c' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('', lines[1])
    eq('c', lines[2])
  end)

  it('de on a b single line deletes all', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'a b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    eq('', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de on a at start of multi-line does not eat next line', function()
    -- 'a b' on line 1, 'c' on line 2. de from 'a' should delete
    -- 'a b' (whole line content) but not cross-line to delete 'c'.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'a b', 'c' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('', lines[1])
    eq('c', lines[2])
  end)

  it('dw deletes word on CJK end-of-line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('dw')
    eq('你好', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de deletes to end of word on CJK end-of-line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('de')
    eq('你好', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('d2w deletes two words on ASCII', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar baz' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('d2w')
    eq('baz', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('cw replaces a CJK word with insert mode', function()
    -- icu_ffi merges "你好" into one cjdict run, so cw eats the
    -- whole run and leaves "我".
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    eq('我', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode:sub(1, 1))
  end)

  it('db deletes previous word on ASCII', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar baz' })
    helpers.api.nvim_win_set_cursor(0, { 1, 8 })
    helpers.feed('db')
    eq('foo baz', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('db deletes the preceding CJK run', function()
    -- icu_ffi merges "你好" into one run, so db from the start of
    -- "我" eats the whole "你好" run and lands on "我".
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('db')
    eq('我', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de deletes to end of word including the last character', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    eq(' world', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('ce changes to end of word including the last character', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('ce')
    eq(' world', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode:sub(1, 1))
  end)

  it('ye yanks to end of word including the last character', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('ye')
    local reg = helpers.exec_lua('return vim.fn.getreg("0")')
    eq('hello', reg)
  end)

  it('yw yanks word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('yw')
    local reg = helpers.exec_lua('return vim.fn.getreg("0")')
    eq('hello ', reg)
  end)

  it('dw at end of line does not join lines', function()
    -- Stock Vim's operator-pending w does NOT wrap to the next
    -- line; only normal-mode w wraps.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('hell', lines[1])
    eq('world', lines[2])
  end)

  it('dw on a single-word last line deletes the whole line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('', lines[1])
  end)

  it('db wraps to previous line and removes the previous word', function()
    -- cword's `b` wraps when the cursor is on a word boundary at
    -- col 0, unlike stock vim. With byte_start anchoring, db from
    -- the start of "world" eats the preceding "hello\n" so the
    -- previous line disappears into the cursor line.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('db')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('world', lines[1])
  end)

  it('d3w across multiple lines deletes everything', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo', 'bar', 'baz' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('d3w')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('', lines[1])
  end)

  it('d3w across lines with inner words stays on word boundaries', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar', 'baz bac' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('d3w')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('bac', lines[1])
  end)

  -- CJK operator-pending

  it('dw on CJK 你好世界 deletes 你好', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('cw on CJK 你好世界 changes 你好 and enters insert', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode:sub(1, 1))
  end)

  it('de on CJK 你好世界 deletes to end of 你好', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('cw on abc def changes abc and trailing space', function()
    -- nvim --clean: cw from col 0 deletes 'abc ' (word + one
    -- space), leaving ' def'. The user reported cw was leaving
    -- ' def' but by removing the trailing space too, i.e. by
    -- matching dw instead of ce.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    local result = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    io.write('cw result: "' .. result .. '"\n')
    eq(' def', result)
  end)

  it('cw on leading whitespace deletes whitespace and word', function()
    -- nvim --clean: cw on leading whitespace '   abc' from col 0
    -- deletes the leading whitespace + the next word, leaving
    -- 'abc'. The user reported that the result should be 'abc'
    -- (i.e. the leading spaces are consumed).
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '   abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    local result = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    io.write('cw on leading ws result: "' .. result .. '"\n')
    eq('abc', result)
  end)

  it('ce on leading whitespace deletes through end of next word', function()
    -- nvim --clean: ce on '   abc def' from col 0 should delete
    -- '   abc ' (leading whitespace + first word + one space),
    -- leaving ' def'. The user reported that the result should
    -- be ' def'. This is different from cw which only consumes
    -- the leading whitespace; ce extends through the end of
    -- the next word.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '   abc def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('ce')
    local result = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    io.write('ce on leading ws result: "' .. result .. '"\n')
    eq(' def', result)
  end)

  it('ce on ab cd at col 0 deletes ab plus trailing space', function()
    -- nvim --clean: ce from col 0 on 'ab cd' deletes 'ab ' (word
    -- + one space), leaving ' cd'. Cursor is on 'a' (end of 'ab'
    -- is at col 2, same as start of 'ab' which is at col 0).
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'ab cd' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('ce')
    local result = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    io.write('ce result: "' .. result .. '"\n')
    eq(' cd', result)
  end)

  it('db on CJK 你好世界 from 世界 deletes 你好', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('db')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  -- CJK + ASCII mixed operator-pending

  it('dw on CJK+ASCII 你好 hello 世界 from 你好 deletes 你好+space', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 hello 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    eq('hello 世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dw from middle CJK+ASCII only deletes from cursor', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 hello 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 3 }) -- inside 你好
    helpers.feed('dw')
    eq('你hello 世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dge at EOL line 1 does not cross line (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 }) -- on 'd'
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('hell', lines[1])
    eq('foo bar', lines[2])
  end)

  it('dge at EOL line 1 does not cross line (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 你好', '你好 你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 12 }) -- on last 好
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('你', lines[1])
    eq('你好 你好', lines[2])
  end)

  it('dge at BOL wraps to last char of previous line (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hello worloo bar', lines[1])
  end)

  it('dge at BOL wraps to last char of previous line (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 你好', '你好 你好' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('你好 你好 你好', lines[1])
  end)

  it('dge at BOL wraps to empty previous line (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '', '你好 你好' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('好 你好', lines[1])
  end)

  it('dge at BOL wraps to empty previous line (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('oo bar', lines[1])
  end)

  it('dge at BOL wraps past multiple empty lines', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '', '', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 3, 0 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('', lines[1])
    eq('oo bar', lines[2])
  end)

  -- Regression: `ce` from end of a non-last word on a multi-word
  -- line must not wrap to the next line. Previously cword always
  -- wrapped when the motion target was at the end of the line,
  -- so `ce` from `c` of "abc def" with "foo" on the next line
  -- ate the "foo" line.
  it('ce at end of non-last word does not wrap (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc def', 'foo' })
    helpers.api.nvim_win_set_cursor(0, { 1, 2 })
    helpers.feed('ce')
    eq({ 'ab', 'foo' }, helpers.api.nvim_buf_get_lines(0, 0, -1, false))
    eq('i', helpers.api.nvim_get_mode().mode)
    eq({ 1, 2 }, helpers.api.nvim_win_get_cursor(0))
  end)

  -- Regression: the cursor after `c{motion}` lands at the position
  -- where the deleted range started, in the new line. For
  -- `ce` on the start of a word, the deletion is shorter than
  -- the line, so the cursor lands mid-line at s_col, not at past-EOL.
  it('ce on first char of word lands cursor at s_col (not past-EOL)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('ce')
    eq(' def', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    eq('i', helpers.api.nvim_get_mode().mode)
    eq({ 1, 0 }, helpers.api.nvim_win_get_cursor(0))
  end)

  -- Regression: cword merges CJK runs so `end_forward` from a mid-char
  -- cursor lands at #line even though the cursor is not at end of last
  -- word. nvim's operator-pending also clamps the cursor back to the
  -- start byte of the char it was on. The wrap check must not be
  -- fooled by this; only wrap when the cursor is at the start byte of
  -- the last char of the line, so `de` from mid 你好 eats only 世.
  it('de on 世 of 你好世界\\n123 deletes only 世 (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '123' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 }) -- start of 世
    helpers.feed('de')
    eq({ '你好', '123' }, helpers.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('ce on 世 of 你好世界\\n123 deletes only 世 (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '123' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('ce')
    eq({ '你好', '123' }, helpers.api.nvim_buf_get_lines(0, 0, -1, false))
    eq('i', helpers.api.nvim_get_mode().mode)
    eq({ 1, 6 }, helpers.api.nvim_win_get_cursor(0))
  end)

  it('de at EOL wraps to next line (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好', '世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 3 }) -- on 好 (last char)
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('你', lines[1])
  end)

  it('de at EOL with ASCII wraps to next line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 4 }) -- on 'o' (last char)
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hell', lines[1])
  end)

  it('de at EOL joins empty lines after (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 你好', '', '' })
    helpers.api.nvim_win_set_cursor(0, { 1, 12 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('你好 你', lines[1])
  end)

  it('de at EOL joins empty lines after (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', '', '' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hello worl', lines[1])
  end)

  it('de at EOL joins one empty line after (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 你好', '' })
    helpers.api.nvim_win_set_cursor(0, { 1, 12 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('你好 你', lines[1])
  end)

  it('de at EOL joins one empty line after (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', '' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hello worl', lines[1])
  end)

  -- de at various single-line positions
  it('de from start of word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    eq(' world', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de from middle of word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 2 })
    helpers.feed('de')
    eq('he world', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de from last char of word (before space)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 4 })
    helpers.feed('de')
    -- cword's end_forward from 'o' (end of "hello" token) wraps to
    -- next word "world" and deletes to its end.
    eq('hell', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de from space between words', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 })
    helpers.feed('de')
    eq('hello', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de from last char of line (EOL, single line)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 })
    helpers.feed('de')
    eq('hello worl', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  -- de cross-line at various positions
  it('de cross-line from last char of line 1 (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 4 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hell', lines[1])
  end)

  it('de cross-line from last char of multi-word line (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hello worl bar', lines[1])
  end)

  it('de cross-line from last char of multi-word line (CJK)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 你好', '你好 你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 12 })
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('你好 你 你好', lines[1])
  end)

  it('de from non-last char of last word stays on current line (ASCII)', function()
    -- Cursor on 'a' of 'abc' (first line); line 2 also has 'abc'.
    -- de should delete to the end of 'abc' on line 1, not cross
    -- to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 7 }) -- on 'a' of 'abc'
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('你好 ', lines[1])
    eq('abc', lines[2])
  end)

  it('de from middle char of last word stays on current line (ASCII)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 8 }) -- on 'b' of 'abc'
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('你好 a', lines[1])
    eq('abc', lines[2])
  end)

  it('de from non-last char of last CJK word stays on current line', function()
    -- 你好世界: cursor on 你 (first char of 你好). de should
    -- delete to the end of 你好, not cross to next line.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 }) -- on '你'
    helpers.feed('de')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('世界', lines[1])
    eq('你好', lines[2])
  end)

  -- dge at various single-line positions
  it('dge from middle of word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 7 })
    helpers.feed('dge')
    eq('hellrld', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dge from first char of word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('dge')
    eq('hellorld', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dge from space between words', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 })
    helpers.feed('dge')
    eq('hellworld', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dge from first char of line (no-op)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dge')
    eq('hello world', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dge from end of CJK word on line 2 should match stock nvim', function()
    -- Cursor on the first 好 of the second line (col 3).
    -- Stock nvim: dge from the end of the first word crosses
    -- to the previous line and deletes back to the end of the
    -- last word there.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '123', '你好 你好' })
    helpers.api.nvim_win_set_cursor(0, { 2, 3 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('12 你好', lines[1])
  end)

  it('dge from end of CJK word on line 2 with trailing space', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '123', '你好 你好 ' })
    helpers.api.nvim_win_set_cursor(0, { 2, 3 })
    helpers.feed('dge')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('12 你好 ', lines[1])
  end)

  -- dw at EOL
  it('dw at EOL does not cross line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 4 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('hell', lines[1])
    eq('world', lines[2])
  end)

  -- dw on empty line deletes the line (including newline)
  it('dw on empty line deletes the line', function()
    -- nvim --clean behavior: dw on an empty line deletes the
    -- current line (joining it with the next line). cw on an
    -- empty line does NOT delete the line.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '', 'hello' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('hello', lines[1])
  end)

  -- `dw` on an empty line always joins it with the next line, even
  -- if the following lines are all empty. The result is the empty
  -- line deleted and the next line promoted.
  it('dw on empty line with only empty lines after joins next empty', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '', '', '' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('', lines[1])
    eq('', lines[2])
  end)

  -- `dw` on the very last line (which is empty) is a no-op, matching
  -- stock nvim. There is no next line to join with.
  it('dw on the last (empty) line is a no-op', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc', '' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('abc', lines[1])
    eq('', lines[2])
  end)

  -- cw on empty line does NOT delete the line
  it('cw on empty line does not delete the line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '', 'hello' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(2, #lines)
    eq('', lines[1])
    eq('hello', lines[2])
    -- cw should enter insert mode
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode)
    -- single <Esc> should exit insert mode (not require two)
    helpers.feed('<Esc>')
    mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('n', mode)
  end)

  -- db at BOL
  it('db at BOL wraps to previous line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('db')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('world', lines[1])
  end)
end)

-- icu_ffi segments "你好" as one word (cjdict merge). The operator
-- handlers must use that boundary verbatim, so dw eats the merged
-- "你好" rather than just the first character. The test is skipped
-- when libicuuc is not available in the test environment.
describe('operator-pending mode (icu_ffi backend)', function()
  local screen
  local ok_ffi = false

  setup(function()
    ok_ffi = pcall(require, 'cword.backends.icu_ffi')
  end)

  before_each(function()
    if not ok_ffi then
      return
    end
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup()
      local m = cword
      local opts = { noremap = true, silent = true }
      vim.keymap.set({ 'n', 'x' }, 'w', m.move_forward, opts)
      vim.keymap.set({ 'n', 'x' }, 'b', m.move_backward, opts)
      vim.keymap.set('o', 'w', m.op_forward, vim.tbl_extend('force', opts, { expr = true }))
      vim.keymap.set('o', 'b', m.op_backward, vim.tbl_extend('force', opts, { expr = true }))
      vim.keymap.set('o', 'e', m.op_end_forward, vim.tbl_extend('force', opts, { expr = true }))
    end)
    screen = Screen.new(40, 6)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('dw eats the merged cjdict run as one word', function()
    if not ok_ffi then
      return
    end
    -- "你好" is a single icu token; dw from col 0 should consume
    -- "你好" plus the following whitespace.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dw on the second CJK word deletes it', function()
    if not ok_ffi then
      return
    end
    -- Cursor on the start of "世界" (col 7, the char boundary
    -- right after the space). dw eats the merged run.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 7 })
    helpers.feed('dw')
    eq('你好 ', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('cw replaces the merged run and enters insert mode', function()
    if not ok_ffi then
      return
    end
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode:sub(1, 1))
  end)

  it('db eats the preceding merged run', function()
    if not ok_ffi then
      return
    end
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 7 })
    helpers.feed('db')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('de deletes the current merged run to its end', function()
    if not ok_ffi then
      return
    end
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    eq(' 世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dw wraps across newlines using icu boundaries', function()
    if not ok_ffi then
      return
    end
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好', '世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('世界', lines[1])
  end)

  it('dw on Latin eats the identifier and stops at the dot', function()
    if not ok_ffi then
      return
    end
    -- cword's `w` lands on the next non-whitespace token, which
    -- is the `.` here (it is not whitespace, just non-word). dw
    -- therefore eats "pkgs" and leaves ".hello" — same shape as
    -- the cjk backend, where the cjk motion spec asserts
    -- forward("pkgs.hello.out", 1) == 5.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'pkgs.hello' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    eq('.hello', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('dw from the dot eats just the dot (next non-ws boundary)', function()
    if not ok_ffi then
      return
    end
    -- Same shape as the cjk backend: forward on a non-word token
    -- (the dot) lands on the byte_start of the next non-ws token
    -- ("hello"). The "on the char + c - 2" visual formula
    -- therefore collapses the dot and "hello" to land on a single
    -- column, deleting only the dot here.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'pkgs.hello' })
    helpers.api.nvim_win_set_cursor(0, { 1, 4 })
    helpers.feed('dw')
    eq('pkgshello', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)
end)

describe('textobject iw/aw (icu_ffi backend)', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup()
      local m = cword
      local opts = { noremap = true, silent = true }
      vim.keymap.set({ 'n', 'x' }, 'w', m.move_forward, opts)
      vim.keymap.set('x', 'iw', m.textobject_inner_word, opts)
      vim.keymap.set('x', 'aw', m.textobject_a_word, opts)
      vim.keymap.set(
        'o',
        'iw',
        m.textobject_inner_word,
        vim.tbl_extend('force', opts, { expr = true })
      )
      vim.keymap.set('o', 'aw', m.textobject_a_word, vim.tbl_extend('force', opts, { expr = true }))
    end)
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  local function put(text)
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { text })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  it('diw deletes the inner word on ASCII', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('diw')
    eq(' world foo', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('daw deletes the word plus its trailing space', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('daw')
    eq('world foo', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('diw from the end of a word deletes that word', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 4 })
    helpers.feed('diw')
    eq(' world foo', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('diw on the last word keeps any leading whitespace', function()
    put('hello world')
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('diw')
    eq('hello ', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('daw at end of line deletes just the word (no trailing ws)', function()
    put('hello world')
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('daw')
    eq('hello ', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('ciw replaces the inner word and enters insert mode', function()
    put('hello world')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('ciw')
    eq(' world', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode:sub(1, 1))
  end)

  it('diw on a merged cjdict run eats the whole run', function()
    put('你好 世界')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('diw')
    eq(' 世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('daw on a merged cjdict run eats run + trailing whitespace', function()
    put('你好 世界')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('daw')
    eq('世界', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('viw extends the visual selection to the inner word', function()
    -- Control: just `v` first to see what the screen looks like
    -- before the keymap handler runs.
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('v')
    screen:expect({
      grid = [[
  ^hello world foo                         |
  ~                                       |
  ~                                       |
  -- VISUAL --                            |
]],
    })
  end)

  it('viw on a CJK run covers the whole run, not the trailing CJK byte', function()
    -- Regression for the partial-run selection bug: with `end_c` (= 7)
    -- passed verbatim to setpos('`>', ...), Vim treated byte 7 — the
    -- lead byte of 世, which is a valid char start — as the last char of
    -- the visual area, so the region came back as { "你好世" } when the
    -- cursor sat anywhere on the 你好 run. Read the actual visual region
    -- via getregion() so the assertion catches this class of bug
    -- regardless of mark conventions.
    put('你好世界')
    helpers.api.nvim_win_set_cursor(0, { 1, 4 }) -- middle byte of 好
    helpers.feed('viw')
    eq('v', helpers.api.nvim_get_mode().mode)
    local region = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return ok and r or ('err:' .. tostring(r))
    end)
    eq({ '你好' }, region)
  end)

  it('viw selects the inner word regardless of which CJK byte the cursor sits on', function()
    -- Exhaustive: viw must select 你好 from any byte on the run (or 世界
    -- from any byte on that run). The pre-fix bug was off-by-one
    -- because `'<`/`'>` setpos got end_c (= byte after the word) instead
    -- of the lead byte of the last char.
    local results = {}
    for byte_col = 0, 11 do
      put('你好世界')
      helpers.api.nvim_win_set_cursor(0, { 1, byte_col })
      helpers.feed('viw')
      results[byte_col] = helpers.exec_lua(function()
        local ok, r =
          pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
        return ok and r or ('err:' .. tostring(r))
      end)
      helpers.exec_lua(function()
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes('<Esc>', true, false, true),
          'mtx',
          false
        )
      end)
    end
    for i = 0, 5 do
      eq({ '你好' }, results[i], 'cursor col ' .. i)
    end
    for i = 6, 11 do
      eq({ '世界' }, results[i], 'cursor col ' .. i)
    end
  end)

  it('vaw on a CJK run covers the run plus its trailing whitespace', function()
    put('你好 世界')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('vaw')
    local region = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return ok and r or ('err:' .. tostring(r))
    end)
    eq({ '你好 ' }, region)
  end)

  it('viw with keymap set up selects hello', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('viw')
    -- `'<` / `'>` mark the lead byte of the last CHAR of the visual
    -- area (`:help '">`); for ASCII 'hello' that's the lead byte of 'o',
    -- which equals the byte column where nvim reports col('.'). Read
    -- the actual visual region to validate behavior without relying on
    -- mark conventions.
    eq('v', helpers.api.nvim_get_mode().mode)
    local region = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return ok and r or ('err:' .. tostring(r))
    end)
    eq({ 'hello' }, region)
  end)

  it('vaw extends to the word plus its trailing space', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('vaw')
    local state = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return {
        mode = vim.api.nvim_get_mode().mode,
        cursor = vim.api.nvim_win_get_cursor(0)[2],
        col1 = vim.fn.col('v'),
        col2 = vim.fn.col('.'),
        region = ok and r or ('err:' .. tostring(r)),
      }
    end)
    eq('v', state.mode)
    eq({ 'hello ' }, state.region)
  end)

  it('virtualedit is restored after viw', function()
    local saved = helpers.exec_lua(function()
      return vim.o.virtualedit
    end)
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('viw')
    -- schedule runs in the next tick; wait for it then check.
    helpers.exec_lua(function()
      vim.wait(50, function()
        return vim.o.virtualedit == saved
      end)
    end)
    eq(
      saved,
      helpers.exec_lua(function()
        return vim.o.virtualedit
      end)
    )
  end)
end)

describe('text_object API + mouse double-click', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  it('text_object returns the inner word byte range for ASCII', function()
    local result = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world foo' })
      -- Cursor on 'l' of 'hello' (col 1 0-indexed = byte 2 1-indexed)
      return cword.text_object(0, 1, 2, 'i')
    end)
    eq('hello', result.text)
    eq(1, result.start) -- 1-indexed byte_start inclusive
    eq(6, result.end_excl) -- 1-indexed byte_end exclusive
    eq('i', result.ai)
  end)

  it('text_object extends with trailing ws for ai = "a"', function()
    local result = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world foo' })
      return cword.text_object(0, 1, 2, 'a')
    end)
    eq('hello ', result.text) -- word + 1 space
    eq(1, result.start)
    eq(7, result.end_excl)
  end)

  it('text_object returns merged CJK run for cjdict', function()
    local result = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
      -- Cursor on second char of 你好 (byte 4 = col 3 0-indexed)
      return cword.text_object(0, 1, 3, 'i')
    end)
    eq('你好', result.text)
    eq(1, result.start)
    eq(7, result.end_excl) -- 你好 is 6 bytes
  end)

  it('text_object splits CJK at word-class boundaries', function()
    local ni_hao = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '你 好 世界' })
      return cword.text_object(0, 1, 5, 'i') -- cursor on '好'
    end)
    eq('好', ni_hao.text)
    eq(5, ni_hao.start)
    eq(8, ni_hao.end_excl)

    local shi_jie = helpers.exec_lua(function()
      local cword = require('cword')
      return cword.text_object(0, 1, 10, 'i') -- cursor on '世'
    end)
    eq('世界', shi_jie.text)
    eq(9, shi_jie.start)
    eq(15, shi_jie.end_excl)
  end)

  it('text_object returns nil on whitespace and past EOL', function()
    local r1 = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '你 好 世界' })
      return cword.text_object(0, 1, 3, 'i') -- on the space
    end)
    eq(nil, r1)
    local r2 = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc' })
      return cword.text_object(0, 1, 4, 'i') -- past EOL
    end)
    eq(nil, r2)
  end)

  it('text_object clamps EOL cursor (#line + 1) to last token', function()
    -- nvim's mouse column can report one past the last byte (EOL).
    -- We clamp to #line + 1 and return the last token.
    local r = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello' })
      return cword.text_object(0, 1, 5, 'i')
    end)
    eq('hello', r.text)
  end)

  it('text_object returns nil for invalid row / buf', function()
    local r1 = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello' })
      return cword.text_object(0, 99, 0, 'i')
    end)
    eq(nil, r1)
    local r2 = helpers.exec_lua(function()
      return require('cword').text_object(9999, 1, 0, 'i')
    end)
    eq(nil, r2)
  end)

  it('double_click_select sets visual marks and enters visual mode', function()
    -- `'>` is the lead byte of the last CHAR (`:help '">`): for 'hello'
    -- that's the lead byte of 'o' (= byte 5), not byte 6 (one past).
    -- The end mark must point AT the last char, not past it.
    local ok = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
      -- Simulate double-click on 'l' of 'hello' (col 2 0-indexed)
      return cword.double_click_select(0, 1, 2, 'i')
    end)
    eq(true, ok)
    eq('v', helpers.api.nvim_get_mode().mode)
    local marks = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return {
        s = vim.fn.getpos("'<"),
        e = vim.fn.getpos("'>"),
        region = ok and r or ('err:' .. tostring(r)),
      }
    end)
    eq(1, marks.s[2]) -- start row
    eq(1, marks.s[3]) -- start col 1-indexed byte = 'h'
    eq(1, marks.e[2])
    eq(5, marks.e[3]) -- 'o' (lead byte of last char)
    eq({ 'hello' }, marks.region)
  end)

  it('double_click_select on whitespace returns false without changing marks', function()
    local ok = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
      return cword.double_click_select(0, 1, 5, 'i') -- on the space
    end)
    eq(false, ok)
  end)

  it('double_click_select with ai="a" includes trailing whitespace', function()
    -- `aw` extends past the trailing whitespace: visual area covers
    -- "hello " (6 bytes). `'>` should be the lead byte of the last
    -- included char — the space at byte 6, not byte 7 (one past).
    local ok = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
      return cword.double_click_select(0, 1, 2, 'a')
    end)
    eq(true, ok)
    local result = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return {
        e = vim.fn.getpos("'>")[3],
        region = ok and r or ('err:' .. tostring(r)),
      }
    end)
    eq(6, result.e) -- lead byte of the trailing space
    eq({ 'hello ' }, result.region)
  end)

  it('double_click_select on a CJK run selects the whole run', function()
    -- `'>` should be the lead byte of the last CHAR (per `:help '">`):
    -- for 你好 that's byte 4 (start of 好), NOT byte 7 (start of 世,
    -- which is what `end_excl` would point at). Read the actual visual
    -- region so the assertion catches the bug class rather than
    -- encoding the previous wrong mark convention.
    local ok = helpers.exec_lua(function()
      local cword = require('cword')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界' })
      return cword.double_click_select(0, 1, 2, 'i') -- middle of 你好
    end)
    eq(true, ok)
    local result = helpers.exec_lua(function()
      local ok, r =
        pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = 'v' })
      return {
        s = vim.fn.getpos("'<")[3],
        e = vim.fn.getpos("'>")[3],
        region = ok and r or ('err:' .. tostring(r)),
      }
    end)
    eq(1, result.s) -- byte 1 1-indexed = '你'
    eq(4, result.e) -- byte 4 1-indexed = '好' (last char of selection)
    eq({ '你好' }, result.region)
  end)
end)
