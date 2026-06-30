--- @diagnostic disable: undefined-global
-- Specs for the segmentation API.
-- Run with: busted test/segmenter_spec.lua
-- Or:       make test

local helpers = require('test.cword_helpers')

local eq = helpers.eq
local text_of = helpers.text_of

describe('icu_ffi segmentation (real ICU via libicuuc FFI)', function()
  -- Skip on systems without libicuuc; the load would fail.
  local ok, _ = pcall(require, 'cword.segmenter')
  if not ok then
    return
  end

  it('auto-detects the loaded ICU major version', function()
    local Segmenter = require('cword.segmenter')
    eq('number', type(Segmenter._icu_version))
    assert(
      Segmenter._icu_version >= 50 and Segmenter._icu_version <= 80,
      'detected icu version looks implausible: ' .. tostring(Segmenter._icu_version)
    )
  end)

  describe('segmentation (executed in target nvim via exec_lua)', function()
    before_each(function()
      helpers.clear()
      helpers.setup_path()
    end)

    local function cut_ffi(str)
      return helpers.exec_lua(function(s)
        return require('cword.segmenter').cut(s)
      end, str)
    end

    it('matches JS Intl.Segmenter for cjdict merges', function()
      eq('你好|世界', text_of(cut_ffi('你好世界')))
    end)

    it('uses Viterbi DP for ambiguous Chinese strings', function()
      eq('南京市|长江|大|桥', text_of(cut_ffi('南京市长江大桥')))
    end)

    it('handles script change across whitespace', function()
      eq('你好| |hello', text_of(cut_ffi('你好 hello')))
    end)

    it('breaks CJK punctuation as a non-word token', function()
      eq('你好|，|世界', text_of(cut_ffi('你好，世界')))
    end)

    it('handles empty input', function()
      eq('', text_of(cut_ffi('')))
    end)

    it('reports byte offsets in UTF-8 (not UTF-16 code units)', function()
      local t = cut_ffi('你好世界')
      eq(1, t[1].byte_start)
      eq(6, t[1].byte_end)
      eq(7, t[2].byte_start)
      eq(12, t[2].byte_end)
    end)

    it('roundtrips via string.sub using the reported byte offsets', function()
      local s = '南京市长江大桥'
      local parts = {}
      local t = cut_ffi(s)
      for _, tok in ipairs(t) do
        parts[#parts + 1] = string.sub(s, tok.byte_start, tok.byte_end)
      end
      eq(s, table.concat(parts))
    end)

    it('splits on non-iskeyword characters (respects iskeyword)', function()
      local t = cut_ffi('pkgs.hello.out')
      eq(5, #t)
      eq('pkgs', t[1].text)
      eq(true, t[1].is_word_like)
      eq('.', t[2].text)
      eq(false, t[2].is_word_like)
      eq('hello', t[3].text)
      eq(true, t[3].is_word_like)
      eq('.', t[4].text)
      eq(false, t[4].is_word_like)
      eq('out', t[5].text)
      eq(true, t[5].is_word_like)
    end)
  end)
end)

describe('motion module surface', function()
  it('exposes four pure functions for word motion', function()
    local motion = require('cword.motion')
    eq('function', type(motion.forward))
    eq('function', type(motion.backward))
    eq('function', type(motion.end_forward))
    eq('function', type(motion.end_backward))
  end)
end)
