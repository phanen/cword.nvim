--- @diagnostic disable: undefined-global
-- E2E specs for ZWJ (Zero Width Joiner) sequence handling.
-- ZWJ sequences like 🏴‍☠️ (pirate flag) are composed of multiple codepoints
-- joined by U+200D (ZWJ). Neovim treats them as single grapheme clusters,
-- so motion commands should skip over them entirely.

local helpers = require('test.cword_helpers')
local eq = helpers.eq

describe('ZWJ sequence handling', function()
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
    end)
  end)

  it('w skips over ZWJ sequences', function()
    -- "abc🏴‍☠️def" has tokens: abc, 🏴, ‍ (ZWJ), ☠️, def
    -- w should skip from 'abc' to 'def', treating the ZWJ sequence as one unit
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc🏴‍☠️def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    eq(3, helpers.api.nvim_win_get_cursor(0)[2]) -- lands on 'c'
    helpers.feed('w')
    eq(16, helpers.api.nvim_win_get_cursor(0)[2]) -- skips ZWJ sequence, lands on 'd'
  end)

  it('e skips over ZWJ sequences', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc🏴‍☠️def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('e')
    eq(2, helpers.api.nvim_win_get_cursor(0)[2]) -- end of 'abc'
    helpers.feed('e')
    eq(3, helpers.api.nvim_win_get_cursor(0)[2]) -- start of emoji (ZWJ sequence)
    helpers.feed('e')
    eq(18, helpers.api.nvim_win_get_cursor(0)[2]) -- end of 'def'
  end)

  it('b skips over ZWJ sequences', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc🏴‍☠️def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 18 })
    helpers.feed('b')
    eq(16, helpers.api.nvim_win_get_cursor(0)[2]) -- start of 'def'
    helpers.feed('b')
    eq(3, helpers.api.nvim_win_get_cursor(0)[2]) -- skips ZWJ sequence, lands on 'c'
  end)

  it('ge skips over ZWJ sequences', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc🏴‍☠️def' })
    helpers.api.nvim_win_set_cursor(0, { 1, 18 })
    helpers.feed('ge')
    eq(3, helpers.api.nvim_win_get_cursor(0)[2]) -- end of 'abc' (skips ZWJ)
  end)

  it('w handles ZWJ at end of line', function()
    -- Test with emoji at end: "test🏴‍☠️"
    -- ICU treats this as one token, but nvim sees two grapheme clusters
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'test🏴‍☠️' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    -- Should move to start of emoji (position 4)
    eq(4, helpers.api.nvim_win_get_cursor(0)[2])
  end)

  it('e handles ZWJ at end of line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'test🏴‍☠️' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('e')
    eq(3, helpers.api.nvim_win_get_cursor(0)[2]) -- end of 'test'
    helpers.feed('e')
    -- Should land at start of emoji (ZWJ sequence)
    eq(4, helpers.api.nvim_win_get_cursor(0)[2])
    helpers.feed('e')
    -- Should stay at same position (already at end of line)
    eq(4, helpers.api.nvim_win_get_cursor(0)[2])
  end)

  it('b handles ZWJ at start of line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '🏴‍☠️test' })
    helpers.api.nvim_win_set_cursor(0, { 1, 15 })
    helpers.feed('b')
    -- Should skip over ZWJ sequence and land at start of line
    eq(0, helpers.api.nvim_win_get_cursor(0)[2])
  end)
end)
