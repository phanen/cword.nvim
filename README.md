# cword.nvim

[![MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

CJK-aware word segmentation and word motion for Neovim. Built in two
phases: a pure-Lua segmentation API first, then `w`/`b`/`e`/`ge`
motions that use it.

## Status

| Phase | What                                                   | Status  |
| ----- | ------------------------------------------------------ | ------- |
| 1     | Segmentation API with 3 backends (`cjk`, `icu`, `char`) | shipped |
| 2     | Word motion (`w`/`b`/`e`/`ge`) on top of the segmenter | shipped |

Phase 1 has no external runtime dependencies. Phase 2 needs Neovim >= 0.9.

## Why

Vim's default word motion treats every CJK character as part of one big
`iskeyword` run, so `w` jumps over entire Chinese sentences. ICU's word
segmenter (what `Intl.Segmenter` and most editor integrations use) does
dictionary lookups over `cjdict.txt` and produces unpredictable merges
like `[你好, 世界]` for `你好世界`.

cword.nvim keeps ICU-style CJK run grouping but skips the dictionary,
so the segmentation is **predictable, configurable, and dependency-free**.

| Backend | `你好世界`            | Notes                                                |
| ------- | -------------------- | ---------------------------------------------------- |
| `cjk`   | `你`, `好`, `世`, `界` | default, each CJK char is its own word                |
| `icu`   | `你好世界`            | one CJK run, no dictionary merge                     |
| `char`  | `你`, `好`, `世`, `界` | one token per UTF-8 code point, ASCII letters split too |

## Requirements

- Phase 1: any Lua 5.1+ runtime.
- Phase 2 (planned): Neovim >= 0.9.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'your-name/cword.nvim',
  -- Phase 2: opts = { backend = 'cjk' }, -- default
}
```

With [rocks.nvim](https://github.com/nvim-neorocks/rocks.nvim):

```vim
:Rocks install cword
```

Until Phase 2 lands there are no keymaps or commands to wire. The
segmentation API is usable directly from Lua:

```lua
local Segmenter = require('cword').Segmenter
local seg = Segmenter.new({ backend = 'cjk' })
for _, tok in ipairs(seg:cut('你好，世界 hello')) do
  print(tok.text, tok.byte_start, tok.byte_end, tok.is_word_like)
end
-- 你      1 3  true
-- 好      4 6  true
-- ，      7 9  false
-- 世     10 12 true
-- 界     13 15 true
--       16 16 false
-- hello 17 21 true
```

### Word motion (Phase 2)

```lua
local cword = require('cword')
local seg   = cword.Segmenter.new({ backend = 'cjk' })
local motion = cword.Motion.new({ segmenter = seg })
motion:set_keymaps() -- binds w/b/e/ge in normal mode
```

After `set_keymaps()`:
- `w` jumps one CJK char (or one ASCII word)
- `b` jumps to previous word start
- `e` jumps to end of current/next word
- `ge` jumps to end of previous word

## API

### `Segmenter.new(opts?) -> segmenter`

| Field          | Type   | Default | Description                                       |
| -------------- | ------ | ------- | ------------------------------------------------- |
| `opts.backend` | string | `"cjk"` | One of `"cjk"`, `"icu"`, `"char"`.                |

### `segmenter:cut(str) -> token[]`

Returns a list of tokens. Each token:

```lua
{
  text         = '...',   -- the token's text (UTF-8 byte sequence)
  byte_start   = 1,       -- 1-indexed, inclusive (matches string.sub)
  byte_end     = 6,       -- 1-indexed, inclusive
  is_word_like = true,    -- false for whitespace and punctuation
}
```

`is_word_like` mirrors `Intl.SegmentData.isWordLike` from the JS API.

### `Segmenter.backends() -> string[]`

Sorted list of registered backend names.

### `Motion.new({ segmenter })` (Phase 2 stub)

Defined in `lua/cword/motion.lua` but the `forward`/`backward`/
`end_forward`/`end_backward` methods raise until Phase 2 ships.

## Adding a backend

A backend is a module exposing a single `cut(str) -> token[]` function.

1. Drop a file at `lua/cword/backends/<name>.lua` returning a table with
   `M.cut(str)`.
2. Register the name in `BACKENDS` inside `lua/cword/segmenter.lua`.
3. Add specs under `test/` covering the new behavior.

## Development

```sh
make build         # format-check + test
make test          # busted spec suite
make format        # autoformat Lua sources with stylua
```

See `AGENTS.md` for the full contributor guide.

## Similar Plugins

- [jieba.nvim](https://github.com/neo451/jieba.nvim) — LuaJIT FFI binding
  to cppjieba (C++). Best segmentation quality, needs a build step.
- [jieba-lua](https://github.com/neo451/jieba-lua) — pure-Lua jieba with
  the dictionary baked into a Lua table. No build, but 350k-line dict
  file.
- [wordmotion.nvim](https://github.com/neo451/jieba-lua/tree/master/packages/wordmotion.nvim)
  — the motion framework jieba.nvim and jieba-lua both build on.

## License

MIT. See [LICENSE](./LICENSE).