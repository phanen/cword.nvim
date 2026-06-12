-- Minimal runnable demo of the segmentation API.
-- Run from the repo root:
--
--   luajit examples/cut_demo.lua
--
-- Needs libicuuc available on the dynamic linker path so that
-- require('cword.segmenter') can dlopen it.

-- Make `require("cword...")` resolvable when running outside Neovim.
local script_dir = (debug.getinfo(1).source:match('@?(.*)'):match('(.*/)') or './')
package.path = script_dir .. '../lua/?.lua;' .. script_dir .. '../lua/?/init.lua;' .. package.path

local Segmenter = require('cword.segmenter')

local samples = {
  '你好世界',
  '你好，世界 hello',
  '南京市长江大桥',
  'foo_bar baz',
  'a ->  ->  b',
}

io.write('--- backend: icu_ffi ---\n')
for _, s in ipairs(samples) do
  io.write(string.format('  %-22s -> ', '[' .. s .. ']'))
  local parts = {}
  for _, tok in ipairs(Segmenter.cut(s)) do
    parts[#parts + 1] = string.format('%s%s', tok.text, tok.is_word_like and '' or '·')
  end
  io.write(table.concat(parts, '|') .. '\n')
end
