--- @diagnostic disable: undefined-global
-- Insert-mode word motions. The handlers read the current line
-- from the buffer and move the cursor, so we can drive them via
-- Screen:expect + helpers.feed like the e2e operator-pending
-- specs.
local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')
local eq = helpers.eq

describe('insert mode', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup()
      local opts = { noremap = true, silent = true }
      vim.keymap.set('i', '<m-f>', cword.insert_forward, opts)
      vim.keymap.set('i', '<m-b>', cword.insert_backward, opts)
      vim.keymap.set('i', '<c-w>', cword.insert_delete_word, opts)
    end)
    screen = Screen.new(40, 6)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('<c-w> deletes the word before the cursor', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 }) -- end of "world" (before trailing space)
    helpers.feed('a')
    helpers.feed('<c-w>')
    screen:expect({
      grid = [[
  hello ^                                  |
  ~                                       |
  ~                                       |
  ~                                       |
  ~                                       |
  -- INSERT --                            |
]],
    })
  end)

  it('<c-w> in the middle of a line deletes word before cursor', function()
    -- "hello |world" -> c-w -> "world". Vim's built-in <c-w>
    -- in insert mode eats the word before the cursor plus any
    -- whitespace between the word and cursor.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 }) -- at space (0-indexed)
    helpers.feed('a')
    helpers.feed('<c-w>')
    local state = helpers.exec_lua(function()
      vim.wait(50, function()
        return vim.api.nvim_get_current_line() == 'world'
      end)
      return {
        line = vim.api.nvim_get_current_line(),
        cursor = vim.api.nvim_win_get_cursor(0)[2],
      }
    end)
    eq('world', state.line)
    eq(0, state.cursor)
  end)

  it('<c-w> at start of first word deletes leading whitespace', function()
    -- "  |hello" -> i<c-w> -> "hello". cword should delete the
    -- leading whitespace when the cursor is at the start of the
    -- first word.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '  hello' })
    helpers.api.nvim_win_set_cursor(0, { 1, 2 })
    helpers.feed('i<c-w>')
    eq('hello', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('<c-w> in leading whitespace deletes whitespace up to cursor', function()
    -- "  |abc" -> i<c-w> -> "|abc". Cursor at col 2 (start of
    -- 'abc'), then <c-w> should delete the leading whitespace.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '  abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 2 })
    helpers.feed('i<c-w>')
    eq('abc', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('<c-w> at col 0 on whitespace-only line does not error', function()
    -- "  " -> <c-w> should not error. nvim --clean behavior:
    -- <c-w> at col 0 joins with previous line or does nothing.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '  ' })
    helpers.api.nvim_win_set_cursor(0, { 1, 2 })
    helpers.feed('a<c-w>')
    eq('', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('<m-f> moves forward one word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('i')
    helpers.feed('<m-f>')
    -- The handler defers the cursor move via vim.schedule; wait
    -- for it to land before asserting the screen.
    helpers.exec_lua(function()
      vim.wait(50, function()
        return vim.api.nvim_win_get_cursor(0)[2] == 6
      end)
    end)
    screen:expect({
      grid = [[
  hello ^world                             |
  ~                                       |
  ~                                       |
  ~                                       |
  ~                                       |
  -- INSERT --                            |
]],
    })
  end)

  it('<m-b> moves backward one word', function()
    -- From the end of "world" (col 11), <m-b> lands on the start
    -- of "world" (col 6), same as standard vim's b.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 11 })
    helpers.feed('a')
    helpers.feed('<m-b>')
    local state = helpers.exec_lua(function()
      vim.wait(50, function()
        return vim.api.nvim_win_get_cursor(0)[2] == 6
      end)
      return {
        cursor = vim.api.nvim_win_get_cursor(0)[2],
      }
    end)
    eq(6, state.cursor)
  end)

  it('<c-w> on an empty line joins with the previous line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', '' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('a')
    helpers.feed('<c-w>')
    screen:expect({
      grid = [[
  hello world^                             |
  ~                                       |
  ~                                       |
  ~                                       |
  ~                                       |
  -- INSERT --                            |
]],
    })
  end)

  it('<c-w> yanks the deleted word into the small-delete register', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 }) -- between "hello" and " world"
    helpers.feed('a')
    helpers.feed('<c-w>')
    local reg = helpers.exec_lua('return vim.fn.getreg("-")')
    eq('hello ', reg)
  end)

  it('<c-w> on a non-empty line-start joins with the previous line', function()
    -- col 0 on line 2 (non-empty): should join into line 1, like
    -- stock Vim's <c-w> / <BS> at the start of a line.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('i<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local lines = helpers.exec_lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    eq(1, #lines)
    eq('abcabc', lines[1])
  end)

  it('<c-w> at EOL with CJK text deletes last word', function()
    -- Regression test: <c-w> at end of line with CJK text should
    -- delete the last word. With space-separated CJK, it deletes
    -- only the last word.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local lines = helpers.exec_lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    eq('你好 ', lines[1])
  end)

  it('<c-w> with CJK + space + ASCII deletes ASCII word', function()
    -- Regression test: <c-w> should delete only the ASCII word,
    -- not the CJK text before the space.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界 h' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local lines = helpers.exec_lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    eq('你好世界 ', lines[1])
  end)

  it('<c-w> twice with CJK + space + ASCII deletes ASCII and trailing CJK token', function()
    -- Regression test: two <c-w> presses should delete the ASCII
    -- word, then the trailing whitespace and the last CJK cjdict
    -- token. <C-w> does not merge consecutive CJK tokens; each
    -- cjdict token is deleted as a separate word.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界 h' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w><C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local lines = helpers.exec_lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    eq('你好', lines[1])
  end)

  it('<c-w> with trailing whitespace deletes word + whitespace', function()
    -- Regression test: <c-w> should skip trailing whitespace and
    -- delete the word before it.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world   ' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local lines = helpers.exec_lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    eq('hello ', lines[1])
  end)

  it('<c-w> with consecutive CJK should delete only one cjdict token', function()
    -- Regression: '你好你好 test' from mid-line deletes only the
    -- second cjdict token (and the preceding space), leaving
    -- '你好 test'. Each cjdict segment is its own <c-w> word.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好你好 test' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 }) -- after first 你好
    helpers.feed('i<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local line = helpers.exec_lua('return vim.api.nvim_get_current_line()')
    eq('你好 test', line)
  end)

  it('<c-w> with 你好你好 should delete only one 你好', function()
    -- Regression: from EOL of '你好你好', <c-w> deletes only the
    -- second cjdict token, leaving '你好'.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('A<C-w>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local line = helpers.exec_lua('return vim.api.nvim_get_current_line()')
    eq('你好', line)
  end)

  it('<c-w> with abc-def should delete only the last word', function()
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

  it('<c-w> with CJK-ASCII mixed respects word boundaries', function()
    -- 你好-a: the '-' is not word-like, so <c-w> deletes only the
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

  it('<m-f> wraps to the next line when there is no next word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 2 })
    helpers.feed('i<m-f>') -- first: stops at EOL
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    helpers.feed('<m-f>') -- second: wraps to next line
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local r = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[1]')
    local c = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[2]')
    eq(2, r)
    eq(0, c)
  end)

  it('<m-b> wraps to the previous line when there is no previous word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('i<m-b>')
    helpers.exec_lua(function()
      vim.wait(50)
    end)
    local r = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[1]')
    local c = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[2]')
    eq(1, r)
    eq(3, c)
  end)
end)
