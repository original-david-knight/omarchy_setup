if [ ! -f ~/.ssh/id_github ]; then
    ssh-keygen -t ed25519 -C david@knight.fm -P "" -f ~/.ssh/id_github
fi
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_github
echo "github pub ssh key:\n"
cat ~/.ssh/id_github.pub

