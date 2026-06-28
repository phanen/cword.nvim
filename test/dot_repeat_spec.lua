--- @diagnostic disable: undefined-global
local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

describe('dot-repeat for operator-pending motions', function()
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
      vim.keymap.set({ 'n', 'x' }, 'e', m.move_end_forward, opts)
      vim.keymap.set({ 'n', 'x' }, 'ge', m.move_end_backward, opts)
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

  -- dw repeated

  it('dw . on ASCII deletes two words', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar baz qux' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    helpers.exec_lua('vim.wait(50)')
    eq('bar baz qux', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq('baz qux', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  it('dw . . on ASCII deletes three words', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'aa bb cc dd' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    helpers.exec_lua('vim.wait(50)')
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq('dd', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  it('dw . on uneven word lengths', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'aaaa bbb cc d' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    helpers.exec_lua('vim.wait(50)')
    eq('bbb cc d', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq('cc d', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq('d', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  -- de repeated -- the dot-repeat must recompute the visual range,
  -- not replay stale coordinates from the first call

  it('de . on ASCII deletes two end-of-words', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar baz qux' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    helpers.exec_lua('vim.wait(50)')
    eq(' bar baz qux', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq(' baz qux', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  it('de . . . on uneven word lengths (matches stock nvim)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'aaaa bbb cc d' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    helpers.exec_lua('vim.wait(50)')
    eq(' bbb cc d', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq(' cc d', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq(' d', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  -- dw + move + .

  it('dw then w then . advances forward correctly', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo bar baz qux' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    helpers.exec_lua('vim.wait(50)')
    helpers.feed('w')
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq('bar qux', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  -- CJK cases

  it('dw . on CJK merged', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 世界 你好 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('dw')
    helpers.exec_lua('vim.wait(50)')
    eq('世界 你好 世界', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq('你好 世界', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  it('de . on CJK merged (matches stock nvim)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 世界 你好 世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('de')
    helpers.exec_lua('vim.wait(50)')
    eq(' 世界 你好 世界', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq(' 你好 世界', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    eq(' 世界', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)

  -- count is preserved on dot-repeat (matches stock nvim)

  it('d2w then . repeats the count (matches stock nvim)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'aa bb cc dd ee' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('d2w')
    helpers.exec_lua('vim.wait(50)')
    eq('cc dd ee', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
    helpers.feed('.')
    helpers.exec_lua('vim.wait(50)')
    -- Stock nvim: `.` repeats the whole change including count, so
    -- `d2w.` deletes 2 words. Verify our refactor matches.
    eq('ee', helpers.api.nvim_buf_get_lines(0, 0, -1, false)[1])
  end)
end)
