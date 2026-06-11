--- @diagnostic disable: undefined-global
local helpers = require('test.cword_helpers')
local eq = helpers.eq

describe('cword.util.iskeyword', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  it('is_keyword returns true for letters under default iskeyword', function()
    local result = helpers.exec_lua(function()
      local ik = require('cword.util.iskeyword')
      return {
        upper = ik.is_keyword(string.byte('A')),
        lower = ik.is_keyword(string.byte('z')),
        digit = ik.is_keyword(string.byte('5')),
        under = ik.is_keyword(string.byte('_')),
        dot = ik.is_keyword(string.byte('.')),
        cjk = ik.is_keyword(0x4F60), -- 你
      }
    end)
    eq(true, result.upper)
    eq(true, result.lower)
    eq(true, result.digit)
    eq(true, result.under)
    eq(false, result.dot)
    eq(true, result.cjk)
  end)

  it('reacts to vim.o.iskeyword changes', function()
    local result = helpers.exec_lua(function()
      local ik = require('cword.util.iskeyword')
      local saved = vim.o.iskeyword
      local before = ik.is_keyword(string.byte('A'))
      vim.o.iskeyword = '48-57,_'
      local after = ik.is_keyword(string.byte('A'))
      local still_digit = ik.is_keyword(string.byte('7'))
      vim.o.iskeyword = saved
      return { before = before, after = after, still_digit = still_digit }
    end)
    eq(true, result.before)
    eq(false, result.after)
    eq(true, result.still_digit)
  end)

  it('recompiles the regex when iskeyword is restored', function()
    local result = helpers.exec_lua(function()
      local ik = require('cword.util.iskeyword')
      local saved = vim.o.iskeyword
      -- Trigger initial compile with the default iskeyword.
      local first = ik.is_keyword(string.byte('A'))
      -- Switch to a restrictive setting: only digits.
      vim.o.iskeyword = '48-57'
      local digits_only = ik.is_keyword(string.byte('A'))
      -- Restore the default.  The cached regex must be recompiled
      -- so 'A' becomes keyword again.
      vim.o.iskeyword = saved
      local restored = ik.is_keyword(string.byte('A'))
      return { first = first, digits_only = digits_only, restored = restored }
    end)
    eq(true, result.first)
    eq(false, result.digits_only)
    eq(true, result.restored)
  end)
end)
