#!/bin/bash

printLogo()
{
  echo ""
  echo ""
  echo "  ██████╗   ██████╗   ██████╗ ██╗  ██╗ ███████╗ ████████╗"
  echo "  ██╔══██╗ ██╔═══██╗ ██╔════╝ ██║ ██╔╝ ██╔════╝ ╚══██╔══╝"
  echo "  ██████╔╝ ██║   ██║ ██║      █████╔╝  █████╗      ██║ "
  echo "  ██╔══██╗ ██║   ██║ ██║      ██╔═██╗  ██╔══╝      ██║ "
  echo "  ██║  ██║ ╚██████╔╝ ╚██████╗ ██║  ██╗ ███████╗    ██║ "
  echo "  ╚═╝  ╚═╝  ╚═════╝   ╚═════╝ ╚═╝  ╚═╝ ╚══════╝    ╚═╝ "
  echo ""
}

# Variables Initialization


# SSH
ssh_dir="/home/$USER/.ssh"
ssh_keys_dir="keys"

# WEBHOOKS
webhook_port=9000
webhook_config_git_repo="git@github.com:fedeiglesiasc/server-webhooks.git"


# COLORS
red=$'\e[1;31m'
green=$'\e[1;32m'
yellow=$'\e[1;33m'
blue=$'\e[1;34m'
magenta=$'\e[1;35m'
cyan=$'\e[1;36m'
end=$'\e[0m'

working()
{
  printf "\r [ ${blue}WORKING${end} ] "
}

ok()
{
  printf "\r [ ${green}OK${end} ] "
}

error()
{
  printf "\r [ ${red}ERROR${end} ] "
}

warning()
{
  printf "\r [ ${yellow}WARNING${end} ] "
}

info()
{
  printf "\r [ ${cyan}INFO${end} ] "
}

nl()
{
  printf "                                \n"
} 


updateYUM() 
{
  # Update YUM
  working && printf "Updating YUM ..."
  sudo yum -y update 2>&1 >/dev/null
  ok && printf "YUM is updated" && nl

  # Upgrade YUM
  working && printf "Upgrading YUM ..."
  sudo yum -y upgrade 2>&1 >/dev/null
  ok && printf "YUM is upgraded" && nl

  #Remove orphan packages  
  working && printf "Clean orphan packages ..."
  sudo yum -y autoremove 2>&1 >/dev/null
  ok && printf "YUM is clean" && nl
}

installGolang()
{
  # Install Golang
  working && printf "Installing Golang ..."

  {
    # Get LTS version
    GOLANG_VERSION="`wget -qO- https://golang.org/VERSION?m=text`"
    # Move to tmp
    cd /tmp
    # Get installer
    wget https://dl.google.com/go/$GOLANG_VERSION.linux-amd64.tar.gz --quiet
    # decompress
    sudo tar -C /usr/local -xzf $GOLANG_VERSION.linux-amd64.tar.gz
    # install 
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    # remove tmp files
    rm -rf $GOLANG_VERSION.linux-amd64.tar.gz
    # move to home
    cd ~/

  } 2>/dev/null

  # All go ok
  ok && printf "Golang is installed" && nl
}

installWebhook()
{
  # Install Nginx
  installGit

  # Install Golang
  installGolang

  # Install Webhook
  working && printf "Installing Webhook ..."
  go get github.com/adnanh/webhook 2>/dev/null
  ok && printf "Webhook installed successfull" && nl

  # Create directory structure
  mkdir -p ~/webhooks 2>/dev/null
  mkdir -p ~/webhooks/hooks 2>/dev/null

  # Check for port is used
  working && printf "Checking if port $webhook_port is used ..."
  if lsof -Pi :webhook_port -sTCP:LISTEN -t 2>/dev/null ;
  then
    error && printf "Port $webhook_port is used" && nl
  else
    ok && printf "Port $webhook_port is free" && nl
  fi
  #TODO ASK FOR OTHER PORT

  # Add webhook in crontab
  working && printf "Adding Webhook to UpStart ..."
  # Add service to UpStart
  sudo tee -a /etc/init/webhook.conf >/dev/null <<'EOF'
      description "A Webhook server to run with Github"
      author "Federico Iglesias Colombo"
      start on runlevel [2345]
      exec /home/$USER/go/bin/webhook -hooks /home/$USER/webhooks/main/hook.json -hooks /home/$USER/webhooks/hooks/*/hook.json -ip '127.0.0.1'
EOF

  # Start service
  sudo initctl start webhook
  # All go ok
  ok && printf "Webhook added to UpStart" && nl
}

configWebhooksFromGit() 
{
  
  # Add configure startup webhook project
  working && printf "Installing Feature: Set Webhooks from Git ..."
  
  # Create directory structure
  mkdir -p ~/webhooks 2>/dev/null
  mkdir -p ~/webhooks/main 2>/dev/null
  mkdir -p ~/webhooks/hooks 2>/dev/null

  # Create main hook file
  cat > ~/webhooks/main/hook.json << EOF
    [
      {
        "id": "webhooks",
        "execute-command": "/home/$USER/webhooks/main/script.sh",
        "command-working-directory": "/home/$USER/webhooks/hooks/",
        "response-message": "Executing deploy script..."
      }
    ]
EOF

  # Create main shell script file
  cat > ~/webhooks/main/script.sh << EOF
    #!/bin/bash

    git fetch --all
    git checkout --force "origin/master"

    # give permission to all hooks scripts
    chmod +x ~/webhooks/hooks/*/script.sh

    # Restart service webhooks to get changes
EOF

  # set permission to execute file
  chmod +x ~/webhooks/main/script.sh

  # Set remote repo to hooks dir
  cd ~/webhooks/hooks && git init --quiet 2>/dev/null
  git remote add origin $webhook_config_git_repo ~/ 2>/dev/null && cd ~/ 2>/dev/null

  # All go ok
  ok && printf "Feature created: Set Webhooks from Git" && nl
}

