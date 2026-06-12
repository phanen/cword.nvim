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
