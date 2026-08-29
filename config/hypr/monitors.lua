-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 1.6

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Internal laptop display.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })

-- External monitor, extended to the right of the laptop display.
-- eDP-1 is 2560px wide at scale 1.6 => 1600 logical px, so HDMI starts at x=1600.
--
-- Setup on right
-- hl.monitor({ output = "HDMI-A-2", mode = "preferred", position = "1600x0", scale = 1 })

-- Setup on left
hl.monitor({ output = "HDMI-A-2", mode = "preferred", position = "-1920x0", scale = 1 })

-- Fallback for any other plugged-in monitor not configured above.
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
