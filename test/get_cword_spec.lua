--- @diagnostic disable: undefined-global
-- Phase 2: get_cword reads the cursor and the current line.

local helpers = require('test.cword_helpers')

local eq = helpers.eq

local function put_at(line, row, col)
  helpers.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  helpers.api.nvim_win_set_cursor(0, { row, col })
end

local function get_cword()
  return helpers.exec_lua(function()
    return require('cword').get_cword()
  end)
end

local function get_token()
  return helpers.exec_lua(function()
    return require('cword').get_token()
  end)
end

describe('cword.get_cword (CJK-aware <cword>)', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  describe('ASCII', function()
    it('returns the identifier under the cursor', function()
      put_at('hello world', 1, 0)
      eq('hello', get_cword())
    end)

    it('returns the next identifier from its first byte', function()
      put_at('hello world', 1, 6)
      eq('world', get_cword())
    end)
  end)

  describe('CJK', function()
    it('returns the merged run from its first byte', function()
      put_at('你好世界', 1, 0)
      eq('你好', get_cword())
    end)

    it('returns the merged run from a middle byte', function()
      put_at('你好世界', 1, 3)
      eq('你好', get_cword())
    end)

    it('returns the second run from its first byte', function()
      put_at('你好世界', 1, 6)
      eq('世界', get_cword())
    end)
  end)

  describe('mixed', function()
    it('returns the ASCII word', function()
      put_at('hello 世界', 1, 0)
      eq('hello', get_cword())
    end)

    it('returns the CJK run', function()
      put_at('hello 世界', 1, 6)
      eq('世界', get_cword())
    end)
  end)

  describe('non-word positions', function()
    it('returns "" on ASCII whitespace', function()
      put_at('hello world', 1, 5)
      eq('', get_cword())
    end)

    it('returns "" on CJK punctuation', function()
      put_at('你好，世界', 1, 6)
      eq('', get_cword())
    end)

    it('returns "" on a non-word non-whitespace token', function()
      put_at('a -> b', 1, 2)
      eq('', get_cword())
    end)
  end)

  describe('end-of-line', function()
    it('returns the word when cursor is one cell past the last byte', function()
      put_at('hello', 1, 5)
      eq('hello', get_cword())
    end)

    it('returns "" when the line ends on whitespace', function()
      put_at('hello ', 1, 6)
      eq('', get_cword())
    end)

    it('returns the last CJK run past its last byte', function()
      put_at('你好世界', 1, 12)
      eq('世界', get_cword())
    end)
  end)

  describe('empty line', function()
    it('returns ""', function()
      put_at('', 1, 0)
      eq('', get_cword())
    end)
  end)
end)

describe('cword.get_token', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  it('returns full token info for an ASCII word', function()
    put_at('hello world', 1, 0)
    local tok = get_token()
    eq('hello', tok.text)
    eq(1, tok.byte_start)
    eq(5, tok.byte_end)
    eq(true, tok.is_word_like)
  end)

  it('returns nil on whitespace', function()
    put_at('hello world', 1, 5)
    assert.is_nil(get_token())
  end)

  it('reports UTF-8 byte offsets for a CJK run', function()
    put_at('你好世界', 1, 3)
    local tok = get_token()
    eq('你好', tok.text)
    eq(1, tok.byte_start)
    eq(6, tok.byte_end)
    eq(true, tok.is_word_like)
  end)
end)
