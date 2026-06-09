--- @diagnostic disable: undefined-global
-- Specs for the segmentation API.
-- Run with: busted test/segmenter_spec.lua
-- Or:       make test

local helpers = require('test.cword_helpers')
local Segmenter = require('cword.segmenter')

local eq = helpers.eq
local text_of = helpers.text_of
local slice = helpers.slice

describe('segmenter', function()
  describe('error handling', function()
    it('rejects unknown backend names', function()
      local ok, err = pcall(Segmenter.new, { backend = 'nope' })
      eq(false, ok)
      assert(err:find('nope'), 'error should mention the bad name')
      assert(
        err:find('cjk') and err:find('icu') and err:find('char'),
        'error should list known backends'
      )
    end)
  end)

  describe('backends()', function()
    it('returns the sorted list of registered backend names', function()
      local names = Segmenter.backends()
      eq('char,cjk,icu', table.concat(names, ','))
    end)
  end)
end)

describe('cjk backend', function()
  local seg = Segmenter.new({ backend = 'cjk' })

  describe('basic Chinese', function()
    it('splits 你好 into per-char tokens', function()
      eq('你|好', text_of(seg:cut('你好')))
    end)

    it('splits 你好世界 into per-char tokens', function()
      eq('你|好|世|界', text_of(seg:cut('你好世界')))
    end)

    it('treats CJK punctuation as its own non-word token', function()
      eq('你|好|，|世|界', text_of(seg:cut('你好，世界')))
    end)
  end)

  describe('ASCII', function()
    it('groups letters into one word', function()
      eq('hello', text_of(seg:cut('hello')))
    end)

    it('groups letters and digits via vim iskeyword default', function()
      eq('foo_bar| |123', text_of(seg:cut('foo_bar 123')))
    end)

    it('treats ASCII punctuation as its own non-word token', function()
      eq('foo|.|bar', text_of(seg:cut('foo.bar')))
    end)
  end)

  describe('mixed CJK and ASCII', function()
    it('keeps them separated', function()
      eq('你|好|hello|世|界', text_of(seg:cut('你好hello世界')))
    end)

    it('separates with whitespace', function()
      eq('hi| |你|好', text_of(seg:cut('hi 你好')))
    end)
  end)

  describe('whitespace', function()
    it('collapses consecutive spaces into one token', function()
      local t = seg:cut('a   b')
      eq(3, #t)
      eq('   ', t[2].text)
    end)
  end)

  describe('empty input', function()
    it('returns no tokens for an empty string', function()
      eq('', text_of(seg:cut('')))
    end)
  end)

  describe('byte offsets', function()
    it('reports inclusive 1-indexed ranges for ASCII', function()
      local t = seg:cut('a b')
      eq('1-1', slice(t[1]))
      eq('2-2', slice(t[2]))
      eq('3-3', slice(t[3]))
    end)

    it('reports 3-byte ranges for CJK chars', function()
      local t = seg:cut('你好')
      eq('1-3', slice(t[1]))
      eq('4-6', slice(t[2]))
    end)

    it('roundtrips via string.sub using the reported offsets', function()
      local s = '你好，世界 hello'
      local parts = {}
      for _, tok in ipairs(seg:cut(s)) do
        parts[#parts + 1] = string.sub(s, tok.byte_start, tok.byte_end)
      end
      eq(s, table.concat(parts))
    end)
  end)

  describe('is_word_like', function()
    it('marks CJK chars, ASCII letters, digits, underscore as word-like', function()
      local t = seg:cut('a 你 1 _')
      eq('true', tostring(t[1].is_word_like)) -- a
      eq('true', tostring(t[3].is_word_like)) -- 你
      eq('true', tostring(t[5].is_word_like)) -- 1
      eq('true', tostring(t[7].is_word_like)) -- _
    end)

    it('marks whitespace and punctuation as non-word-like', function()
      local t = seg:cut('a, b.')
      eq(5, #t)
      eq('true', tostring(t[1].is_word_like)) -- a
      eq('false', tostring(t[2].is_word_like)) -- ,
      eq('false', tostring(t[3].is_word_like)) -- ' '
      eq('true', tostring(t[4].is_word_like)) -- b
      eq('false', tostring(t[5].is_word_like)) -- .
    end)
  end)
end)

describe('icu backend', function()
  local seg = Segmenter.new({ backend = 'icu' })

  it('groups consecutive CJK chars into one run', function()
    eq('你好世界', text_of(seg:cut('你好世界')))
  end)

  it('keeps CJK and ASCII runs separated by a script change', function()
    eq('你好|hello|世界', text_of(seg:cut('你好hello世界')))
  end)

  it('breaks on CJK punctuation', function()
    eq('你好|，|世界', text_of(seg:cut('你好，世界')))
  end)

  it('leaves ASCII-only input unchanged from the cjk backend', function()
    eq('hello| |world', text_of(seg:cut('hello world')))
  end)

  it('handles empty input', function()
    eq('', text_of(seg:cut('')))
  end)
end)

describe('char backend', function()
  local seg = Segmenter.new({ backend = 'char' })

  it('emits one token per UTF-8 code point', function()
    eq('你|好', text_of(seg:cut('你好')))
    eq('h|e|l|l|o', text_of(seg:cut('hello')))
  end)

  it('still treats whitespace as non-word-like', function()
    local t = seg:cut('h ')
    eq('false', tostring(t[2].is_word_like))
  end)

  it('handles empty input', function()
    eq('', text_of(seg:cut('')))
  end)
end)

describe('motion stub (phase 2)', function()
  local seg = Segmenter.new({ backend = 'cjk' })
  local Motion = require('cword.motion')
  local motion = Motion.new({ segmenter = seg })

  it('raises on forward() until phase 2 lands', function()
    local ok = pcall(function()
      motion:forward('hello', 1)
    end)
    eq(false, ok)
  end)

  it('raises on backward() until phase 2 lands', function()
    local ok = pcall(function()
      motion:backward('hello', 1)
    end)
    eq(false, ok)
  end)

  it('requires a segmenter at construction time', function()
    local ok, err = pcall(Motion.new, {})
    eq(false, ok)
    assert(err:find('segmenter'), 'error should mention segmenter')
  end)
end)
