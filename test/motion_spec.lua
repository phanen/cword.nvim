--- @diagnostic disable: undefined-global
-- Motion specs. Algorithm specs are pure Lua. E2E specs run under
-- nvim-test: setup() must be invoked inside helpers.exec_lua so its
-- callback closures stay in nvim's Lua context (msgpack cannot
-- serialize them).

local helpers = require('test.cword_helpers')
local Segmenter = require('cword.segmenter')
local motion = require('cword.motion')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

local function seg(backend)
  return Segmenter.new({ backend = backend })
end

-- byte offsets for the test strings below:
--   '你好世界'      你 1-3   好 4-6   世 7-9   界 10-12   (length 12)
--   '你 好'        你 1-3   ' ' 4    好 5-7              (length 7)
--   '你，世界'     你 1-3   ， 4-6   世 7-9   界 10-12   (length 12)
--   '你hi'         你 1-3   h 4   i 5                    (length 5)
--   'hi你'         h 1   i 2   你 3-5                    (length 5)
--   'hello'        hello 1-5                              (length 5)
--   'hello world'  hello 1-5   ' ' 6   world 7-11         (length 11)
--   'hi world'     hi 1-2   ' ' 3   world 4-8            (length 8)
--   '你 ，世'      你 1-3   ' ' 4   ， 5-7   世 8-10     (length 10)
--   '你，世'       你 1-3   ， 4-6   世 7-9               (length 9)
--   '你好hello世界' 你 1-3   好 4-6   hello 7-11   世 12-14   界 15-17

describe('motion algorithm (cjk backend)', function()
  local s = seg('cjk')

  describe('forward', function()
    it('jumps one CJK char at a time', function()
      eq(4, motion.forward(s, '你好世界', 1))
      eq(7, motion.forward(s, '你好世界', 4))
      eq(10, motion.forward(s, '你好世界', 7))
    end)

    it('jumps across whitespace and CJK punctuation', function()
      eq(5, motion.forward(s, '你 好', 1))
      eq(7, motion.forward(s, '你，世界', 1))
    end)

    it('jumps across script change', function()
      eq(4, motion.forward(s, '你hi', 1))
      eq(3, motion.forward(s, 'hi你', 2))
    end)

    it('clamps to end of line when no next word', function()
      eq(12, motion.forward(s, '你好世界', 12))
      eq(5, motion.forward(s, 'hello', 5))
    end)

    it('handles cursor at end of word', function()
      eq(4, motion.forward(s, '你好世界', 3))
    end)

    it('handles empty line', function()
      eq(0, motion.forward(s, '', 1))
    end)

    it('mixed CJK and ASCII', function()
      eq(4, motion.forward(s, '你好hello世界', 1))
      eq(7, motion.forward(s, '你好hello世界', 6))
      eq(12, motion.forward(s, '你好hello世界', 11))
    end)
  end)

  describe('backward', function()
    it('jumps to previous CJK char', function()
      eq(1, motion.backward(s, '你好世界', 4))
      eq(4, motion.backward(s, '你好世界', 7))
    end)

    it('returns start of current word when cursor is inside it', function()
      eq(4, motion.backward(s, '你好世界', 6))
    end)

    it('returns start of previous word when cursor at start of word', function()
      eq(1, motion.backward(s, '你好世界', 4))
    end)

    it('skips whitespace and punctuation', function()
      eq(1, motion.backward(s, '你 ，世', 8))
      eq(1, motion.backward(s, '你，世', 7))
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, motion.backward(s, '你好', 1))
    end)
  end)

  describe('end_forward', function()
    it('jumps to end of current word', function()
      eq(3, motion.end_forward(s, '你好世界', 1))
      eq(6, motion.end_forward(s, '你好世界', 4))
    end)

    it('skips to next word end when cursor at end of current', function()
      eq(6, motion.end_forward(s, '你好世界', 3))
      eq(2, motion.end_forward(s, 'hi world', 1))
    end)

    it('clamps to end of line when no next word', function()
      eq(12, motion.end_forward(s, '你好世界', 12))
    end)
  end)

  describe('end_backward', function()
    it('jumps to end of previous word', function()
      eq(3, motion.end_backward(s, '你好世界', 4))
    end)

    it('handles cursor inside word', function()
      eq(3, motion.end_backward(s, '你好世界', 5))
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, motion.end_backward(s, '你好', 1))
    end)
  end)

  describe('ASCII words', function()
    it('treats ASCII identifiers as single words', function()
      eq(7, motion.forward(s, 'hello world', 1))
      eq(1, motion.backward(s, 'hello world', 7))
      eq(5, motion.end_forward(s, 'hello world', 1))
    end)
  end)
end)

describe('motion algorithm (icu_ffi backend)', function()
  local ok_ffi, _ = pcall(require, 'cword.backends.icu_ffi')
  if not ok_ffi then
    return
  end
  local s = seg('icu_ffi')

  it('dictionary merges break into multiple runs', function()
    -- icu_ffi segments 你好世界 as [你好, 世界], so forward from 1
    -- jumps to byte 7 (start of 世界), not 12 (end of line).
    eq(7, motion.forward(s, '你好世界', 1))
    eq(7, motion.forward(s, '你好世界', 6))
  end)

  it('still jumps across runs via whitespace', function()
    eq(8, motion.forward(s, '你好 world', 1))
  end)
end)

describe('motion e2e (cjk backend)', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      require('cword').setup({ backend = 'cjk' })
    end)
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  local function put(text)
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { text })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  it('w jumps one CJK char', function()
    put('你好世界')
    helpers.feed('w')
    screen:expect({
      grid = [[
  你^好世界                                |
  ~                                       |
  ~                                       |
                                          |
]],
    })
  end)

  it('w jumps one ASCII word', function()
    put('hi你好')
    helpers.feed('w')
    screen:expect({
      grid = [[
  hi^你好                                  |
  ~                                       |
  ~                                       |
                                          |
]],
    })
  end)
end)
