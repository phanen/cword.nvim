--- @diagnostic disable: undefined-global
-- iskeyword parse + predicate. The parse is deliberately NOT
-- run at module load (see lua/cword/util/iskeyword.lua), so all
-- assertions here go through `helpers.exec_lua` to exercise the
-- module inside a real Neovim where `vim.o.iskeyword` is live.
local helpers = require('test.cword_helpers')
local eq = helpers.eq

describe('cword.util.iskeyword', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  it('parses the default iskeyword into alpha + range rules', function()
    local rules = helpers.exec_lua(function()
      return require('cword.util.iskeyword').parse('@,48-57,_,192-255')
    end)
    eq('alpha', rules[1].kind)
    eq('range', rules[2].kind)
    eq(48, rules[2].lo)
    eq(57, rules[2].hi)
    eq('range', rules[3].kind)
    eq(95, rules[3].lo) -- '_'
    eq(95, rules[3].hi)
  end)

  it('parses a single codepoint segment as a one-byte range', function()
    local rules = helpers.exec_lua(function()
      return require('cword.util.iskeyword').parse('a,7')
    end)
    eq('range', rules[1].kind)
    eq(97, rules[1].lo) -- 'a'
    eq(97, rules[1].hi)
    eq('range', rules[2].kind)
    eq(55, rules[2].lo) -- '7'
    eq(55, rules[2].hi)
  end)

  it('expands a multi-codepoint segment into one rule per byte', function()
    -- Vim's iskeyword can hold several literal bytes in one
    -- comma segment; each byte becomes its own range rule.
    local rules = helpers.exec_lua(function()
      return require('cword.util.iskeyword').parse('ab')
    end)
    eq(2, #rules)
    eq(97, rules[1].lo)
    eq(97, rules[1].hi)
    eq(98, rules[2].lo)
    eq(98, rules[2].hi)
  end)

  it('treats empty input as no rules', function()
    local rules = helpers.exec_lua(function()
      return require('cword.util.iskeyword').parse('')
    end)
    eq(0, #rules)
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

  it('reacts to vim.o.iskeyword changes without a reload hook', function()
    local result = helpers.exec_lua(function()
      local ik = require('cword.util.iskeyword')
      local saved = vim.o.iskeyword
      -- Default: @,48-57,_,192-255 → letters are keyword.
      local before = ik.is_keyword(string.byte('A'))
      -- Tighten to digits + underscore only: letters no longer hit.
      vim.o.iskeyword = '48-57,_'
      local after = ik.is_keyword(string.byte('A'))
      local still_digit = ik.is_keyword(string.byte('7'))
      -- Restore so other specs in the same nvim run keep working.
      vim.o.iskeyword = saved
      return { before = before, after = after, still_digit = still_digit }
    end)
    eq(true, result.before)
    eq(false, result.after)
    eq(true, result.still_digit)
  end)
end)
