--- @diagnostic disable: undefined-global
-- Motion specs. Algorithm specs are pure Lua. E2E specs run under
-- nvim-test: setup() must be invoked inside helpers.exec_lua so its
-- callback closures stay in nvim's Lua context (msgpack cannot
-- serialize them).
--
-- byte offsets for the test strings below (icu_ffi tokens):
--   '你好世界'      你好 1-6  世界 7-12  (length 12)
--   '你 好'        你 1-3  ' ' 4  好 5-7  (length 7)
--   '你，世界'     你 1-3  ， 4-6  世界 7-9  (length 9)
--   '你hi'         你 1-3  hi 4-5  (length 5)
--   'hi你'         hi 1-2  你 3-5  (length 5)
--   'hello'        hello 1-5  (length 5)
--   'hello world'  hello 1-5  ' ' 6  world 7-11  (length 11)
--   'hi world'     hi 1-2  ' ' 3  world 4-8  (length 8)
--   '你 ，世'      你 1-3  ' ' 4  ， 5-7  世 8-10  (length 10)
--   '你好hello世界' 你好 1-6  hello 7-11  世界 12-17  (length 17)
--   'pkgs.hello.out' pkgs 1-4  . 5  hello 6-10  . 11  out 12-14

local helpers = require('test.cword_helpers')
local Segmenter = require('cword.segmenter')
local motion = require('cword.motion')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

local function seg(backend)
  return Segmenter.new({ backend = backend })
end

describe('motion algorithm (icu_ffi backend)', function()
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

  local function bwd(str, cursor)
    return helpers.exec_lua(function(s, c)
      local Segmenter = require('cword.segmenter')
      local motion = require('cword.motion')
      local seg = Segmenter.new({ backend = 'icu_ffi' })
      return motion.backward(seg, s, c)
    end, str, cursor)
  end

  local function efwd(str, cursor)
    return helpers.exec_lua(function(s, c)
      local Segmenter = require('cword.segmenter')
      local motion = require('cword.motion')
      local seg = Segmenter.new({ backend = 'icu_ffi' })
      return motion.end_forward(seg, s, c)
    end, str, cursor)
  end

  local function ebwd(str, cursor)
    return helpers.exec_lua(function(s, c)
      local Segmenter = require('cword.segmenter')
      local motion = require('cword.motion')
      local seg = Segmenter.new({ backend = 'icu_ffi' })
      return motion.end_backward(seg, s, c)
    end, str, cursor)
  end

  describe('forward', function()
    it('jumps over the merged cjdict run', function()
      eq(7, fwd('你好世界', 1))
      eq(7, fwd('你好世界', 4)) -- still inside "你好"
      eq(13, fwd('你好世界', 7)) -- past end, clamp
    end)

    it('stops at CJK punctuation (non-word, non-space)', function()
      eq(5, fwd('你 好', 1)) -- skip space to 好
      eq(4, fwd('你，世界', 1)) -- 你 -> ，
    end)

    it('jumps across script change', function()
      eq(4, fwd('你hi', 1))
      eq(3, fwd('hi你', 2))
    end)

    it('clamps to end of line when no next word', function()
      eq(13, fwd('你好世界', 12))
      eq(6, fwd('hello', 5))
    end)

    it('handles cursor inside a merged run', function()
      eq(7, fwd('你好世界', 3))
    end)

    it('handles empty line', function()
      eq(1, fwd('', 1))
    end)

    it('mixed CJK and ASCII', function()
      eq(7, fwd('你好hello世界', 1))
      eq(7, fwd('你好hello世界', 6))
      eq(12, fwd('你好hello世界', 11))
    end)

    it('stops at non-iskeyword boundaries', function()
      eq(5, fwd('pkgs.hello.out', 1)) -- p -> .
      eq(6, fwd('pkgs.hello.out', 5)) -- . -> h
      eq(11, fwd('pkgs.hello.out', 6)) -- h -> .
    end)
  end)

  describe('backward', function()
    it('returns start of merged run when cursor is inside it', function()
      eq(1, bwd('你好世界', 4))
    end)

    it('returns start of previous run when cursor is at its start', function()
      eq(1, bwd('你好世界', 7))
    end)

    it('goes back to non-word token at boundary', function()
      eq(4, bwd('你，世', 7)) -- 界 -> ，
      -- icu_ffi merges adjacent non-word tokens, so the space
      -- and fullwidth comma become one "  ，" run starting at
      -- byte 4. bwd from 世 lands at byte 4, the start of that
      -- merged non-word run.
      eq(4, bwd('你 ，世', 8))
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, bwd('你好', 1))
    end)

    it('stops at non-iskeyword boundaries', function()
      eq(1, bwd('pkgs.hello.out', 5)) -- . -> p (pkgs start)
    end)
  end)

  describe('end_forward', function()
    it('jumps to end of current merged run', function()
      eq(7, efwd('你好世界', 1))
      eq(7, efwd('你好世界', 4))
    end)

    it('skips to next word end when cursor at end of current', function()
      eq(7, efwd('你好世界', 3))
      eq(3, efwd('hi world', 1))
    end)

    it('clamps to end of line when no next word', function()
      eq(13, efwd('你好世界', 12))
    end)
  end)

  describe('end_backward', function()
    it('jumps to end of current merged run', function()
      eq(6, ebwd('你好世界', 4))
    end)

    it('handles cursor inside merged run', function()
      eq(6, ebwd('你好世界', 5))
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, ebwd('你好', 1))
    end)
  end)

  describe('ASCII words', function()
    it('treats ASCII identifiers as single words', function()
      eq(7, fwd('hello world', 1))
      eq(1, bwd('hello world', 7))
      eq(6, efwd('hello world', 1))
    end)
  end)
end)

describe('motion e2e (icu_ffi backend)', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup({ backend = 'icu_ffi' })
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

  it('w jumps over the merged cjdict run', function()
    put('你好世界')
    helpers.feed('w')
    screen:expect({
      grid = [[
  你好^世界                                |
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

  it('w from the last word on a line wraps to the first word on the next line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello --world', 'next here' })
    helpers.api.nvim_win_set_cursor(0, { 1, 8 }) -- on "world"
    helpers.feed('w')
    screen:expect({
      grid = [[
  hello --world                           |
  ^next here                               |
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

  it('vw extends visual selection to the next word', function()
    put('你好世界')
    helpers.feed('v')
    helpers.feed('w')
    screen:expect({
      grid = [[
  你好^世界                                |
  ~                                       |
  ~                                       |
  -- VISUAL --                            |
]],
    })
  end)
end)
