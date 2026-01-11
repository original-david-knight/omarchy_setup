mkdir -p /home/$USER/workspace

if [ ! -d /home/$USER/workspace/davidknight ]; then
  git clone git@github.com:original-david-knight/davidknight.git /home/$USER/workspace/davidknight
fi

if [ ! -d /home/$USER/workspace/wilder ]; then
  git clone --bare git@github.com:original-david-knight/wilder.git /home/$USER/workspace/wilder
fi

if [ ! -d /home/$USER/workspace/wilder/main ]; then
  git -C /home/$USER/workspace/wilder worktree add main main
fi
