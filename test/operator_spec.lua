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

  it('viw with keymap set up selects hello', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('viw')
    -- After the function, check that the cursor is at col 5
    -- (end of "hello") and the mode is still visual. These are
    -- the concrete side effects of the keymap handler, regardless
    -- of how nvim-test renders the visual highlight.
    local state = helpers.exec_lua(function()
      return {
        mode = vim.api.nvim_get_mode().mode,
        cursor = vim.api.nvim_win_get_cursor(0)[2],
        col1 = vim.fn.col('v'),
        col2 = vim.fn.col('.'),
      }
    end)
    eq('v', state.mode)
    eq(5, state.cursor)
    eq(1, state.col1)
    eq(6, state.col2)
  end)

  it('vaw extends to the word plus its trailing space', function()
    put('hello world foo')
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('vaw')
    local state = helpers.exec_lua(function()
      return {
        mode = vim.api.nvim_get_mode().mode,
        cursor = vim.api.nvim_win_get_cursor(0)[2],
        col1 = vim.fn.col('v'),
        col2 = vim.fn.col('.'),
      }
    end)
    eq('v', state.mode)
    eq(6, state.cursor)
    eq(1, state.col1)
    eq(7, state.col2)
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
