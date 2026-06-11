--- @diagnostic disable: undefined-global
-- Command-line mode handlers. The motion logic is covered by
-- motion_spec.lua; here we verify the handlers exist and that
-- cmdline_delete_word can modify the cmdline via setcmdline.

local helpers = require('test.cword_helpers')
local eq = helpers.eq

describe('command-line mode', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

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

  it('cmdline_delete_word cuts the word before cursor (setcmdline works)', function()
    -- setcmdpos does not stick inside CmdlineEnter (neovim
    -- limitation), but setcmdline DOES. From the end of "ab|cd"
    -- (pos=5, the cursor position after setcmdline), backward
    -- lands on the start of "abcd" (byte_start=1), so the
    -- handler deletes the whole word.
    local r = helpers.exec_lua(function()
      local m = require('cword')
      m.setup({ backend = 'icu_ffi' })
      local result, done = nil, false
      vim.api.nvim_create_autocmd('CmdlineEnter', {
        once = true,
        callback = function()
          vim.fn.setcmdline('hello world')
          m.cmdline_delete_word()
          result = { line = vim.fn.getcmdline() }
          done = true
        end,
      })
      vim.api.nvim_feedkeys(':', 'nx', false)
      vim.wait(99, function()
        return done
      end)
      return result
    end)
    -- From the end of "hello world", backward returns 7
    -- (start of "世界" in icu_ffi terms — actually "world"
    -- for Latin). setcmdline("hello ") — deletes "world".
    -- But actually backward from pos=12 (end) on "hello world":
    -- tokens: hello(1-5), ' '(6), world(7-11).
    -- backward(12): tokens with byte_start < 12 — all. last
    -- non-ws: world(7). prev=world. cursor=12 <= 11? No.
    -- Return 7. setcmdline(line:sub(1,6) .. line:sub(12))
    -- = "hello " .. "" = "hello ".
    eq('hello ', r.line)
  end)
end)
