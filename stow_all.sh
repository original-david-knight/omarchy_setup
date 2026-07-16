
get_monitor_count() {
    # Run hyprctl monitors and count lines starting with "Monitor"
    count=$(hyprctl monitors | grep -c '^Monitor')
    echo "$count"
}

rm ~/.bashrc
stow --target=../  bash

rm -rf ../.config/ghostty
monitor_count=$(get_monitor_count)
echo $monitor_count
if [ "$monitor_count" -gt 1 ]; then
    stow --target=../  ghostty_big_screen
else
    stow --target=../  ghostty
fi

stow --target=../  tmux
stow --target=../  zellij
stow --target=../  omarchy
rm -rf ../.config/hypr
stow --target=../ hypr
rm -rf ../.config/starship*
stow --target=../ starship
stow --target=../ ssh
# --no-folding keeps ~/bin a real directory of individual symlinks so the
# laptop-only bin_laptop package can't be dropped by stow re-folding the tree.
stow --no-folding --target=../ bin

# Touchpad auto-toggle is laptop-only; skip on multi-monitor (desktop) setups
if [ "$monitor_count" -le 1 ]; then
  stow --no-folding --target=../ bin_laptop
fi

rm -rf ../.config/waybar

if [ "$monitor_count" -gt 1 ]; then
  stow --target=../ waybar
else
  stow --target=../ waybar_laptop
fi
mkdir -p ../.config/Code/User
stow --target=../ vscode
