# cword.nvim

CJK-aware word motion for Neovim. `w` lands on cjdict-merged CJK runs
(`你好` is one word, `hello` is one word) so `daw`, `viw`, etc. work the
same way they do on Latin identifiers. `w`/`b`/`e`/`ge` also handle
non-keyword non-whitespace runs (`->`, `**`, `]]`) as single words,
matching stock Vim's behaviour.

## Dependencies

- Neovim >= 0.11
- `libicuuc` (the icu_ffi backend is mandatory; every supported
  platform ships it and the LuaJIT FFI binding loads it eagerly)

## Install

```lua
{
  'phanen/cword.nvim',
  lazy = true,
  keys = { 'w', 'b', 'e', 'ge', '<m-f>', '<m-b>', '<c-w>' },
  config = function()
    local cword = require('cword')
    local opts = { noremap = true, silent = true }

    -- Normal + visual
    vim.keymap.set({ 'n', 'x' }, 'w',  cword.move_forward, opts)
    vim.keymap.set({ 'n', 'x' }, 'b',  cword.move_backward, opts)
    vim.keymap.set({ 'n', 'x' }, 'e',  cword.move_end_forward, opts)
    vim.keymap.set({ 'n', 'x' }, 'ge', cword.move_end_backward, opts)

    -- Operator-pending (d/c/y + motion). `expr = true` is required:
    -- the handler returns a `<Cmd>lua ...<CR>` string that aborts
    -- the pending operator and runs the actual delete/change/yank
    -- in normal mode with `virtualedit=onemore` (so the cursor can
    -- sit one cell past the last byte — this is what makes CJK
    -- end-of-line motion exact).
    vim.keymap.set('o', 'w',  cword.op_forward,       vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'b',  cword.op_backward,      vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'e',  cword.op_end_forward,  vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'ge', cword.op_end_backward, vim.tbl_extend('force', opts, { expr = true }))

    -- Insert mode
    vim.keymap.set('i', '<m-f>', cword.insert_forward, opts)
    vim.keymap.set('i', '<m-b>', cword.insert_backward, opts)
    vim.keymap.set('i', '<c-w>', cword.insert_delete_word, opts)

    -- Command-line mode
    vim.keymap.set('c', '<m-f>', cword.cmdline_forward, opts)
    vim.keymap.set('c', '<m-b>', cword.cmdline_backward, opts)
    vim.keymap.set('c', '<c-w>', cword.cmdline_delete_word, opts)

    -- Textobjects (`iw` / `aw`). `expr = true` is required in operator-
    -- pending mode. The same handler serves `diw`, `ciw`, `yiw` and the
    -- visual-mode entry `viw` / `vaw` (the handler detects which mode
    -- it was invoked from).
    vim.keymap.set(
      'o',
      'iw',
      cword.textobject_inner_word,
      vim.tbl_extend('force', opts, { expr = true })
    )
    vim.keymap.set(
      'o',
      'aw',
      cword.textobject_a_word,
      vim.tbl_extend('force', opts, { expr = true })
    )
    vim.keymap.set('x', 'iw', cword.textobject_inner_word, opts)
    vim.keymap.set('x', 'aw', cword.textobject_a_word, opts)

    -- Mouse double-click selects the CJK-aware word under the cursor.
    -- The default `iskeyword`-based `find_start_of_word` /
    -- `find_end_of_word` in `src/nvim/mouse.c:970-981` does not merge
    -- CJK runs (你好 stays as 你|好). `cword.double_click_select`
    -- uses the same icu_ffi segmenter as the motions, so double-click
    -- on `你好` selects the whole run.
    --
    -- `getmousepos()` returns 1-based fields; `double_click_select` takes
    -- a 0-indexed byte column, so `m.column - 1` does the conversion.
    vim.keymap.set('', '<2-LeftMouse>', function()
      local m = vim.fn.getmousepos()
      if m.line < 1 then
        return
      end
      cword.double_click_select(0, m.line, m.column - 1)
    end, vim.tbl_extend('force', opts, { expr = false }))
  end,
}
```

## API

| Function                     | Description |
| ---------------------------- | ----------- |
| `require('cword').setup(opts?)` | Bind the segmenter (optional, auto-called on first move_*). No opts. |
| `cword.move_forward`         | `w` handler. Supports count, wraps, visual mode. |
| `cword.move_backward`        | `b` handler. |
| `cword.move_end_forward`     | `e` handler. |
| `cword.move_end_backward`    | `ge` handler. |
| `cword.op_forward`           | Operator-pending `w` (use in `'o'` mode with `expr = true`). Pairs with `d`/`c`/`y`. |
| `cword.op_backward`          | Operator-pending `b`. |
| `cword.op_end_forward`       | Operator-pending `e`. |
| `cword.op_end_backward`      | Operator-pending `ge`. |
| `cword.insert_forward`       | Insert-mode `<m-f>` / `<alt-f>`. Move cursor forward one word. |
| `cword.insert_backward`      | Insert-mode `<m-b>` / `<alt-b>`. Move cursor backward one word. |
| `cword.insert_delete_word`   | Insert-mode `<c-w>`. Delete word backward. |
| `cword.cmdline_forward`      | Command-line `<m-f>`. Move cursor forward one word. |
| `cword.cmdline_backward`     | Command-line `<m-b>`. Move cursor backward one word. |
| `cword.cmdline_delete_word`  | Command-line `<c-w>`. Delete word backward. |
| `cword.textobject_inner_word` | Textobject `iw` (use in `'o'` mode with `expr = true` and in `'x'` mode). Selects the inner word at the cursor. |
| `cword.textobject_a_word`    | Textobject `aw`. Selects the word plus its trailing whitespace. |
| `cword.text_object(buf, row, col, ai?)` | CJK-aware text-object lookup. Returns `{buf, row, start, end_excl, text, ai}` for the word at `(row, col)` (col is 0-indexed byte). `ai` defaults to `'i'`. Returns `nil` when the cursor is on whitespace or past the last token. |
| `cword.double_click_select(buf, row, col, ai?)` | Mouse double-click helper. Sets the `'<` / `'>` marks and enters visual mode at the CJK-aware word under `(row, col)`. Returns `true` if a word was selected. Bind it to `<2-LeftMouse>` to get CJK-aware double-click selection (matches what stock `viw` would select). |
| `cword.Segmenter`            | The icu_ffi segmenter module (`.cut(str)` → token list). |
| `cword.motion`               | Pure motion functions (`forward(cut, line, cursor)` etc.). |
| `cword.get_cword()`          | CJK-aware version of `expand('<cword>')`. Returns the merged run (`你好`) instead of one char. Empty string when the cursor is on whitespace or a non-word token. |
| `cword.get_token()`          | Full token under the cursor (`{text, byte_start, byte_end, is_word_like}`); `nil` on whitespace / non-word tokens. |

### Segmentation backend

| Backend   | `你好世界`        | Notes |
| --------- | ----------------- | ----- |
| `icu_ffi` | `你好`, `世界`     | Real ICU via LuaJIT FFI. Merges CJK runs via cjdict; treats Latin and punctuation with ICU's word rules. Mandatory, no other backend. |

## Similar

- https://github.com/kkew3/jieba.vim
- https://github.com/neo451/jieba.nvim
- https://github.com/sirasagi62/tinysegmenter.nvim
- https://github.com/atusy/budouxify.nvim

## License

MIT
