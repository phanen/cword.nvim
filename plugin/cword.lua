if vim.g.loaded_cword then
  return
end
vim.g.loaded_cword = 1

-- Default setup: bind w/b/e/ge with the CJK-aware segmenter. Users
-- override by calling require('cword').setup({...}) from their
-- config; this run only happens on first plugin load.
require('cword').setup()