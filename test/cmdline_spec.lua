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

  it('c-w at EOL with CJK text deletes last word', function()
    -- Regression test: <c-w> at end of cmdline with CJK text should
    -- delete only the last word, not the entire line.
    helpers.feed(':你好世界')
    helpers.feed('<c-w>')
    expect_cmdline('你好', 6)
  end)

  it('c-w with CJK + space + ASCII deletes ASCII word', function()
    -- Regression test: <c-w> should delete only the ASCII word,
    -- not the CJK text before the space.
    helpers.feed(':你好世界 h')
    helpers.feed('<c-w>')
    expect_cmdline('你好世界 ', 13)
  end)

  it('c-w with trailing whitespace deletes word + whitespace', function()
    -- Regression test: <c-w> should skip trailing whitespace and
    -- delete the word before it.
    helpers.feed(':hello world   ')
    helpers.feed('<c-w>')
    expect_cmdline('hello ', 6)
  end)
end)
