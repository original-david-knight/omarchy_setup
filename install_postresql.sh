yay -S --noconfirm --needed postgresql
if ! sudo test -f /var/lib/postgres/data/PG_VERSION; then
  sudo -u postgres initdb --locale en_US.UTF-8 -D /var/lib/postgres/data
fi
sudo systemctl enable --now postgresql

# Create superuser role for current user with peer auth (no password needed)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$USER'" | grep -q 1; then
  sudo -u postgres createuser --superuser "$USER"
fi
