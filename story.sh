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
  cat <<"EOF"
  ___  _     _      _                                     _      
 / _ \| |   | |    | |                                   | |     
/ /_\ \ | __| | ___| |__   __ _ _ __ __ _ _ __   ___   __| | ___ 
|  _  | |/ _` |/ _ \ '_ \ / _` | '__/ _` | '_ \ / _ \ / _` |/ _ \
| | | | | (_| |  __/ |_) | (_| | | | (_| | | | | (_) | (_| |  __/
\_| |_/_|\__,_|\___|_.__/ \__,_|_|  \__,_|_| |_|\___/ \__,_|\___|
EOF
}

echo_new_step() {
  local step_message=$1
  echo -e "${COLOR_BLUE}=== ${step_message} ===${COLOR_RESET}"
}

get_latest_version() {
  local repo=$1
  curl -s "https://api.github.com/repos/piplabs/$repo/releases/latest" | jq -r '.tag_name'
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

install_prerequisites() {
  echo_new_step "Installing prerequisites"
  sudo apt update -q
  sudo apt install -y -qq make unzip clang pkg-config lz4 libssl-dev build-essential git jq ncdu bsdmainutils htop aria2
  install_go
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
  ARCH_TYPE=$(echo $ARCH_TYPE | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
  GETH_NAME="geth-${OS_TYPE}-${ARCH_TYPE}"
  DOWNLOAD_URL="https://github.com/piplabs/story-geth/releases/download/v0.9.4/${GETH_NAME}"
  wget $DOWNLOAD_URL
  sudo chmod +x $GETH_NAME
  sudo mv $GETH_NAME /usr/local/bin/story-geth
  story-geth version
}

# Function to check if a port is in use
is_port_in_use() {
  local port=$1
  if lsof -i:$port >/dev/null; then
    return 0
  else
    return 1
  fi
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

  prompt_change_port
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

install_using_cosmovisor() {
  echo_new_step "Installing using cosmovisor"
  if ! command -v go >/dev/null; then
    read -p "Go is not installed. Do you want to install it? (y/n): " response
    [ "$response" = "y" ] && install_go || {
      echo -e "${COLOR_RED}Go installation is required. Exiting script.${COLOR_RESET}"
      exit 1
    }
  else
    echo -e "${COLOR_GREEN}Go is already installed. Version: $(go version)${COLOR_RESET}"
  fi
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
  command -v cosmovisor >/dev/null || {
    echo -e "${COLOR_RED}Cosmovisor is not installed. Exiting script.${COLOR_RESET}"
    exit 1
  }
  cosmovisor version
  DAEMON_NAME=$DAEMON_NAME DAEMON_HOME=$DAEMON_HOME cosmovisor init "$(which story)"
}

update_port_in_config() {
  local default_port=$1
  local new_port=$2
  sed -i -e "s|:$default_port\"|:$new_port\"|g" "$INSTALLATION_DIR/config.toml"
}

prompt_change_port() {
  echo_new_step "Configuring custom ports"

  declare -A default_ports=(
    ["http_port"]=8545
    ["ws_port"]=8546
    ["rpc_port"]=26657
    ["p2p_port"]=26656
    ["api_port"]=1317
    ["grpc_port"]=26658
  )

  declare -A port_descriptions=(
    ["http_port"]="HTTP port for story-geth"
    ["ws_port"]="WebSocket port for story-geth"
    ["rpc_port"]="RPC port for cometbft"
    ["p2p_port"]="P2P port for cometbft"
    ["api_port"]="API port for cometbft"
    ["grpc_port"]="GRPC port for cometbft"
  )

  for port in "${!default_ports[@]}"; do
    read -p "Enter the desired ${port_descriptions[$port]} (default: ${default_ports[$port]}): " input_port
    declare "$port=${input_port:-${default_ports[$port]}}"
  done

  declare -A port_mappings=(
    ["26656"]="$p2p_port"
    ["1317"]="$api_port"
    ["26658"]="$grpc_port"
    ["26657"]="$rpc_port"
  )

  for key in "${!port_mappings[@]}"; do
    update_port_in_config "$key" "${port_mappings[$key]}"
  done

  config_files=(
    "$INSTALLATION_DIR/ecosystem.config.js"
    "/etc/system/systemd/story-geth.service"
  )

  for config_file in "${config_files[@]}"; do
    if [ -f "$config_file" ]; then
      sed -i -e "s|--http.port 8545|--http.port $http_port|g" "$config_file"
      sed -i -e "s|--ws.port 8546|--ws.port $ws_port|g" "$config_file"
    else
      echo -e "${COLOR_RED}File $config_file not found. Skipping port configuration.${COLOR_RESET}"
    fi
  done

  echo -e "${COLOR_GREEN}Ports configured: P2P port - $p2p_port, API port - $api_port, GRPC port - $grpc_port, RPC port - $rpc_port, HTTP port - $http_port, WebSocket port - $ws_port${COLOR_RESET}"
}

create_story_service() {
  echo_new_step "Creating systemd service for Story Node"
  command -v story >/dev/null || {
    echo -e "${COLOR_RED}Story binary is not available. Please ensure it is installed correctly.${COLOR_RESET}"
    exit 1
  }
  command -v story-geth >/dev/null || {
    echo -e "${COLOR_RED}Story-geth binary is not available. Please ensure it is installed correctly.${COLOR_RESET}"
    exit 1
  }

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

  prompt_change_port

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

  prompt_change_port

  pm2 start "$INSTALLATION_DIR/ecosystem.config.js"
  pm2 pid story && echo -e "${COLOR_GREEN}Story is running${COLOR_RESET}" || echo -e "${COLOR_RED}Story is not running${COLOR_RESET}"
  pm2 pid story-geth && echo -e "${COLOR_GREEN}Story geth is running${COLOR_RESET}" || echo -e "${COLOR_RED}Story geth is not running${COLOR_RESET}"
}

backup_config_files() {
  echo -e "${COLOR_YELLOW}Backing up configuration files...${COLOR_RESET}"
  cp $STORY_DIR/story/data/priv_validator_state.json $STORY_DIR/priv_validator_state.json.backup
  echo -e "${COLOR_GREEN}Backup completed successfully.${COLOR_RESET}"
}

remove_old_data() {
  echo -e "${COLOR_YELLOW}Removing old data...${COLOR_RESET}"
  rm -rf $STORY_DIR/story/data
  rm -rf $STORY_DIR/geth/iliad/geth/chaindata
  rm -rf $DAEMON_HOME/data
  echo -e "${COLOR_GREEN}Old data removed successfully.${COLOR_RESET}"
}

extract_snapshot() {
  echo_new_step "Extracting snapshot"
  # Check if the backup exists before proceeding
  if [ ! -f "$STORY_DIR/priv_validator_state.json.backup" ]; then
    echo -e "${COLOR_RED}Backup file not found. Please ensure you have a backup before extracting.${COLOR_RESET}"
    exit 1
  fi

  # Extract the story snapshot
  echo -e "${COLOR_YELLOW}Extracting story snapshot...${COLOR_RESET}"
  tar -xzvf story_snapshot.tar.gz -C $STORY_DIR/story/data
  echo -e "${COLOR_GREEN}Story snapshot extracted successfully.${COLOR_RESET}"

  # Extract the geth snapshot
  echo -e "${COLOR_YELLOW}Extracting geth snapshot...${COLOR_RESET}"
  tar -xzvf geth_snapshot.tar.gz -C $STORY_DIR/geth/iliad/geth/chaindata
  echo -e "${COLOR_GREEN}Geth snapshot extracted successfully.${COLOR_RESET}"
}

install_using_pm2() {
  echo_new_step "Installing using pm2"
  install_all_in_one
  install_pm2
  create_pm2_service
}

install_default() {
  echo_new_step "Begin default installation"
  install_all_in_one
  install_using_cosmovisor
  create_story_service
}

apply_snapshot() {
  echo_new_step "Applying snapshot"
  read -p "Please enter the story snapshot download URL: " STORY_SNAPSHOT_URL
  if [ -z "$STORY_SNAPSHOT_URL" ]; then
    echo -e "${COLOR_RED}Snapshot URL is unavailable. Exiting.${COLOR_RESET}"
    exit 1
  fi
  read -p "Please enter the story geth snapshot download URL: " STORY_GETH_SNAPSHOT_URL
  if [ -z "$STORY_GETH_SNAPSHOT_URL" ]; then
    echo -e "${COLOR_RED}Snapshot URL is unavailable. Exiting.${COLOR_RESET}"
    exit 1
  fi
  echo "Downloading snapshots simultaneously from ${COLOR_BLUE}${STORY_GETH_SNAPSHOT_URL}${COLOR_RESET} and ${COLOR_BLUE}${STORY_SNAPSHOT_URL}${COLOR_RESET}"
  aria2c -x 16 -s 16 -k 2M $STORY_GETH_SNAPSHOT_URL $STORY_SNAPSHOT_URL
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

select_option
