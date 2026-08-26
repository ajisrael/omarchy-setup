-- harpoon 2 config
local harpoon = require 'harpoon'

-- harpoon's default settings.key() is `vim.loop.cwd()` (see harpoon.config's
-- get_default_config), i.e. the process's current directory rather than the
-- project root. When nvim is launched from outside a project (e.g. $HOME)
-- and a file inside some project is opened by absolute path, cwd never
-- changes to match - so marks silently land in a shared bucket keyed by
-- that launch directory instead of the project's own bucket, and appear to
-- leak across projects. Keying off the buffer's git root keeps marks scoped
-- per-repository regardless of where nvim's cwd happens to be.
local function project_key()
  local root = vim.fs.root(0, '.git')
  return root or vim.loop.cwd()
end

-- REQUIRED
harpoon:setup {
  settings = {
    key = project_key,
  },
}
-- REQUIRED

vim.keymap.set('n', '<leader>a', function() harpoon:list():add() end)
vim.keymap.set('n', '<C-e>', function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

vim.keymap.set('n', '<C-j>', function() harpoon:list():select(1) end)
vim.keymap.set('n', '<C-k>', function() harpoon:list():select(2) end)
vim.keymap.set('n', '<C-l>', function() harpoon:list():select(3) end)
vim.keymap.set('n', '<C-h>', function() harpoon:list():select(4) end)

-- Toggle previous & next buffers stored within Harpoon list
vim.keymap.set('n', '<C-S-P>', function() harpoon:list():prev() end)
vim.keymap.set('n', '<C-S-N>', function() harpoon:list():next() end)
