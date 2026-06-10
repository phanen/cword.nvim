--- @diagnostic disable: undefined-global
-- E2E specs for operator-pending and insert mode.

local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

describe('operator-pending mode', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup({ backend = 'cjk' })
      local opts = { noremap = true, silent = true }
      vim.keymap.set({ 'n', 'x' }, 'w', cword.move_forward, opts)
      vim.keymap.set({ 'n', 'x' }, 'b', cword.move_backward, opts)
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

  it('yw yanks word', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('yw')
    local reg = helpers.exec_lua('return vim.fn.getreg("0")')
    eq('hello ', reg)
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
    helpers.feed('a') -- append after cursor (cursor after 'd')
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

describe('direct operators', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      require('cword').setup({ backend = 'cjk' })
      vim.keymap.set('n', 'dw', require('cword').delete_forward, { noremap = true, silent = true })
      vim.keymap.set(
        'n',
        'de',
        require('cword').delete_end_forward,
        { noremap = true, silent = true }
      )
      vim.keymap.set('n', 'cw', require('cword').change_forward, { noremap = true, silent = true })
      vim.keymap.set(
        'n',
        'ce',
        require('cword').change_end_forward,
        { noremap = true, silent = true }
      )
      vim.keymap.set('n', 'db', require('cword').delete_backward, { noremap = true, silent = true })
    end)
  end)

  it('dw deletes word on CJK', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('dw')
    local line = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    eq('你好', line)
  end)

  it('de deletes to end of word on CJK', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好我' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 })
    helpers.feed('de')
    local line = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    eq('你好', line)
  end)

  it('dw deletes word on ASCII', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    local line = helpers.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    eq('world', line)
  end)
end)
