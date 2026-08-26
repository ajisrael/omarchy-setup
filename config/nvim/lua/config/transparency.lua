-- Ported from omarchy-nvim's plugin/after/transparency.lua: strip background
-- from highlight groups while preserving their other attributes, so nvim
-- matches the transparent omarchy desktop on every theme. Runs on every
-- ColorScheme event (see config.omarchy-theme) plus manually after each apply.
local M = {}

local function make_transparent(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok then
    hl.bg = nil
    vim.api.nvim_set_hl(0, name, hl)
  end
end

local groups = {
  -- transparent background
  'Normal',
  'NormalFloat',
  'FloatBorder',
  'Pmenu',
  'Terminal',
  'EndOfBuffer',
  'FoldColumn',
  'Folded',
  'SignColumn',
  'LineNr',
  'CursorLineNr',
  'NormalNC',
  'WhichKeyFloat',
  'TelescopeBorder',
  'TelescopeNormal',
  'TelescopePromptBorder',
  'TelescopePromptTitle',
  -- neotree
  'NeoTreeNormal',
  'NeoTreeNormalNC',
  'NeoTreeVertSplit',
  'NeoTreeWinSeparator',
  'NeoTreeEndOfBuffer',
  -- nvim-tree
  'NvimTreeNormal',
  'NvimTreeVertSplit',
  'NvimTreeEndOfBuffer',
  -- notify
  'NotifyINFOBody',
  'NotifyERRORBody',
  'NotifyWARNBody',
  'NotifyTRACEBody',
  'NotifyDEBUGBody',
  'NotifyINFOTitle',
  'NotifyERRORTitle',
  'NotifyWARNTitle',
  'NotifyTRACETitle',
  'NotifyDEBUGTitle',
  'NotifyINFOBorder',
  'NotifyERRORBorder',
  'NotifyWARNBorder',
  'NotifyTRACEBorder',
  'NotifyDEBUGBorder',
}

function M.apply()
  for _, name in ipairs(groups) do
    make_transparent(name)
  end
end

return M
