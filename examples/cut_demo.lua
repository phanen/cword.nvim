-- Minimal runnable demo of the segmentation API.
-- Run from the repo root:
--
--   lua examples/cut_demo.lua
--
-- Or with LuaJIT:
--
--   luajit examples/cut_demo.lua
--
-- No Neovim required.

-- Make `require("cword...")` resolvable when running outside Neovim.
local script_dir = (debug.getinfo(1).source:match('@?(.*)'):match('(.*/)') or './')
package.path = script_dir .. '../lua/?.lua;' .. script_dir .. '../lua/?/init.lua;' .. package.path

local Segmenter = require('cword.segmenter')

local samples = {
  '你好世界',
  '你好，世界 hello',
  '南京市长江大桥',
  'foo_bar baz',
}

local backends = Segmenter.backends()

for _, name in ipairs(backends) do
  local seg = Segmenter.new({ backend = name })
  io.write(('--- backend: %s ---\n'):format(name))
  for _, s in ipairs(samples) do
    io.write(string.format('  %-22s -> ', '[' .. s .. ']'))
    local parts = {}
    for _, tok in ipairs(seg:cut(s)) do
      parts[#parts + 1] = string.format('%s%s', tok.text, tok.is_word_like and '' or '·')
    end
    io.write(table.concat(parts, '|') .. '\n')
  end
  io.write('\n')
end
