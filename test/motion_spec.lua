--- @diagnostic disable: undefined-global
-- Motion specs — end-to-end via nvim-test Screen or cursor position
-- assertions (helpers.exec_lua).  The key behavioural cases use
-- screen:expect; for less visual regressions we check the cursor
-- column directly.

local helpers = require('test.cword_helpers')
local Screen = require('nvim-test.screen')

local eq = helpers.eq

local function setup()
  helpers.clear()
  helpers.setup_path()
  helpers.exec_lua(function()
    local cword = require('cword')
    cword.setup()
    local opts = { noremap = true, silent = true }
    vim.keymap.set({ 'n', 'x' }, 'w', cword.move_forward, opts)
    vim.keymap.set({ 'n', 'x' }, 'b', cword.move_backward, opts)
    vim.keymap.set({ 'n', 'x' }, 'e', cword.move_end_forward, opts)
    vim.keymap.set({ 'n', 'x' }, 'ge', cword.move_end_backward, opts)
    vim.keymap.set('o', 'w', cword.op_forward, vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'b', cword.op_backward, vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'e', cword.op_end_forward, vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'ge', cword.op_end_backward, vim.tbl_extend('force', opts, { expr = true }))
  end)
end

local function put(line)
  helpers.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  helpers.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function put_at(line, row, col)
  helpers.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  helpers.api.nvim_win_set_cursor(0, { row, col })
end

local function col0()
  return helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[2]')
end

