#!/bin/sh

STORY_DIR="$HOME/.story"
DAEMON_HOME="$STORY_DIR/story"
DAEMON_NAME="story"
CHAIN_ID="iliad"
MONIKER="Story Validator"

INSTALLATION_DIR="$HOME/nodes-installer/story"

print_logo() {
  echo "  ___  _     _      _                                     _      "
  echo " / _ \| |   | |    | |                                   | |     "
  echo "/ /_\ \ | __| | ___| |__   __ _ _ __ __ _ _ __   ___   __| | ___ "
  echo "|  _  | |/ _\` |/ _ \ '_ \ / _\` | '__/ _\` | '_ \ / _ \ / _\` |/ _ \\"
  echo "| | | | | (_| |  __/ |_) | (_| | | | (_| | | | | (_) | (_| |  __/"
  echo "\_| |_/_|\__,_|\___|_.__/ \__,_|_|  \__,_|_| |_|\___/ \__,_|\___|"
}

get_story_version() {
  curl -s https://api.github.com/repos/piplabs/story/releases/latest | jq -r '.tag_name'
}

get_geth_version() {
  curl -s https://api.github.com/repos/piplabs/story-geth/releases/latest | jq -r '.tag_name'
}

select_option() {
  print_logo
  echo ""
  echo "Story Protocol Installer"
  echo ""
  echo "Please select an option:"
  echo "1. Install (default: systemd)"
  echo "2. Install using pm2"
  echo "3. Apply snapshot"
  read -p "Enter your choice [1-3]: " choice

  case $choice in
  1)
    install_default
    ;;
  2)
    install_using_pm2
    ;;
  3)
    apply_snapshot
    ;;
  *)
    echo "Invalid option. Please try again."
    ;;
  esac
}

install_default() {
  echo "Begin default installation..."
  install_all_in_one
  install_using_cosmovisor
  create_story_service
  check_node_status
}

install_all_in_one() {
  echo "Installing all components..."
  if [ ! -d "$INSTALLATION_DIR" ]; then
    mkdir -p "$INSTALLATION_DIR"
  else
    echo "Installation directory already exists."
    read -p "Do you want to delete and recreate it? (y/n): " response
    if [ "$response" = "y" ]; then
      rm -rf "$INSTALLATION_DIR"
      mkdir -p "$INSTALLATION_DIR"
      echo "Installation directory has been recreated."
    else
      echo "Using existing installation directory."
    fi
  fi
  cd "$INSTALLATION_DIR"
  install_prerequisites
  install_story_and_geth
}

install_prerequisites() {
  echo "Installing prerequisites..."
  sudo apt update -q
  sudo apt install make unzip clang pkg-config lz4 libssl-dev build-essential git jq ncdu bsdmainutils htop -y -qq

  # Add installation commands here
  install_go
}

