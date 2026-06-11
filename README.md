# cword.nvim

CJK-aware word motion for Neovim. `w` lands on cjdict-merged CJK runs
(`你好` is one word, `hello` is one word) so `daw`, `viw`, etc. work the
same way they do on Latin identifiers.

## Dependencies

- Neovim >= 0.10
- `libicuuc` (the icu_ffi backend is mandatory; every supported
  platform ships it and the LuaJIT FFI binding loads it eagerly)

## Install

```lua
{
  'phanen/cword.nvim',
  lazy = true,
  keys = { 'w', 'b', 'e', 'ge', 'iw', 'aw', '<m-f>', '<m-b>', '<c-w>' },
  config = function()
    local cword = require('cword')
    local opts = { noremap = true, silent = true }

    -- Normal + visual
    vim.keymap.set({ 'n', 'x' }, 'w',  cword.move_forward, opts)
    vim.keymap.set({ 'n', 'x' }, 'b',  cword.move_backward, opts)
    vim.keymap.set({ 'n', 'x' }, 'e',  cword.move_end_forward, opts)
    vim.keymap.set({ 'n', 'x' }, 'ge', cword.move_end_backward, opts)

    -- Textobjects. Bind in 'x' (visual) and 'o' (operator-pending)
    -- mode; in 'o' mode `expr = true` is required. The same
    -- handler runs in visual mode to extend the selection and in
    -- operator-pending mode to set up the range for d/c/y.
    vim.keymap.set('x', 'iw', cword.textobject_inner_word, opts)
    vim.keymap.set('x', 'aw', cword.textobject_a_word, opts)
    vim.keymap.set('o', 'iw', cword.textobject_inner_word, vim.tbl_extend('force', opts, { expr = true }))
    vim.keymap.set('o', 'aw', cword.textobject_a_word, vim.tbl_extend('force', opts, { expr = true }))

    -- Operator-pending (d/c/y + motion). `expr = true` is required:
    -- the handler returns a `<Cmd>lua ...<CR>` string that aborts the
    -- pending operator and runs the actual delete/change/yank in
    -- normal mode with `virtualedit=onemore` (so the cursor can sit
    -- one cell past the last byte — this is what makes CJK
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
  end,
}
```

## API

| Function                     | Description |
| ---------------------------- | ----------- |
| `require('cword').setup(opts?)` | Init segmenter (optional, auto-called on first use). `opts.backend` = `"icu_ffi"`. |
| `cword.move_forward`         | `w` handler. Supports count, wraps, visual mode. |
| `cword.move_backward`        | `b` handler. |
| `cword.move_end_forward`     | `e` handler. |
| `cword.move_end_backward`    | `ge` handler. |
| `cword.op_forward`          | Operator-pending `w` (use in `'o'` mode with `expr = true`). Pairs with `d`/`c`/`y`. |
| `cword.op_backward`         | Operator-pending `b`. |
| `cword.op_end_forward`      | Operator-pending `e`. |
| `cword.op_end_backward`     | Operator-pending `ge`. |
| `cword.textobject_inner_word` | `iw` handler. Bind in `'x'` and `'o'` (with `expr = true`) mode. |
| `cword.textobject_a_word`    | `aw` handler. Bind in `'x'` and `'o'` (with `expr = true`) mode. |
| `cword.insert_forward`       | Insert-mode `<m-f>` / `<alt-f>`. Move cursor forward one word. |
| `cword.insert_backward`      | Insert-mode `<m-b>` / `<alt-b>`. Move cursor backward one word. |
| `cword.insert_delete_word`   | Insert-mode `<c-w>`. Delete word backward. |
| `cword.cmdline_forward`      | Command-line `<m-f>`. Move cursor forward one word. |
| `cword.cmdline_backward`     | Command-line `<m-b>`. Move cursor backward one word. |
| `cword.cmdline_delete_word`  | Command-line `<c-w>`. Delete word backward. |
| `cword.Segmenter`            | Low-level segmentation (`:cut(str)` → token list). |
| `cword.motion`               | Pure motion functions (`forward(seg, line, cursor)` etc.). |

### Backends

| Backend   | `你好世界`        | Notes |
| --------- | ----------------- | ----- |
| `icu_ffi` | `你好`, `世界`     | Real ICU via FFI. Merges CJK runs via cjdict; treats Latin with ICU's word rules. Mandatory. |

## Similar

- [jieba.nvim](https://github.com/neo451/jieba.nvim)
- [jieba-lua](https://github.com/neo451/jieba-lua)

## License

MIT