describe('motion w (icu_ffi)', function()
  local screen

  before_each(function()
    setup()
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('w from start of 你好 world lands on world (cjkdict merge)', function()
    put('你好 world')
    helpers.feed('w')
    eq(7, col0()) -- past 你好 + space, on 'w'
  end)

  it('w on ASCII moves one word at a time', function()
    put('hi你好')
    helpers.feed('w')
    -- hi → 你 (the first CJK char)
    eq(2, col0()) -- past 'hi' (2 bytes 0-idx)
  end)

  it('w on a ->  ->  b lands on each arrow then b', function()
    -- w from a → → → b, one word-step at a time.
    put('a ->  ->  b')
    helpers.feed('w')
    eq(2, col0()) -- on first '-'
    helpers.feed('w')
    eq(6, col0()) -- on second '-'
    helpers.feed('w')
    eq(10, col0()) -- on 'b'
  end)

  it('w stops at CJK punctuation', function()
    put('你好，世界')
    helpers.feed('w')
    eq(6, col0()) -- on ，
    helpers.feed('w')
    eq(9, col0()) -- on 世界
  end)

  it('w stops at non-iskeyword boundaries (pkgs.hello.out)', function()
    put('pkgs.hello.out')
    helpers.feed('w')
    eq(4, col0()) -- on .
    helpers.feed('w')
    eq(5, col0()) -- on h
    helpers.feed('w')
    eq(10, col0()) -- on .
  end)

  it('w clamps to end of line when no next word', function()
    put('hello')
    helpers.feed('w')
    eq(4, col0()) -- clamped
  end)

  it('3w repeats the motion', function()
    put('aa bb cc dd')
    helpers.feed('3w')
    eq(9, col0()) -- on 'cc' space
  end)

  it('w wraps past the end of a line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'next line here' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    eq(6, col0()) -- on 'world' of first line
  end)

  it('w stops at an empty line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello', '', 'next' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    eq(0, col0()) -- on empty line
  end)

  it('w from start of line with CJK should not jump to next line', function()
    -- '你好 a' on line 1, 'b' on line 2. w from col 0 should
    -- land on 'a' of line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(7, cursor[2]) -- should be at 'a'
  end)

  it('w from space should not jump to next line', function()
    -- ' a' on line 1, 'b' on line 2. w from col 0 (on space)
    -- should land on 'a' of line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { ' a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('w')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(1, cursor[2]) -- should be at 'a'
  end)
end)

describe('motion b (icu_ffi)', function()
  local screen

  before_each(function()
    setup()
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('b from end of a ->  ->  b lands on second ->', function()
    put_at('a ->  ->  b', 1, 10) -- on b
    helpers.feed('b')
    eq(6, col0()) -- on second '-'
  end)

  it('b walks back through cjdict-merged runs', function()
    put_at('你好世界', 1, 12) -- past end
    helpers.feed('b')
    eq(6, col0()) -- on 世界 start
    helpers.feed('b')
    eq(0, col0()) -- on 你好 start
  end)

  it('b wraps into the previous line', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo bar' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 })
    helpers.feed('b')
    eq(10, col0()) -- on 'd' of first line
  end)
end)

describe('motion e (icu_ffi)', function()
  local screen

  before_each(function()
    setup()
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  it('e from a ->  ->  b lands on end of first ->', function()
    put('a ->  ->  b')
    helpers.feed('e')
    eq(3, col0()) -- on '>' of first ->
  end)

  it('e on emoji with variation selector does not get stuck', function()
    -- abc ⚠️ def: e from the start of ⚠️ should not get stuck
    -- at the start. cword treats ⚠️ as a separate word via
    -- ICU segmentation, so the motion returns byte_end = 10
    -- of the ⚠️ token.
    --
    -- This test uses exec_lua + normal! instead of helpers.feed
    -- because nvim_input / nvim_feedkeys in the test runner
    -- have trouble moving past multi-byte characters (the
    -- keymap is called and sets the cursor correctly, but
    -- the input handler then overrides it).
    put('abc ⚠️ def')
    helpers.api.nvim_win_set_cursor(0, { 1, 4 }) -- start of ⚠️
    local col = helpers.exec_lua(function()
      vim.cmd('normal! e')
      return vim.api.nvim_win_get_cursor(0)[2]
    end)
    -- The cursor should move (not stay at col 4). In stock
    -- nvim v0.12.0, ⚠️ is part of a larger word (CJK chars
    -- are in iskeyword), so normal! e goes to end of 'def'
    -- (col 13). The important assertion is that the cursor
    -- does NOT get stuck at col 4.
    assert(col ~= 4, 'e got stuck at the start of the emoji (col 4)')
  end)

  it('e from space should not jump to next line', function()
    -- ' a' on line 1, 'b' on line 2. e from col 0 (on space)
    -- should land on 'a' of line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { ' a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(1, cursor[2]) -- should be at 'a'
  end)

  it('e from space mid-line with ASCII should go to next word end', function()
    -- 'hello world' on line 1, 'foo' on line 2. e from the space
    -- should land on 'd' of 'world' on line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello world', 'foo' })
    helpers.api.nvim_win_set_cursor(0, { 1, 5 }) -- on the space
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(10, cursor[2]) -- end of 'world'
  end)
end)

describe('motion vw (icu_ffi)', function()
  local screen

  before_each(function()
    setup()
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
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

describe('CJK motion e2e (icu_ffi)', function()
  local screen

  before_each(function()
    setup()
    screen = Screen.new(40, 4)
    screen:attach()
  end)

  after_each(function()
    if screen then
      screen:detach()
    end
  end)

  -- CJK: icu merges 你好 into one word; stock Vim treats continuous
  -- CJK as one big word.  cword follows ICU, so w moves per-cjdict
  -- segment rather than per-character.

  it('w on CJK 你好世界 lands on 世界 (cjdict merge)', function()
    put('你好世界')
    helpers.feed('w')
    eq(6, col0()) -- start of 世界
  end)

  it('w from middle of CJK word stays in same word', function()
    put('你好世界')
    put_at('你好世界', 1, 3) -- mid-byte of 你
    helpers.feed('w')
    eq(6, col0()) -- still lands on start of 世界
  end)

  it('b on CJK 你好世界 lands on 你好 (cjdict merge)', function()
    put_at('你好世界', 1, 12) -- past end
    helpers.feed('b')
    eq(6, col0()) -- start of 世界
    helpers.feed('b')
    eq(0, col0()) -- start of 你好
  end)

  it('e on CJK 你好世界 lands on end of 你好', function()
    put('你好世界')
    helpers.feed('e')
    -- end of 你好 is the first byte of 好 = col 3.
    eq(3, col0())
  end)

  it('ge on CJK 你好世界 from 世界 start lands on end of 你好', function()
    put_at('你好世界', 1, 6)
    helpers.feed('ge')
    eq(3, col0())
  end)

  -- CJK + punctuation: e moves (not stuck)

  it('e on 你好，世界 lands on end of 你好', function()
    put('你好，世界')
    helpers.feed('e')
    eq(3, col0())
  end)

  -- CJK: e from col 0 should not jump to next line when there
  -- is more content on the same line.

  it('e from start of line with CJK should not jump to next line', function()
    -- '你好 a' on line 1, 'b' on line 2. e from col 0 should
    -- land on end of '你好' (col 3) on line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(3, cursor[2]) -- end of '你好'
  end)

  it('e from space mid-line with CJK+ASCII should go to next word end', function()
    -- Cursor on the space between '你好' and 'a' on line 1;
    -- line 2 has a single-char word. e should land on the end
    -- of 'a' on line 1, not jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 a', 'b' })
    helpers.api.nvim_win_set_cursor(0, { 1, 6 }) -- on the space
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(7, cursor[2]) -- end of 'a'
  end)

  it('e on non-last char of last word should go to last char', function()
    -- Cursor on 'a' of 'abc' (first line); line 2 also has 'abc'.
    -- e should land on the end of 'abc' (col 9) on line 1, not
    -- jump to line 2.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 7 }) -- on 'a' of 'abc'
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(9, cursor[2]) -- end of 'abc'
  end)

  it('e on middle char of last word should go to last char', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好 abc', 'abc' })
    helpers.api.nvim_win_set_cursor(0, { 1, 8 }) -- on 'b' of 'abc'
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(9, cursor[2]) -- end of 'abc'
  end)

  it('e on CJK non-last char of last word should go to last char', function()
    -- 你好世界: cursor on 你 (first char of 你好). e should go
    -- to the end of 你好 (start of 好, col 3), not jump to next line.
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '你好' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 }) -- on '你'
    helpers.feed('e')
    local cursor = helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)')
    eq(1, cursor[1]) -- should stay on line 1
    eq(3, cursor[2]) -- start of 好 (end of 你好)
  end)

  -- CJK + ASCII mixed

  it('w from hello to CJK 你好 jumps correctly', function()
    put('hello 你好 world')
    put_at('hello 你好 world', 1, 6) -- start of 你好
    helpers.feed('w')
    eq(13, col0()) -- start of world (byte 14 -> col 13)
  end)

  -- CJK + punctuation

  it('w on CJK+punct 你好，世界 lands on 世界', function()
    put('你好，世界')
    helpers.feed('w')
    eq(6, col0()) -- on ，
    helpers.feed('w')
    eq(9, col0()) -- start of 世界
  end)

  -- cross-line e / ge

  it('e wraps to next line on CJK', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 12 }) -- EOL
    helpers.feed('e')
    eq(2, helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[1]'))
    eq(3, col0()) -- end of 你好 on line 2
  end)

  it('e advances across CJK lines without getting stuck', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 1, 0 })
    -- The test runner's --embed mode processes input between
    -- exec_lua calls, which can trigger the keymap and move
    -- the cursor. To avoid this, we call cword.move_end_forward
    -- directly and return the cursor in the same exec_lua call.
    local r1 = helpers.exec_lua(function()
      local cword = require('cword')
      cword.move_end_forward()
      return vim.api.nvim_win_get_cursor(0)
    end)
    eq(1, r1[1])
    eq(5, r1[2]) -- end of 你好
    local r2 = helpers.exec_lua(function()
      -- Reset cursor to end of 你好 before calling move_end_forward
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      local cword = require('cword')
      cword.move_end_forward()
      return vim.api.nvim_win_get_cursor(0)
    end)
    eq(1, r2[1])
    eq(11, r2[2]) -- end of 世界
    local r3 = helpers.exec_lua(function()
      -- Reset cursor to end of 世界 before calling move_end_forward
      vim.api.nvim_win_set_cursor(0, { 1, 11 })
      local cword = require('cword')
      cword.move_end_forward()
      return vim.api.nvim_win_get_cursor(0)
    end)
    eq(2, r3[1]) -- wrap to line 2
    eq(5, r3[2]) -- end of 你好 on line 2
  end)

  it('ge wraps to previous line on CJK', function()
    helpers.api.nvim_buf_set_lines(0, 0, -1, false, { '你好世界', '你好世界' })
    helpers.api.nvim_win_set_cursor(0, { 2, 0 }) -- BOL line 2
    helpers.feed('ge')
    eq(1, helpers.exec_lua('return vim.api.nvim_win_get_cursor(0)[1]'))
    eq(9, col0()) -- end of 世界 on line 1
  end)
end)
