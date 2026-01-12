yay -S --noconfirm --needed postgresql
if ! sudo test -f /var/lib/postgres/data/PG_VERSION; then
  sudo -u postgres initdb --locale en_US.UTF-8 -D /var/lib/postgres/data
fi
sudo systemctl enable postgresql