install_go() {
  echo "Installing the latest version of Go..."
  GO_VERSION=$(curl https://go.dev/VERSION?m=text | head -n1)
  wget https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz
  tar -C /usr/local -xzf ${GO_VERSION}.linux-amd64.tar.gz
  rm ${GO_VERSION}.linux-amd64.tar.gz
  echo "export PATH=\$PATH:/usr/local/go/bin" >>~/.profile
  source ~/.profile
  echo "Go installation completed. Version: $(go version)"
}

install_story_and_geth() {
  echo "Installing story & geth..."
  # Add installation commands here

  STORY_VERSION=$(get_story_version)
  STORY_NAME="story-linux-amd64-0.11.0-aac4bfe"
  STORY_DOWNLOAD_URL="https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/${STORY_NAME}.tar.gz"

  wget $STORY_DOWNLOAD_URL
  tar -xzvf $STORY_NAME.tar.gz
  sudo chmod +x $STORY_NAME/story
  sudo mv $STORY_NAME/story /usr/local/bin/

  story version
}

download_geth() {
  OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH_TYPE=$(uname -m)

  if [ "$ARCH_TYPE" = "x86_64" ]; then
    ARCH_TYPE="amd64"
  elif [ "$ARCH_TYPE" = "aarch64" ]; then
    ARCH_TYPE="arm64"
  fi

  GETH_NAME="geth-${OS_TYPE}-${ARCH_TYPE}"
  DOWNLOAD_URL="https://github.com/piplabs/story-geth/releases/download/v0.9.4/${GETH_NAME}"
  wget $DOWNLOAD_URL
  sudo chmod +x $GETH_NAME
  sudo mv $GETH_NAME /usr/local/bin/story-geth
  story-geth version
}

install_using_cosmovisor() {
  echo "Installing using cosmovisor..."
  if ! command -v go >/dev/null; then
    read -p "Go is not installed. Do you want to install it? (y/n): " response
    if [ "$response" = "y" ]; then
      install_go
    else
      echo "Go installation is required. Exiting script."
      exit 1
    fi
  else
    echo "Go is already installed. Version: $(go version)"
  fi

  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
  cosmovisor version

  cosmovisor DAEMON_NAME=$DAEMON_NAME DAEMON_HOME=$DAEMON_HOME cosmovisor init $(which story)
}

install_using_pm2() {
  echo "Installing using pm2..."
  install_all_in_one
  install_pm2
  create_pm2_service
}

install_pm2() {
  wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

  nvm install --lts
  npm install -g pm2
}

create_pm2_service() {
  sudo tee $INSTALLATION_DIR/ecosystem.config.js >/dev/null <<EOF
const { execSync } = require("child_process");

const cosmovisorPath = execSync("which cosmovisor").toString().trim();
const gethPath = execSync("which story-geth").toString().trim();

module.exports = {
  apps: [
    {
      name: "story",         
      script: cosmovisorPath,               
      args: "run start",                     
      cwd: "$DAEMON_HOME",
      env: {
        DAEMON_NAME: "$DAEMON_NAME",                
        DAEMON_HOME: "$DAEMON_HOME",
        UNSAFE_SKIP_BACKUP: "true",
        PATH: process.env.PATH               
      },
      autorestart: true,                     
      restart_delay: 3000,                   
      max_restarts: 10,                      
      instances: 1,                          
      exec_mode: "fork",                     
      max_open_files: "infinity",            
      max_procs: "infinity"                 
    },
    {
      name: "story-geth",         
      script: gethPath,                
      args: "--iliad --syncmode full --http --http.addr 0.0.0.0 --http.port 8545 --ws --ws.addr 0.0.0.0 --ws.port 8546 --http.vhosts=*",                     
      cwd: "$STORY_DIR/geth",  
      env: {
        PATH: process.env.PATH              
      },
      autorestart: true,                   
      restart_delay: 3000,                
      max_restarts: 10,                  
      instances: 1,                     
      exec_mode: "fork",               
      max_open_files: "infinity",     
      max_procs: "infinity"         
    }
  ]
};
EOF

  pm2 start $INSTALLATION_DIR/ecosystem.config.js
  if pm2 pid story; then
    echo "Story is running"
  else
    echo "Story is not running"
  fi
  if pm2 pid story-geth; then
    echo "Story geth is running"
  else
    echo "Story geth is not running"
  fi
}

create_story_service() {
  if ! command -v story >/dev/null; then
    echo "Story binary is not available. Please ensure it is installed correctly."
    exit 1
  fi

  if ! command -v story-geth >/dev/null; then
    echo "Story-geth binary is not available. Please ensure it is installed correctly."
    exit 1
  fi

  echo "Creating systemd service for Story Node..."
  sudo tee /etc/systemd/system/story.service >/dev/null <<EOF
[Unit]
Description=Cosmovisor Story Node
After=network-online.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$DAEMON_HOME
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity
Environment="DAEMON_NAME=$DAEMON_NAME"
Environment="DAEMON_HOME=$DAEMON_HOME"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF
  echo "Systemd service for Story Node created successfully."

  echo "Creating systemd service for Story Geth..."
  sudo tee /etc/systemd/system/story-geth.service >/dev/null <<EOF
[Unit]
Description=Story execution daemon
After=network-online.target

[Service]
User=aldebaranode
ExecStart=$(which story-geth) --iliad --syncmode full --http --http.addr 0.0.0.0 --http.port 8545 --ws --ws.addr 0.0.0.0 --ws.port 8546 --http.vhosts=*
Restart=always
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
EOF
  echo "Systemd service for Story Geth created successfully."

  echo "Enabling and starting systemd services..."

  # Enable the systemd services
  sudo systemctl enable story-geth.service
  sudo systemctl enable story.service

  # Restart the systemd services
  sudo systemctl restart story-geth.service
  sudo systemctl restart story.service

  echo "Systemd services enabled and restarted successfully."

  echo "Checking node status..."
  sleep 5
  echo "Checking if Story Node is running..."
  if sudo systemctl is-active --quiet story.service; then
    echo "Story Node is running."
  else
    echo "Story Node is not running."
  fi

  echo "Checking if Story Geth is running..."
  if sudo systemctl is-active --quiet story-geth.service; then
    echo "Story Geth is running."
  else
    echo "Story Geth is not running."
  fi
}

# Call the function to start the selection process
select_option
