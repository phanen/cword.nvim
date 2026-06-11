# cword.nvim

CJK-aware word motion for Neovim. `w` jumps one CJK character at a time
instead of skipping an entire sentence.

## Dependencies

- Neovim >= 0.10
- `icu_ffi` backend: `libicuuc` (optional, auto-detected)

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
| `require('cword').setup(opts?)` | Init segmenter (optional, auto-called on first use). `opts.backend` = `"cjk"` or `"icu_ffi"`. |
| `cword.move_forward`         | `w` handler. Supports count, wraps, visual mode. |
| `cword.move_backward`        | `b` handler. |
| `cword.move_end_forward`     | `e` handler. |
| `cword.move_end_backward`    | `ge` handler. |
| `cword.op_forward`          | Operator-pending `w` (use in `'o'` mode with `expr = true`). Pairs with `d`/`c`/`y`. |
| `cword.op_backward`         | Operator-pending `b`. |
| `cword.op_end_forward`      | Operator-pending `e`. |
| `cword.op_end_backward`     | Operator-pending `ge`. |
| `cword.insert_forward`       | Insert-mode `<m-f>` / `<alt-f>`. Move cursor forward one word. |
| `cword.insert_backward`      | Insert-mode `<m-b>` / `<alt-b>`. Move cursor backward one word. |
| `cword.insert_delete_word`   | Insert-mode `<c-w>`. Delete word backward. |
| `cword.cmdline_forward`      | Command-line `<m-f>`. Move cursor forward one word. |
| `cword.cmdline_backward`     | Command-line `<m-b>`. Move cursor backward one word. |
| `cword.cmdline_delete_word`  | Command-line `<c-w>`. Delete word backward. |
| `cword.Segmenter`            | Low-level segmentation (`:cut(str)` → token list). |
| `cword.motion`               | Pure motion functions (`forward(seg, line, cursor)` etc.). |

### Backends

| Backend   | `你好世界` | Notes |
| --------- | ---------- | ----- |
| `icu_ffi` | `你好`, `世界` | Real ICU via FFI, matches `Intl.Segmenter`. Default when libicuuc present. |
| `cjk`     | `你`, `好`, `世`, `界` | Pure Lua. Each CJK code point is one word. |

## Similar

- [jieba.nvim](https://github.com/neo451/jieba.nvim)
- [jieba-lua](https://github.com/neo451/jieba-lua)

## License

MIT
