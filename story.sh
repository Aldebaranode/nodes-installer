#!/bin/sh

STORY_DIR="$HOME/.story"
DAEMON_HOME="$STORY_DIR/story"
DAEMON_NAME="story"
CHAIN_ID="iliad"
MONIKER="Story Validator"
INSTALLATION_DIR="$HOME/nodes-installer/story"

# Define color variables
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_RESET="\e[0m"

print_logo() {
  cat << "EOF"
  ___  _     _      _                                     _      
 / _ \| |   | |    | |                                   | |     
/ /_\ \ | __| | ___| |__   __ _ _ __ __ _ _ __   ___   __| | ___ 
|  _  | |/ _` |/ _ \ '_ \ / _` | '__/ _` | '_ \ / _ \ / _` |/ _ \
| | | | | (_| |  __/ |_) | (_| | | | (_| | | | | (_) | (_| |  __/
\_| |_/_|\__,_|\___|_.__/ \__,_|_|  \__,_|_| |_|\___/ \__,_|\___|
EOF
}

get_latest_version() {
  local repo=$1
  curl -s "https://api.github.com/repos/piplabs/$repo/releases/latest" | jq -r '.tag_name'
}

select_option() {
  print_logo
  echo -e "${COLOR_BLUE}\nStory Protocol Installer\n${COLOR_RESET}"
  echo "Please select an option:"
  echo "1. Install (default: systemd)"
  echo "2. Install using pm2"
  echo "3. Apply snapshot"
  read -p "Enter your choice [1-3]: " choice

  case $choice in
    1) install_default ;;
    2) install_using_pm2 ;;
    3) apply_snapshot ;;
    *) echo -e "${COLOR_RED}Invalid option. Please try again.${COLOR_RESET}" ;;
  esac
}

install_default() {
  echo_new_step "Begin default installation"
  install_all_in_one
  install_using_cosmovisor
  create_story_service
}

install_all_in_one() {
  echo_new_step "Installing all components"
  [ ! -d "$INSTALLATION_DIR" ] && mkdir -p "$INSTALLATION_DIR" || {
    echo -e "${COLOR_YELLOW}Installation directory already exists.${COLOR_RESET}"
    read -p "Do you want to delete and recreate it? (y/n): " response
    [ "$response" = "y" ] && rm -rf "$INSTALLATION_DIR" && mkdir -p "$INSTALLATION_DIR" && echo -e "${COLOR_GREEN}Installation directory has been recreated.${COLOR_RESET}"
  }
  cd "$INSTALLATION_DIR"
  install_prerequisites
  install_story_and_geth
}

install_prerequisites() {
  echo_new_step "Installing prerequisites"
  sudo apt update -q
  sudo apt install -y -qq make unzip clang pkg-config lz4 libssl-dev build-essential git jq ncdu bsdmainutils htop
  install_go
}

install_go() {
  echo_new_step "Installing the latest version of Go"
  GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n1)
  wget "https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz"
  sudo tar -C /usr/local -xzf "${GO_VERSION}.linux-amd64.tar.gz"
  rm "${GO_VERSION}.linux-amd64.tar.gz"
  {
    echo "export GOROOT=/usr/local/go"
    echo "export GOPATH=\$HOME/go"
    echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin"
  } >>~/.profile
  source ~/.profile
  echo -e "${COLOR_GREEN}Go installation completed. Version: $(go version)${COLOR_RESET}"
}

install_story_and_geth() {
  echo_new_step "Installing story & geth"
  download_story
  download_geth
  story version
  story-geth version
  read -p "Enter the moniker for your node (default: ${MONIKER}): " input_moniker
  [ -n "$input_moniker" ] && MONIKER="$input_moniker"
  echo -e "${COLOR_GREEN}Using moniker: ${MONIKER}${COLOR_RESET}"
  story init --network $CHAIN_ID --moniker $MONIKER
}

download_story() {
  echo_new_step "Downloading story"
  STORY_VERSION=$(get_latest_version "story")
  STORY_NAME="story-linux-amd64-0.11.0-aac4bfe"
  STORY_DOWNLOAD_URL="https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/${STORY_NAME}.tar.gz"
  wget $STORY_DOWNLOAD_URL
  tar -xzvf "${STORY_NAME}.tar.gz"
  sudo chmod +x "${STORY_NAME}/story"
  sudo mv "${STORY_NAME}/story" /usr/local/bin/
}

download_geth() {
  echo_new_step "Downloading geth"
  OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH_TYPE=$(uname -m)
  ARCH_TYPE=${ARCH_TYPE/x86_64/amd64}
  ARCH_TYPE=${ARCH_TYPE/aarch64/arm64}
  GETH_NAME="geth-${OS_TYPE}-${ARCH_TYPE}"
  DOWNLOAD_URL="https://github.com/piplabs/story-geth/releases/download/v0.9.4/${GETH_NAME}"
  wget $DOWNLOAD_URL
  sudo chmod +x $GETH_NAME
  sudo mv $GETH_NAME /usr/local/bin/story-geth
  story-geth version
}

install_using_cosmovisor() {
  echo_new_step "Installing using cosmovisor"
  if ! command -v go >/dev/null; then
    read -p "Go is not installed. Do you want to install it? (y/n): " response
    [ "$response" = "y" ] && install_go || { echo -e "${COLOR_RED}Go installation is required. Exiting script.${COLOR_RESET}"; exit 1; }
  else
    echo -e "${COLOR_GREEN}Go is already installed. Version: $(go version)${COLOR_RESET}"
  fi
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
  command -v cosmovisor >/dev/null || { echo -e "${COLOR_RED}Cosmovisor is not installed. Exiting script.${COLOR_RESET}"; exit 1; }
  cosmovisor version
  DAEMON_NAME=$DAEMON_NAME DAEMON_HOME=$DAEMON_HOME cosmovisor init "$(which story)"
}

install_using_pm2() {
  echo_new_step "Installing using pm2"
  install_all_in_one
  install_pm2
  create_pm2_service
}

install_pm2() {
  echo_new_step "Installing pm2"
  wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm install --lts
  npm install -g pm2
}

create_pm2_service() {
  echo_new_step "Creating pm2 service"
  sudo tee "$INSTALLATION_DIR/ecosystem.config.js" >/dev/null <<EOF
const { execSync } = require("child_process");

const cosmovisorPath = execSync("which cosmovisor").toString().trim();
const gethPath = execSync("which story-geth").toString().trim();

module.exports = {
  apps: [
    {
      name: "story",         
      script: cosmovisorPath,               
      args: "run run",                     
      cwd: "${DAEMON_HOME}",
      env: {
        DAEMON_NAME: "${DAEMON_NAME}",                
        DAEMON_HOME: "${DAEMON_HOME}",
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
      cwd: "${STORY_DIR}/geth",  
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

  pm2 start "$INSTALLATION_DIR/ecosystem.config.js"
  pm2 pid story && echo -e "${COLOR_GREEN}Story is running${COLOR_RESET}" || echo -e "${COLOR_RED}Story is not running${COLOR_RESET}"
  pm2 pid story-geth && echo -e "${COLOR_GREEN}Story geth is running${COLOR_RESET}" || echo -e "${COLOR_RED}Story geth is not running${COLOR_RESET}"
}

create_story_service() {
  echo_new_step "Creating systemd service for Story Node"
  command -v story >/dev/null || { echo -e "${COLOR_RED}Story binary is not available. Please ensure it is installed correctly.${COLOR_RESET}"; exit 1; }
  command -v story-geth >/dev/null || { echo -e "${COLOR_RED}Story-geth binary is not available. Please ensure it is installed correctly.${COLOR_RESET}"; exit 1; }

  echo -e "${COLOR_YELLOW}Creating systemd service for Story Node...${COLOR_RESET}"
  sudo tee /etc/systemd/system/story.service >/dev/null <<EOF
[Unit]
Description=Cosmovisor Story Node
After=network-online.target

[Service]
User=$USER
Type=simple
WorkingDirectory=${DAEMON_HOME}
ExecStart=$(which cosmovisor) run run
Restart=on-failure
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity
Environment="DAEMON_NAME=${DAEMON_NAME}"
Environment="DAEMON_HOME=${DAEMON_HOME}"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=$PATH"

[Install]
WantedBy=multi-user.target
EOF
  echo -e "${COLOR_GREEN}Systemd service for Story Node created successfully.${COLOR_RESET}"

  echo_new_step "Creating systemd service for Story Geth"
  sudo tee /etc/systemd/system/story-geth.service >/dev/null <<EOF
[Unit]
Description=Story execution daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which story-geth) --iliad --syncmode full --http --http.addr 0.0.0.0 --http.port 8545 --ws --ws.addr 0.0.0.0 --ws.port 8546 --http.vhosts=*
Restart=always
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity
Environment="PATH=$PATH"

[Install]
WantedBy=multi-user.target
EOF
  echo -e "${COLOR_GREEN}Systemd service for Story Geth created successfully.${COLOR_RESET}"

  echo_new_step "Enabling and starting systemd services"
  sudo systemctl enable story-geth.service
  sudo systemctl enable story.service
  sudo systemctl restart story-geth.service
  sudo systemctl restart story.service

  echo -e "${COLOR_GREEN}Systemd services enabled and restarted successfully.${COLOR_RESET}"

  echo_new_step "Checking node status"
  sleep 5
  echo -e "${COLOR_YELLOW}Checking if Story Node is running...${COLOR_RESET}"
  sudo systemctl is-active --quiet story.service && echo -e "${COLOR_GREEN}Story Node is running.${COLOR_RESET}" || echo -e "${COLOR_RED}Story Node is not running.${COLOR_RESET}"

  echo -e "${COLOR_YELLOW}Checking if Story Geth is running...${COLOR_RESET}"
  sudo systemctl is-active --quiet story-geth.service && echo -e "${COLOR_GREEN}Story Geth is running.${COLOR_RESET}" || echo -e "${COLOR_RED}Story Geth is not running.${COLOR_RESET}"
}

echo_new_step() {
  local step_message=$1
  echo -e "${COLOR_BLUE}=== ${step_message} ===${COLOR_RESET}"
}

select_option
