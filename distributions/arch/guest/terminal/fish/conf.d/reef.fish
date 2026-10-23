# Enable the reef bash-compatibility layer when it is installed. reef ships
# disabled by default and needs an explicit `reef on`; the guard keeps fish
# usable when the optional AUR package is absent.
if status is-interactive
    reef on 2>/dev/null
end
