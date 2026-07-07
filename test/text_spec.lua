--- @diagnostic disable: undefined-global
local helpers = require('test.cword_helpers')
local eq = helpers.eq

describe('cword.util.text', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  local function call_char_start(line, col)
    return helpers.exec_lua(function(l, c)
      return require('cword.util.text').char_start(l, c)
    end, line, col)
  end

  local function call_char_end(line, col, max_col)
    return helpers.exec_lua(function(l, c, m)
      return require('cword.util.text').char_end(l, c, m)
    end, line, col, max_col)
  end

  describe('char_start', function()
    it('returns the same column on a char boundary', function()
      eq(1, call_char_start('abc', 1))
      eq(2, call_char_start('abc', 2))
      eq(3, call_char_start('abc', 3))
    end)

    it('snaps backward through continuation bytes to the lead byte', function()
      -- "a✓b": 'a'=1, ✓=E2 9A 9C at 2-4, 'b'=5
      eq(2, call_char_start('a✓b', 3))
      eq(2, call_char_start('a✓b', 4))
    end)

    it('walks back through several multi-byte chars', function()
      -- "✓✓": bytes 1=E2 9A 9C, 4=E2 9A 9C; cursor at byte 5 is past EOL
      eq(4, call_char_start('✓✓', 5))
      eq(1, call_char_start('✓✓', 2))
    end)

    it('returns 0 when col is before any lead byte', function()
      eq(0, call_char_start('✓', 0))
    end)
  end)

  describe('char_end', function()
    it('returns the same column on a char boundary', function()
      eq(1, call_char_end('abc', 1, 3))
      eq(2, call_char_end('abc', 2, 3))
      eq(3, call_char_end('abc', 3, 3))
    end)

    it('snaps forward through continuation bytes to the next lead byte', function()
      -- "a✓b": bytes 1='a', 2=E2 9A 9C (✓), 5='b'; cursor at byte 3
      -- (continuation) snaps to byte 5 (next lead byte).
      eq(5, call_char_end('a✓b', 3, 5))
      eq(5, call_char_end('a✓b', 4, 5))
    end)

    it('caps at max_col + 1 when stuck in trailing continuation bytes', function()
      -- col past EOL returns col itself
      eq(6, call_char_end('a✓b', 6, 5))
    end)
  end)

  describe('is_whitespace', function()
    local function call_is_whitespace(text)
      return helpers.exec_lua(function(t)
        return require('cword.util.text').is_whitespace({ text = t })
      end, text)
    end

    it('is true for whitespace-only tokens', function()
      eq(true, call_is_whitespace(' '))
      eq(true, call_is_whitespace('   '))
      eq(true, call_is_whitespace('\t'))
    end)

    it('is false for tokens with non-whitespace content', function()
      eq(false, call_is_whitespace('a'))
      eq(false, call_is_whitespace(' a'))
      eq(false, call_is_whitespace(''))
    end)
  end)
end)
