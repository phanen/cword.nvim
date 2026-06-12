--- @diagnostic disable: undefined-global
local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')
local eq = helpers.eq

describe('command-line mode', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local m = require('cword')
      m.setup()
      local opts = { noremap = true, silent = true }
      vim.keymap.set('c', '<m-f>', function()
        m.cmdline_forward()
        return ''
      end, vim.tbl_extend('force', opts, { expr = true }))
      vim.keymap.set('c', '<m-b>', function()
        m.cmdline_backward()
        return ''
      end, vim.tbl_extend('force', opts, { expr = true }))
      vim.keymap.set('c', '<c-w>', function()
        m.cmdline_delete_word()
        return ''
      end, vim.tbl_extend('force', opts, { expr = true }))
    end)
    screen = Screen.new(40, 6)
    screen:attach()
    screen:set_option('ext_cmdline', true)
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  local function expect_cmdline(text, pos)
    screen:expect({
      cmdline = { { firstc = ':', content = { { text } }, pos = pos } },
    })
  end

  it('exposes the three cmdline handlers', function()
    local cword = helpers.exec_lua(function()
      local m = require('cword')
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

  it('alt-f moves to the next word', function()
    helpers.feed(':hello world')
    helpers.feed('<Home>')
    helpers.feed('<m-f>')
    expect_cmdline('hello world', 6)
  end)

  it('alt-b moves to the previous word from the end', function()
    helpers.feed(':hello world')
    helpers.feed('<Home>')
    helpers.feed('<m-f>')
    helpers.feed('<m-b>')
    expect_cmdline('hello world', 0)
  end)

  it('alt-b from the start of a word lands on the previous word', function()
    helpers.feed(':hello world')
    helpers.feed('<m-b>')
    expect_cmdline('hello world', 6)
  end)

  it('c-w deletes the word before cursor and keeps cursor at the boundary', function()
    helpers.feed(':abcd')
    helpers.feed('<Left><Left>')
    helpers.feed('<c-w>')
    expect_cmdline('cd', 0)
  end)
end)
