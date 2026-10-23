# Persist the syntax-highlighting theme. `fish_config theme choose` only
# affects the current session, so re-apply it on every interactive start.
if status is-interactive
    fish_config theme choose catppuccin-frappe 2>/dev/null
    set -g fish_color_autosuggestion 545454
end