createSSHKeysDir()
{
  {
    # SSH dir
    ssh_dir="/home/$USER/.ssh"

    # if .ssh dir not exist create it 
    mkdir -p $ssh_dir $ssh_dir/$ssh_keys_dir
    # Home directory on the server should not be writable by others
    chmod go-w /home/$USER
    # SSH folder on the server needs 700 permissions: 
    chmod 700 $ssh_dir $ssh_dir/$ssh_keys_dir
    # Authorized_keys file needs 644 permissions: 
    chmod 644 $ssh_dir/authorized_keys
    # Make sure that user owns the files/folders and not root: 
    chown $USER $ssh_dir/authorized_keys
    chown $USER $ssh_dir $ssh_dir
    # Restart SSH service
    service ssh restart

  } 2>/dev/null

  # Put the generated public key (from ssh-keygen) in the user's authorized_keys file on the server
}

createSSHKey()
{
  # Create SSH KEY
  working && printf "Generating SSH KEY ..."

  # create ssh key 
  yes y |ssh-keygen -f $ssh_dir/$ssh_keys_dir/id_$1 -N "" >/dev/null

  # Inform public key
  info && printf "SSH Keys created! here is your public key: " && nl

  # Show it
  cat $ssh_dir/$ssh_keys_dir/id_$1.pub
}

configSSHKeys()
{
  # Add configure startup webhook project
  working && printf "Config SSH Public Keys ..."
  # Create keys dir
  mkdir -p ~/.ssh/keys
  # Add webhook in crontab
  #CC="@reboot eval \"\$(ssh-agent -s)\" && for f in \$(ls ~/.ssh/keys/ --hide='*.pub'); do ssh-add ~/.ssh/keys/\$f; done"
  #CC1="@reboot eval \" \$(ssh-agent -s)\" "
  # Add to Crontab ONLY if not exist alredy and without show errors
  #! (crontab -l 2>/dev/null | grep -q "$CC1") && (crontab -l 2>/dev/null; echo $CC1) | crontab -
  # All go ok
  ok && printf "SSH Public Keys configured" && nl
}


installGit()
{
  working && printf "Installing GIT ..."
  sudo yum -y install git 2>&1 >/dev/null
  ok && printf "GIT installed successfull" && nl
}

installNginx()
{
  # Install Nginx
  working && printf "Installing Nginx ..."
  sudo yum -y install nginx 2>&1 >/dev/null
  # Add Nginx to startup
  sudo chkconfig nginx on 2>&1 >/dev/null
  # All go ok
  ok && printf "Nginx installed successfull" && nl
}


installNVM()
{
  #Install LTS version of NVM
  working && printf "Installing NVM ..."
  
  # Support to get the latest version auto from source
  sudo yum -y install epel-release 2>/dev/null
  sudo yum -y install jq 2>/dev/null

  # LTS
  VER=$(curl -s 'https://api.github.com/repos/nvm-sh/nvm/releases/latest' | jq -r '.tag_name') 2>/dev/null

  # Install nvm
  curl --silent --output /dev/null https://raw.githubusercontent.com/nvm-sh/nvm/$VER/install.sh | bash 
  
  # restart bash
  source ~/.bashrc

  # All go ok
  ok && printf "NVM installed successfull" && nl
}

installNode()
{
  # Install LTS version of Node
  working && printf "Installing Node ..."

  nvm install --lts 2>/dev/null

  # All go ok
  ok && printf "Node installed successfull" && nl
}


printLogo

updateYUM

installWebhook