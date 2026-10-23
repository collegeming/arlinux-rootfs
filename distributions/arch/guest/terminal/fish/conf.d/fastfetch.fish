# Show fastfetch once per top-level interactive shell. SHLVL is 1 for the
# first interactive shell and grows for every nested one, which keeps subshells
# from repainting the screen.
if status is-interactive
    if test "$SHLVL" -eq 1
        if type -q fastfetch
            fastfetch
        end
    end
end
