--- @diagnostic disable: undefined-global
-- E2E specs for operator-pending, insert, and command-line mode.

local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

describe('operator-pending mode', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      require('cword').setup({ backend = 'cjk' })
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
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('cw')
    eq('好我', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    local mode = helpers.exec_lua('return vim.api.nvim_get_mode().mode')
    eq('i', mode:sub(1, 1))
  end)

  it('db deletes previous word on ASCII', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar baz' })
    helpers.api.nvim_win_set_cursor(0, { 1, 8 })
    helpers.feed('db')
    eq('foo baz', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('db deletes a CJK char', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('db')
    eq('你我', helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('yw yanks word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('yw')
    local reg = helpers.exec_lua('return vim.fn.getreg("0")')
    eq('hello ', reg)
  end)

  it('dw wraps across newlines and keeps the next line intact', function()
    -- The visual-mode-based implementation had an off-by-one on
    -- cross-line wrap because nvim_win_set_cursor is "on the char"
    -- while Vim's `v` is "between chars"; computing the range via
    -- nvim_buf_set_text makes the wrap end at the start of the
    -- next line, not on its first character.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', 'world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('world', lines[1])
  end)

  it('dw wraps across an empty line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', '', 'next' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('next', lines[1])
  end)

  it('dw on a single-word last line deletes the whole line', function()
    -- `dw` at end of input must still eat the trailing word; the
    -- old visual-mode path deleted one byte too few because e_col
    -- was clamped to c-2.
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

  it('d3w across multiple lines lands on the third word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo', 'bar', 'baz' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('d3w')
    local lines = helpers.api.nvim_buf_get_lines(0, 0, -1, false)
    eq(1, #lines)
    eq('baz', lines[1])
  end)
end)

describe('insert mode', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup({ backend = 'cjk' })
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

  it('<c-w> deletes word backward', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 10 })
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

  it('<m-f> moves forward one word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('i')
    helpers.feed('<m-f>')
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
end)

describe('command-line mode', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  it('exposes cmdline_forward/backward/delete_word handlers', function()
    local cword = helpers.exec_lua(function()
      local m = require('cword')
      m.setup()
      return {
        cf = type(m.cmdline_forward),
        cb = type(m.cmdline_backward),
        cd = type(m.cmdline_delete_word),
      }
    end)
    eq('function', cword.cf)
    eq('function', cword.cb)
    eq('function', cword.cd)
  end)
end)
