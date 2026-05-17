# ── ALT+number alternatives for byobu F-key bindings ─────────────────────────
# These mirror byobu's default F-key functions so they remain accessible when
# the host application (Claude Code, Gemini CLI, etc.) intercepts F-keys before
# tmux sees them.
#
# Mapping: ALT+<n>  ≡  F<n>
#
# ALT+digit sends ESC+digit (\e<n>) which every terminal passes through reliably,
# including podman/docker exec sessions, SSH tunnels, etc.
# (CTRL+digit was tried first but is unreliable: CTRL+2=NUL, CTRL+3=ESC,
#  CTRL+9/0 send bare digits — all collide with other uses or can't be captured.)

# ALT+2  →  F2   new window
bind-key -n M-2 new-window

# ALT+3  →  F3   previous window
bind-key -n M-3 previous-window

# ALT+4  →  F4   next window
bind-key -n M-4 next-window

# ALT+5  →  F5   reload byobu config
bind-key -n M-5 source-file ~/.byobu/.tmux.conf

# ALT+6  →  F6   detach session
bind-key -n M-6 detach-client

# ALT+7  →  F7   enter scrollback / copy mode
bind-key -n M-7 copy-mode

# ALT+8  →  F8   rename current window
bind-key -n M-8 command-prompt -p "(rename-window)" -I "#W" "rename-window '%%'"

# ALT+9  →  F9   byobu configuration menu
bind-key -n M-9 run-shell "byobu-config"

# ALT+0  →  F11  toggle zoom (maximize / restore current pane)
bind-key -n M-0 resize-pane -Z
