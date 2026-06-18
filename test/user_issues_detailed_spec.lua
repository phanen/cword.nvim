local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')
local eq = helpers.eq

describe('user reported issues - detailed', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      require('cword').setup()
      local m = require('cword')
      vim.keymap.set({ 'n', 'x' }, 'w', m.move_forward, { noremap = true, silent = true })
      vim.keymap.set({ 'n', 'x' }, 'e', m.move_end_forward, { noremap = true, silent = true })
      vim.keymap.set('i', '<c-w>', m.insert_delete_word, { noremap = true, silent = true })
    end)
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('issue 1: <c-w> with 你好你好 should delete only one 你好', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local line = helpers.exec_lua('return vim.api.nvim_get_current_line()')
    eq('你好', line)
  end)

  it('issue 2: e from start of line with CJK should not jump to next line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(3, cursor[2]) -- should be at start of 好 (last char of 你好)
  end)

  it('issue 3: e from space should not jump to next line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { ' a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(1, cursor[2]) -- should be at 'a'
  end)

  it('issue 4: e from space mid-line with CJK+ASCII should go to next word end', function()
    -- Cursor on the space between 你好 and a on line 1; line 2 has
    -- a single-char word. 'e' should land on the end of 'a' on
    -- line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 }) -- on the space
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(7, cursor[2]) -- end of 'a'
  end)

  it('issue 5: e from space mid-line with ASCII should go to next word end', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 }) -- on the space
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(10, cursor[2]) -- end of 'world'
  end)

  it('issue 6: <c-w> with abc-def should delete only the last word', function()
    -- '-' is not in the default iskeyword, so each ASCII run is
    -- its own word. <C-w> should delete only 'def' (plus any
    -- trailing whitespace), not the whole 'abc-def'.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc-def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local line = helpers.exec_lua('return vim.api.nvim_get_current_line()')
    eq('abc-', line)
  end)

  it('issue 7: <c-w> with CJK-ASCII mixed respects word boundaries', function()
    -- 你好-a: the '-' is not word-like, so <C-w> deletes only the
    -- ASCII 'a' (plus any trailing whitespace), leaving '你好-'.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好-a' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local line = helpers.exec_lua('return vim.api.nvim_get_current_line()')
    eq('你好-', line)
  end)

  it('issue 8: e on non-last char of last word should go to last char', function()
    -- Cursor on 'a' of 'abc' (first line); line 2 also has 'abc'.
    -- 'e' should land on the end of 'abc' (col 9) on line 1, not
    -- jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 7 }) -- on 'a' of 'abc'
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(9, cursor[2]) -- end of 'abc'
  end)

  it('issue 9: e on middle char of last word should go to last char', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 8 }) -- on 'b' of 'abc'
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(9, cursor[2]) -- end of 'abc'
  end)

  it('issue 10: e on CJK non-last char of last word should go to last char', function()
    -- 你好世界: cursor on 你 (first char of 你好). 'e' should go
    -- to the end of 你好 (start of 好, col 3), not jump to next line.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 }) -- on '你'
    helpers.feed('e')
    local cursor = helpers.api.nvim_win_get_cursor(0)
    eq(1, cursor[1]) -- should stay on line 1
    eq(3, cursor[2]) -- start of 好 (end of 你好)
  end)
end)
