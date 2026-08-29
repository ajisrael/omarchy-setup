# ble.sh (Bash Line Editor) personal config - inline autosuggestions + syntax
# highlighting (fish/zsh-style) for omarchy's bash. This is ble.sh's stock
# config path (~/.config/blesh/init.sh), read by ble.sh itself when it loads -
# never source it from .bashrc.
#
# Prompt untouched: starship still renders its full prompt unchanged, and ble's
# syntax/auto-complete colors use ANSI palette names, so they track the current
# omarchy theme exactly like the rest of the shell.

# fzf (C-t / C-r / alt-c) is wired by omarchy's default/bash/init through
# readline `bind`, but ble.sh replaces readline with its own keymap. Restate it
# through ble's integration modules. -d defers them to the background after the
# prompt renders, keeping attach cheap.
ble-import -d integration/fzf-completion
ble-import -d integration/fzf-key-bindings

# bashrc-personal's `bind -x '"\C-f": tmux-sessionizer'` is a readline bind and
# is inert under ble.sh; mirror it (same semantics as readline's bind -x).
ble-bind -x 'C-f' 'tmux-sessionizer'

# Keep omarchy's inputrc feel: up/down search history by what's already typed.
# (ble.sh's default is 'backward-line history', which is close; bind the exact
# widgets omarchy's inputrc used.)
ble-bind -f up 'history-search-backward'
ble-bind -f down 'history-search-forward'

# Startup: don't read the whole history file until first use (plain bash reads
# it lazily; ble.sh otherwise does it eagerly at attach).
bleopt history_lazyload=1

# Keep auto-complete cheap on this machine: cap the candidate scan and the
# glob timeout so heavy completions (pacman/paru/make/man) never stall typing.
bleopt complete_limit_auto=100
bleopt complete_timeout_auto=100