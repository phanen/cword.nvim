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
end)
