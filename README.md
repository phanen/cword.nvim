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

    -- Direct operators (dw/cw/de/ce/db/cb)
    vim.keymap.set('n', 'dw', cword.delete_forward, opts)
    vim.keymap.set('n', 'cw', cword.change_forward, opts)
    vim.keymap.set('n', 'de', cword.delete_end_forward, opts)
    vim.keymap.set('n', 'ce', cword.change_end_forward, opts)
    vim.keymap.set('n', 'db', cword.delete_backward, opts)
    vim.keymap.set('n', 'cb', cword.change_backward, opts)

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
| `cword.move_forward`         | `w` handler. Supports count, wraps across lines, visual + operator-pending modes. |
| `cword.move_backward`        | `b` handler. |
| `cword.move_end_forward`     | `e` handler. |
| `cword.move_end_backward`    | `ge` handler. |
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
