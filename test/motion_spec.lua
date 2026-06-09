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
--   'pkgs.hello.out' pkgs 1-4  . 5  hello 6-10  . 11  out 12-14

describe('motion algorithm (cjk backend)', function()
  local s = seg('cjk')

  describe('forward', function()
    it('jumps one CJK char at a time', function()
      eq(4, motion.forward(s, '你好世界', 1))
      eq(7, motion.forward(s, '你好世界', 4))
      eq(10, motion.forward(s, '你好世界', 7))
    end)

    it('stops at CJK punctuation (non-word, non-space)', function()
      eq(5, motion.forward(s, '你 好', 1)) -- skip space to 好
      eq(4, motion.forward(s, '你，世界', 1)) -- 你 -> ，
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

    it('stops at non-iskeyword boundaries', function()
      eq(5, motion.forward(s, 'pkgs.hello.out', 1)) -- p -> .
      eq(6, motion.forward(s, 'pkgs.hello.out', 5)) -- . -> h
      eq(11, motion.forward(s, 'pkgs.hello.out', 6)) -- h -> .
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

    it('returns start of preceding token when at start of word', function()
      eq(1, motion.backward(s, '你好世界', 4))
    end)

    it('goes back to non-word token at boundary', function()
      eq(4, motion.backward(s, '你，世', 7)) -- 世 -> ，
      eq(5, motion.backward(s, '你 ，世', 8)) -- 世 -> ， (space between)
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, motion.backward(s, '你好', 1))
    end)

    it('stops at non-iskeyword boundaries', function()
      eq(1, motion.backward(s, 'pkgs.hello.out', 5)) -- . -> p (pkgs start)
    end)
  end)

  describe('end_forward', function()
    it('jumps to end of current word', function()
      eq(4, motion.end_forward(s, '你好世界', 1))
      eq(7, motion.end_forward(s, '你好世界', 4))
    end)

    it('skips to next word end when cursor at end of current', function()
      eq(7, motion.end_forward(s, '你好世界', 3))
      eq(3, motion.end_forward(s, 'hi world', 1))
    end)

    it('clamps to end of line when no next word', function()
      eq(13, motion.end_forward(s, '你好世界', 12))
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
      eq(6, motion.end_forward(s, 'hello world', 1))
    end)
  end)
end)

describe('motion algorithm (icu_ffi backend)', function()
  local ok_ffi, _ = pcall(require, 'cword.backends.icu_ffi')
  if not ok_ffi then
    return
  end

  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  local function fwd(str, cursor)
    return helpers.exec_lua(function(s, c)
      local Segmenter = require('cword.segmenter')
      local motion = require('cword.motion')
      local seg = Segmenter.new({ backend = 'icu_ffi' })
      return motion.forward(seg, s, c)
    end, str, cursor)
  end

  it('dictionary merges break into multiple runs', function()
    eq(7, fwd('你好世界', 1))
    eq(7, fwd('你好世界', 6))
  end)

  it('still jumps across runs via whitespace', function()
    eq(8, fwd('你好 world', 1))
  end)
end)

describe('motion e2e (cjk backend)', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup({ backend = 'cjk' })
      vim.keymap.set({ 'n', 'x' }, 'w', cword.move_forward, { noremap = true, silent = true })
      vim.keymap.set({ 'n', 'x' }, 'b', cword.move_backward, { noremap = true, silent = true })
      vim.keymap.set({ 'n', 'x' }, 'e', cword.move_end_forward, { noremap = true, silent = true })
      vim.keymap.set({ 'n', 'x' }, 'ge', cword.move_end_backward, { noremap = true, silent = true })
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

  it('w wraps past the end of a line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'next line here' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    screen:expect({
      grid = [[
  hello ^world                             |
  next line here                          |
  ~                                       |
                                          |
]],
    })
  end)

  it('w stops at the start of an empty line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', '', 'next' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    screen:expect({
      grid = [[
  hello                                   |
  ^                                        |
  next                                    |
                                          |
]],
    })
  end)

  it('b wraps into the previous line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('b')
    screen:expect({
      grid = [[
  hello worl^d                             |
  foo bar                                 |
  ~                                       |
                                          |
]],
    })
  end)

  it('3w repeats the motion', function()
    put('你好世界')
    helpers.feed('3w')
    screen:expect({
      grid = [[
  你好世^界                                |
  ~                                       |
  ~                                       |
                                          |
]],
    })
  end)

  it('vw extends visual selection to the next word', function()
    put('你好世界')
    helpers.feed('v')
    helpers.feed('w')
    screen:expect({
      grid = [[
  你^好世界                                |
  ~                                       |
  ~                                       |
  -- VISUAL --                            |
]],
    })
  end)
end)
