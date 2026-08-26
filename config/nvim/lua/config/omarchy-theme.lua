-- omarchy-setup: execute omarchy's generated neovim theme spec directly.
--
-- `omarchy theme set <name>` regenerates
--   ~/.local/state/omarchy/current/theme/neovim.lua
-- - a lazy-style spec whose non-LazyVim entries are colorscheme plugin
-- tables ("owner/repo", optional name/branch/opts) and whose final
-- LazyVim/LazyVim entry carries opts.colorscheme. This module installs the
-- referenced plugins on demand via vim.pack, runs their setup() with the
-- spec's opts (the palette injection matters for omarchy's generated aether
-- themes), then applies the colorscheme. The state file is re-read on
-- FocusGained/VimResume so `omarchy theme set` lands in running instances
-- (tmux has focus-events on). Transparency is reapplied on every ColorScheme.
--
-- Without a state file (fresh box before the first `omarchy theme set`) it
-- falls back to tokyonight-night transparent, the original kickstart choice.
local M = {}

local THEME_SPEC_FILE = vim.fn.expand '~/.local/state/omarchy/current/theme/neovim.lua'
local FALLBACK_COLORSCHEME = 'tokyonight-night'

local function gh(repo) return 'https://github.com/' .. repo end

-- Theme modules required by the last apply(); cleared before re-applying so
-- stale cached palettes (same plugin, different opts - e.g. generic aether
-- themes sharing aether.nvim) never survive a switch.
local loaded_modules = {}

local function read_raw()
  local file = io.open(THEME_SPEC_FILE, 'r')
  if not file then return '' end
  local raw = file:read '*a'
  file:close()
  return raw or ''
end

-- Returns nil when the state file is absent or not a spec table.
local function read_spec()
  local chunk = loadfile(THEME_SPEC_FILE)
  if not chunk then return nil end
  local ok, spec = pcall(chunk)
  if not ok or type(spec) ~= 'table' then return nil end
  return spec
end

---Candidate lua module names for a spec entry ("owner/repo" + optional name),
---most specific first. Every current omarchy theme resolves within these.
---@param entry table
---@return string[]
local function module_candidates(entry)
  local names = {}
  local function add(name)
    if type(name) == 'string' and name ~= '' and not vim.tbl_contains(names, name) then names[#names + 1] = name end
  end
  add(entry.name)
  local base = entry[1]:match '[^/]+$' or entry[1]
  add(base)
  base = (base:gsub('%.nvim$', ''))
  add(base)
  base = (base:gsub('%-nvim$', ''))
  add(base)
  base = (base:gsub('%-neovim$', ''))
  add(base)
  return names
end

---Best-effort setup(): require a candidate module and call its setup with the
---spec's opts. Themes whose module never resolves still work - :colorscheme
---loads them from rtp with defaults; only opts-carrying specs would be missed.
---@param entry table
---@param opts table?
local function setup_theme(entry, opts)
  for _, mod in ipairs(module_candidates(entry)) do
    if pcall(require, mod) then
      if not vim.tbl_contains(loaded_modules, mod) then loaded_modules[#loaded_modules + 1] = mod end
      local theme = package.loaded[mod]
      if type(theme) == 'table' and type(theme.setup) == 'function' then
        pcall(theme.setup, opts or {})
        return
      end
    end
  end
end

local function unload_loaded_modules()
  for _, mod in ipairs(loaded_modules) do
    package.loaded[mod] = nil
  end
  loaded_modules = {}
end

function M.apply()
  -- Clear residue from the previous theme before loading the new one.
  unload_loaded_modules()
  vim.cmd 'highlight clear'
  if vim.fn.exists 'syntax_on' == 1 then vim.cmd 'syntax reset' end

  local colorscheme = FALLBACK_COLORSCHEME
  local packs, entries = {}, {}

  local spec = read_spec()
  if spec then
    for _, entry in ipairs(spec) do
      if type(entry) == 'table' and type(entry[1]) == 'string' then
        if entry[1] == 'LazyVim/LazyVim' then
          colorscheme = (entry.opts and entry.opts.colorscheme) or colorscheme
        else
          packs[#packs + 1] = { src = gh(entry[1]), name = entry.name, version = entry.branch }
          entries[#entries + 1] = entry
        end
      end
    end
  else
    -- Fallback: match upstream kickstart's colorscheme block exactly,
    -- including its transparency settings.
    colorscheme = FALLBACK_COLORSCHEME
    packs = { { src = gh 'folke/tokyonight.nvim' } }
    entries = { { 'folke/tokyonight.nvim', opts = { transparent = true, styles = { sidebars = 'transparent', floats = 'transparent' } } } }
  end

  vim.pack.add(packs)
  for _, entry in ipairs(entries) do
    setup_theme(entry, entry.opts)
  end
  pcall(vim.cmd.colorscheme, colorscheme)

  -- Lighten relative line numbers under tokyonight; default LineNr is too dim.
  if colorscheme:match '^tokyonight' then vim.api.nvim_set_hl(0, 'LineNr', { fg = '#565f89' }) end

  require('config.transparency').apply()
end

---Set up the pipeline: apply now, watch the state file for omarchy theme
---switches, and expose :OmarchyThemeReload for manual re-apply.
function M.setup()
  M.apply()

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('omarchy-theme-transparency', { clear = true }),
    callback = function() vim.schedule(require('config.transparency').apply) end,
    desc = 'Reapply transparency after any colorscheme change',
  })

  local last_raw = read_raw()
  vim.api.nvim_create_autocmd({ 'FocusGained', 'VimResume' }, {
    group = vim.api.nvim_create_augroup('omarchy-theme-watch', { clear = true }),
    callback = function()
      local raw = read_raw()
      if raw ~= last_raw then
        last_raw = raw
        vim.schedule(M.apply)
      end
    end,
    desc = 'Pick up omarchy theme switches in running instances',
  })

  vim.api.nvim_create_user_command('OmarchyThemeReload', function() M.apply() end, { desc = 'Re-run the omarchy theme pipeline' })
end

return M
