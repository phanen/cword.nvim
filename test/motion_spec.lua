--- @diagnostic disable: undefined-global
-- Motion specs. Algorithm specs are wrapped in helpers.exec_lua so
-- they run in the target nvim (which has the same ICU + cjdict as
-- the user's environment); the runner nvim may have a different
-- ICU build. E2E specs are driven via Screen:expect + helpers.feed.

local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

-- Helper: run an expression in the target nvim and return the result.
local function fwd(line, cursor)
  return helpers.exec_lua(function(l, c)
    local seg = require('cword.segmenter')
    local motion = require('cword.motion')
    return motion.forward(seg.cut, l, c)
  end, line, cursor)
end

local function bwd(line, cursor)
  return helpers.exec_lua(function(l, c)
    local seg = require('cword.segmenter')
    local motion = require('cword.motion')
    return motion.backward(seg.cut, l, c)
  end, line, cursor)
end

local function end_fwd(line, cursor)
  return helpers.exec_lua(function(l, c)
    local seg = require('cword.segmenter')
    local motion = require('cword.motion')
    return motion.end_forward(seg.cut, l, c)
  end, line, cursor)
end

local function end_bwd(line, cursor)
  return helpers.exec_lua(function(l, c)
    local seg = require('cword.segmenter')
    local motion = require('cword.motion')
    return motion.end_backward(seg.cut, l, c)
  end, line, cursor)
end

describe('motion algorithm (icu_ffi)', function()
  -- Skip the whole suite if libicuuc cannot be loaded.
  local ok_ffi = helpers.exec_lua(function()
    local ok = pcall(require, 'cword.segmenter')
    return ok and 'ok' or 'fail'
  end)
  if ok_ffi ~= 'ok' then
    return
  end
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  describe('forward', function()
    it('respects ICU cjdict merges (你好世界 -> 你好|世界)', function()
      eq(7, fwd('你好世界', 1)) -- 你好 -> 世界
    end)

    it('stops at CJK punctuation (non-word, non-space)', function()
      -- icu groups space as a non-word token; forward from `你` lands
      -- on the start of the next word `好` (byte 5).
      eq(5, fwd('你 好', 1))
    end)

    it('jumps across script change', function()
      eq(4, fwd('你hi', 1))
    end)

    it('clamps to end of line when no next word', function()
      eq(13, fwd('你好世界', 12))
      eq(6, fwd('hello', 5))
    end)

    it('handles cursor at end of word', function()
      eq(7, fwd('你好世界', 6))
    end)

    it('handles empty line', function()
      eq(1, fwd('', 1))
    end)

    it('still jumps across runs via whitespace', function()
      eq(8, fwd('你好 world', 1))
    end)

    it('stops at non-iskeyword boundaries', function()
      eq(5, fwd('pkgs.hello.out', 1)) -- p -> .
      eq(6, fwd('pkgs.hello.out', 5)) -- . -> h
      eq(11, fwd('pkgs.hello.out', 6)) -- h -> .
    end)

    it('lands on each non-word non-whitespace char (a ->  ->  ->  b)', function()
      local line = 'a ->  ->  b'
      -- icu groups `->` into one non-word token, so fwd jumps
      -- straight from the start of one `->` to the next.
      eq(3, fwd(line, 1)) -- a -> first -
      eq(7, fwd(line, 3)) -- inside first ->  -> second -
      eq(11, fwd(line, 7)) -- inside second ->  -> b
    end)

    it('lands on each arrow when bwd from end (b ->  ->  a)', function()
      local line = 'a ->  ->  b'
      eq(7, bwd(line, 11)) -- b -> second -
      eq(3, bwd(line, 7)) -- second -  -> first -
      eq(1, bwd(line, 3)) -- first -  -> a
    end)
  end)

  describe('backward', function()
    it('jumps to start of previous word', function()
      eq(1, bwd('你好世界', 7)) -- 世界 -> 你好
    end)

    it('returns start of current word when cursor is inside it', function()
      -- 你好|世界 merge: bwd from byte 6 (last byte of 你好) returns 1.
      eq(1, bwd('你好世界', 6))
    end)

    it('returns start of preceding token when at start of word', function()
      eq(1, bwd('你好世界', 7))
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, bwd('你好', 1))
    end)

    it('stops at non-iskeyword boundaries', function()
      eq(1, bwd('pkgs.hello.out', 5)) -- . -> p (pkgs start)
    end)
  end)

  describe('end_forward', function()
    it('jumps to end of current word', function()
      -- 你好 is the first word; end_forward from 1 lands past
      -- byte 6 (i.e. the next byte position, which is 7).
      eq(7, end_fwd('你好世界', 1))
    end)

    it('skips to next word end when cursor at end of current', function()
      -- 你好 (1-6) is the first word; cursor 3 is inside it, so
      -- end_forward lands just past its end (7).
      eq(7, end_fwd('你好世界', 3))
    end)

    it('clamps to end of line when no next word', function()
      eq(13, end_fwd('你好世界', 12))
    end)
  end)

  describe('end_backward', function()
    it('jumps to end of previous word', function()
      eq(6, end_bwd('你好世界', 7)) -- end of 你好
    end)

    it('clamps to 1 when no previous word', function()
      eq(1, end_bwd('你好', 1))
    end)
  end)

  describe('ASCII words', function()
    it('treats ASCII identifiers as single words', function()
      eq(7, fwd('hello world', 1))
      eq(1, bwd('hello world', 7))
      eq(6, end_fwd('hello world', 1))
    end)
  end)
end)

describe('motion e2e (icu_ffi)', function()
  local screen

  before_each(function()
    helpers.clear()
    helpers.setup_path()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup()
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

  it('w jumps over a CJK group (你好世界 is one segment from cursor)', function()
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

  it('w lands on each non-iskeyword char (a ->  ->  ->  b)', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'a ->  ->  b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w') -- a -> first -
    helpers.feed('w') -- first -  ->  second -
    helpers.feed('w') -- second -  ->  b
    screen:expect({
      grid = [[
  a ->  ->  ^b                             |
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
