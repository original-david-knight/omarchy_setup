
get_monitor_count() {
    # Run hyprctl monitors and count lines starting with "Monitor"
    count=$(hyprctl monitors | grep -c '^Monitor')
    echo "$count"
}

stow --target=../  bash

monitor_count=$(get_monitor_count)
if [ "$monitor_count" -gt 1 ]; then
    stow --target=../  ghostty_big_screen
else
    stow --target=../  ghostty
fi

stow --target=../  tmux
stow --target=../ hypr
stow --target=../ starship



