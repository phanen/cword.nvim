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
      cword.setup({ backend = 'icu_ffi' })
      local opts = { noremap = true, silent = true }
      -- expr = true: the handler's side effects (moving the
      -- cursor via nvim_win_set_cursor / nvim_buf_set_text) are
      -- the only thing that should happen. Without expr, the
      -- typed key still runs the default insert-mode binding on
      -- top of our work, which double-deletes for <c-w>.
      vim.keymap.set(
        'i',
        '<m-f>',
        cword.insert_forward,
        vim.tbl_extend('force', opts, { expr = true })
      )
      vim.keymap.set(
        'i',
        '<m-b>',
        cword.insert_backward,
        vim.tbl_extend('force', opts, { expr = true })
      )
      vim.keymap.set(
        'i',
        '<c-w>',
        cword.insert_delete_word,
        vim.tbl_extend('force', opts, { expr = true })
      )
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

  it('<c-w> in the middle of a line deletes word + trailing space', function()
    -- "hello| world" -> c-w -> "world". Vim's built-in <c-w>
    -- in insert mode eats the word before the cursor plus any
    -- whitespace immediately after; the cursor lands at the
    -- start of the surviving text (NOT at the end). The cword
    -- handler matches that contract.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 }) -- between "hello" and " world"
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
end)
