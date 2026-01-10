alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias u='cd ..'
alias uu='cd ../..'
alias uuu='cd ../../..'


alias gs='git status'
alias p='git status'
alias gc='git commit -a -m '
alias gco='git checkout'
alias gb='git branch'


alias e='nvim'
alias blaze='bazel'


# Colorize grep output (good for log files)
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# adding flags
alias df='df -h'                          # human-readable sizes
alias free='free -m'                      # show sizes in MB
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
## get top process eating cpu ##
alias pscpu='ps auxf | sort -nr -k 3'


# get error messages from journalctl
alias jctl="journalctl -p 3 -xb"
alias startvpn_kr="sudo openvpn /etc/openvpn/client/se-kr-01.protonvpn.com.udp.ovpn"
alias startvpn_usa="sudo openvpn /etc/openvpn/client/USA_no_core.ovpn"


