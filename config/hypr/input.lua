-- Personal input overrides. Loaded after Omarchy defaults - uncommented
-- settings here replace them. Everything else inherits Omarchy's stock
-- values (scroll_factor 0.4, disable_while_typing, etc.).

hl.config({
  input = {
    -- Omarchy's default is "compose:caps,shift:both_capslock_cancel": it turns
    -- Caps Lock into the Compose (multi-key macro) key, so Caps+m s types an
    -- emoji, and relocates real Caps Lock onto both-Shifts. Blank kb_options
    -- drops both, so Caps Lock is a plain toggle again. The emoji/identity
    -- sequences in ~/.XCompose stop being reachable, which is the point.
    kb_options = "",

    touchpad = {
      -- macOS muscle memory from archeus.
      natural_scroll = true,
      -- Physical click, not tap.
      tap_to_click = false,
    },
  },
})
