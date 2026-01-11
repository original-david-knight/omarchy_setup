yay -S --noconfirm --needed wget
wget https://dot.net/v1/dotnet-install.sh 
chmod +x dotnet-install.sh
mv dotnet-install.sh /home/$USER/bin
dotnet-install.sh --version 8.0.416

