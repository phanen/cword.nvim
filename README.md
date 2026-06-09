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
  keys = { 'w', 'b', 'e', 'ge' },
  config = function()
    local cword = require('cword')
    vim.keymap.set({ 'n', 'x' }, 'w',  cword.move_forward)
    vim.keymap.set({ 'n', 'x' }, 'b',  cword.move_backward)
    vim.keymap.set({ 'n', 'x' }, 'e',  cword.move_end_forward)
    vim.keymap.set({ 'n', 'x' }, 'ge', cword.move_end_backward)
  end,
}
```

## API

| Function                     | Description |
| ---------------------------- | ----------- |
| `require('cword').setup(opts?)` | Init segmenter (optional, auto-called on first use). `opts.backend` = `"cjk"` or `"icu_ffi"`. |
| `cword.move_forward`         | `w` handler. Supports count, wraps across lines, visual mode. |
| `cword.move_backward`        | `b` handler. |
| `cword.move_end_forward`     | `e` handler. |
| `cword.move_end_backward`    | `ge` handler. |
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
