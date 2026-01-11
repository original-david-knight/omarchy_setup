
get_monitor_count() {
    # Run hyprctl monitors and count lines starting with "Monitor"
    count=$(hyprctl monitors | grep -c '^Monitor')
    echo "$count"
}

rm ~/.bashrc
stow --target=../  bash

rm -rf ../.config/ghostty
monitor_count=$(get_monitor_count)
if [ "$monitor_count" -gt 1 ]; then
    stow --target=../  ghostty_big_screen
else
    stow --target=../  ghostty
fi

stow --target=../  tmux
rm -rf ../.config/hypr
stow --target=../ hypr
rm -rf ../.config/starship*
stow --target=../ starship
stow --target=../ ssh
stow --target=../ bin
rm -rf ../.config/waybar
stow --target=../ waybar
# rm ../.config/Code
stow --target=../ vscode


