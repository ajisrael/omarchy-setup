-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Screenshot keybindings (replaces default PRINT binding)
hl.unbind("PRINT")
o.bind("CTRL + SHIFT + 4", "Screenshot (region)", "omarchy capture screenshot region")
o.bind("CTRL + SHIFT + S", "Screenshot (fullscreen)", "omarchy capture screenshot fullscreen")

-- OCR text extraction (was SUPER + CTRL + PRINT, but no Print key on this keyboard)
hl.unbind("SUPER + CTRL + PRINT")
o.bind("SUPER + CTRL + SHIFT + 4", "Extract text (OCR)", "omarchy capture text")

-- ---------------------------------------------------------------------------
-- Personal bindings (omarchy-setup)
--

-- SUPER+CTRL+ALT+S: toggle suspend-on-lid-close so agents keep working with
-- the lid shut. Runs ~/.local/bin/lid-sleep; state shows in the bar via the
-- LidAwake indicator in ajisrael.indicators.
o.bind("SUPER + CTRL + ALT + S", "Lid sleep toggle", "lid-sleep")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
