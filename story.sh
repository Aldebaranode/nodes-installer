#!/bin/sh

STORY_DIR="$HOME/.story"
DAEMON_HOME="$STORY_DIR/story"
DAEMON_NAME="story"
CHAIN_ID="iliad"
MONIKER="Story Validator"
INSTALLATION_DIR="$HOME/nodes-installer/story"

GETH_SERVICE_NAME="story-geth"
STORY_SERVICE_NAME=$DAEMON_NAME

DEFAULT_GETH_HTTP_PORT=8545
DEFAULT_GETH_WS_PORT=8546
DEFAULT_COMET_RPC_PORT=26657
DEFAULT_COMET_P2P_PORT=26656
DEFAULT_COMET_API_PORT=1317
DEFAULT_COMET_GRPC_PORT=26658

NEW_GETH_HTTP_PORT=$DEFAULT_GETH_HTTP_PORT
NEW_GETH_WS_PORT=$DEFAULT_GETH_WS_PORT
NEW_COMET_RPC_PORT=$DEFAULT_COMET_RPC_PORT
NEW_COMET_P2P_PORT=$DEFAULT_COMET_P2P_PORT
NEW_COMET_API_PORT=$DEFAULT_COMET_API_PORT
NEW_COMET_GRPC_PORT=$DEFAULT_COMET_GRPC_PORT

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

change_story_dir() {
  echo_new_step "Changing story directory"
  read -p "Enter the new directory for your story installation (current: ${STORY_DIR}): " new_story_dir
  new_story_dir=$(eval echo "$new_story_dir")  # Expand variables like $HOME to their actual values
  if [ -n "$new_story_dir" ]; then
    STORY_DIR="$new_story_dir"
    DAEMON_HOME="$STORY_DIR/story"
    echo -e "${COLOR_GREEN}Story directory changed to: ${STORY_DIR}${COLOR_RESET}"
  else
    echo -e "${COLOR_YELLOW}Story directory remains unchanged: ${STORY_DIR}${COLOR_RESET}"
  fi
}

prompt_change_port() {
  echo_new_step "Configuring custom ports"

  read -p "Do you want to change the default ports or use the default settings? (Enter 'y' to modify or 'n' to keep default ports): " change_ports
  if [ "$change_ports" != "y" ]; then
    echo -e "${COLOR_GREEN}Using default ports: HTTP port - $DEFAULT_GETH_HTTP_PORT, WebSocket port - $DEFAULT_GETH_WS_PORT, RPC port - $DEFAULT_COMET_RPC_PORT, P2P port - $DEFAULT_COMET_P2P_PORT, API port - $DEFAULT_COMET_API_PORT, GRPC port - $DEFAULT_COMET_GRPC_PORT.${COLOR_RESET}"
    return
  fi

  declare -A ports=(
    ["HTTP port"]=$DEFAULT_GETH_HTTP_PORT
    ["WebSocket port"]=$DEFAULT_GETH_WS_PORT
    ["RPC port"]=$DEFAULT_COMET_RPC_PORT
    ["P2P port"]=$DEFAULT_COMET_P2P_PORT
    ["API port"]=$DEFAULT_COMET_API_PORT
    ["GRPC port"]=$DEFAULT_COMET_GRPC_PORT
  )

  for port_description in "${!ports[@]}"; do
    while true; do
      read -p "Enter the desired $port_description (default: ${ports[$port_description]}): " input_port
      input_port=${input_port:-${ports[$port_description]}}
      if ! is_port_in_use "$input_port"; then
        ports[$port_description]=$input_port
        break
      else
        echo -e "${COLOR_RED}Port $input_port is already in use. Please choose a different port.${COLOR_RESET}"
      fi
    done
  done

  NEW_GETH_HTTP_PORT=${ports["HTTP port"]}
  NEW_GETH_WS_PORT=${ports["WebSocket port"]}
  NEW_COMET_RPC_PORT=${ports["RPC port"]}
  NEW_COMET_P2P_PORT=${ports["P2P port"]}
  NEW_COMET_API_PORT=${ports["API port"]}
  NEW_COMET_GRPC_PORT=${ports["GRPC port"]}
}

prepare_configuration() {
  echo_new_step "Preparing configuration"
  
  # Check if the configuration file exists
  CONFIG_FILE="$DAEMON_HOME/config/config.toml"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${COLOR_RED}Configuration file not found at $CONFIG_FILE. Exiting.${COLOR_RESET}"
    exit 1
  fi
  APP_CONFIG_FILE="$DAEMON_HOME/config/story.toml"
  if [ ! -f "$APP_CONFIG_FILE" ]; then
    echo -e "${COLOR_RED}App configuration file not found at $APP_CONFIG_FILE. Exiting.${COLOR_RESET}"
    exit 1
  fi

  # Update the configuration file with custom settings
  echo -e "${COLOR_YELLOW}Updating configuration file...${COLOR_RESET}"
  
  # Set the engine JWT file path
  sed -i "s|^engine-jwt-file =.*|engine-jwt-file = \"${STORY_DIR}/geth/iliad/geth/jwtsecret\"|" "$APP_CONFIG_FILE"

  # Update the configuration file with the custom ports
  sed -i -e "s|:$DEFAULT_COMET_RPC_PORT\"|:$NEW_COMET_RPC_PORT\"|g" "$CONFIG_FILE"
  sed -i -e "s|:$DEFAULT_COMET_P2P_PORT\"|:$NEW_COMET_P2P_PORT\"|g" "$CONFIG_FILE"
  sed -i -e "s|:$DEFAULT_COMET_API_PORT\"|:$NEW_COMET_API_PORT\"|g" "$CONFIG_FILE"
  sed -i -e "s|:$DEFAULT_COMET_GRPC_PORT\"|:$NEW_COMET_GRPC_PORT\"|g" "$CONFIG_FILE"

  echo -e "${COLOR_GREEN}Configuration updated successfully.${COLOR_RESET}"
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

  change_story_dir
  story init --network $CHAIN_ID --moniker $MONIKER --home $DAEMON_HOME
  prepare_configuration
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

prompt_service_name() {
  read -p "Please enter the service name for Story Node [default: $STORY_SERVICE_NAME]: " input_story_service_name
  STORY_SERVICE_NAME=${input_story_service_name:-$STORY_SERVICE_NAME}
  
  read -p "Please enter the service name for Story Geth [default: $GETH_SERVICE_NAME]: " input_geth_service_name
  GETH_SERVICE_NAME=${input_geth_service_name:-$GETH_SERVICE_NAME}
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
  sudo tee /etc/systemd/system/${STORY_SERVICE_NAME}.service >/dev/null <<EOF
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
  sudo tee /etc/systemd/system/${GETH_SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=Story execution daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which story-geth) --iliad --syncmode full --http --http.addr 0.0.0.0 --http.port $NEW_GETH_HTTP_PORT --ws --ws.addr 0.0.0.0 --ws.port $NEW_GETH_WS_PORT --http.vhosts=* --datadir $STORY_DIR/geth/iliad
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
  sudo systemctl enable ${GETH_SERVICE_NAME}.service
  sudo systemctl enable ${STORY_SERVICE_NAME}.service
  sudo systemctl restart ${GETH_SERVICE_NAME}.service
  sudo systemctl restart ${STORY_SERVICE_NAME}.service

  echo -e "${COLOR_GREEN}Systemd services enabled and restarted successfully.${COLOR_RESET}"

  echo_new_step "Checking node status"
  sleep 5
  echo -e "${COLOR_YELLOW}Checking if Story Node is running...${COLOR_RESET}"
  sudo systemctl is-active --quiet $STORY_SERVICE_NAME.service && echo -e "${COLOR_GREEN}Story Node is running.${COLOR_RESET}" || echo -e "${COLOR_RED}Story Node is not running.${COLOR_RESET}"

  echo -e "${COLOR_YELLOW}Checking if Story Geth is running...${COLOR_RESET}"
  sudo systemctl is-active --quiet $GETH_SERVICE_NAME.service && echo -e "${COLOR_GREEN}Story Geth is running.${COLOR_RESET}" || echo -e "${COLOR_RED}Story Geth is not running.${COLOR_RESET}"
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
      name: "${STORY_SERVICE_NAME}",         
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
      name: "${GETH_SERVICE_NAME}",         
      script: gethPath,                
      args: "--iliad --syncmode full --http --http.addr 0.0.0.0 --http.port $NEW_GETH_HTTP_PORT --ws --ws.addr 0.0.0.0 --ws.port $NEW_GETH_WS_PORT --http.vhosts=* --datadir $STORY_DIR/geth/iliad",                     
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
  pm2 pid $STORY_SERVICE_NAME && echo -e "${COLOR_GREEN}Story is running${COLOR_RESET}" || echo -e "${COLOR_RED}Story is not running${COLOR_RESET}"
  pm2 pid $GETH_SERVICE_NAME && echo -e "${COLOR_GREEN}Story geth is running${COLOR_RESET}" || echo -e "${COLOR_RED}Story geth is not running${COLOR_RESET}"
}

backup_config_files() {
  echo -e "${COLOR_YELLOW}Backing up configuration files...${COLOR_RESET}"
  cp $STORY_DIR/story/data/priv_validator_state.json $STORY_DIR/priv_validator_state.json.backup
  echo -e "${COLOR_GREEN}Backup completed successfully.${COLOR_RESET}"
}

restore_config_files() {
  echo -e "${COLOR_YELLOW}Restoring configuration files...${COLOR_RESET}"
  if [ -f "$STORY_DIR/priv_validator_state.json.backup" ]; then
    cp $STORY_DIR/priv_validator_state.json.backup $STORY_DIR/story/data/priv_validator_state.json
    echo -e "${COLOR_GREEN}Configuration files restored successfully.${COLOR_RESET}"
  else
    echo -e "${COLOR_RED}Backup file not found. Cannot restore configuration files.${COLOR_RESET}"
  fi
}

remove_old_data() {
  echo -e "${COLOR_YELLOW}Removing old data...${COLOR_RESET}"
  rm -rf $STORY_DIR/story/data
  rm -rf $STORY_DIR/geth/iliad/geth/chaindata
  echo -e "${COLOR_GREEN}Old data removed successfully.${COLOR_RESET}"
}

stop_services() {
  echo_new_step "Stopping services and pm2 processes"
  if systemctl is-active --quiet ${GETH_SERVICE_NAME}.service; then
    sudo systemctl stop ${GETH_SERVICE_NAME}.service
  fi

  if systemctl is-active --quiet ${STORY_SERVICE_NAME}.service; then
    sudo systemctl stop ${STORY_SERVICE_NAME}.service
  fi
  if command -v pm2 >/dev/null; then
    if pm2 list | grep -q $STORY_SERVICE_NAME; then
      pm2 stop $STORY_SERVICE_NAME
    fi
    if pm2 list | grep -q $GETH_SERVICE_NAME; then
      pm2 stop $GETH_SERVICE_NAME
    fi
  fi
  echo -e "${COLOR_GREEN}Services processes stopped successfully.${COLOR_RESET}"
}

start_services() {
  echo_new_step "Starting services"
  if systemctl is-active --quiet ${GETH_SERVICE_NAME}.service; then
    sudo systemctl start ${GETH_SERVICE_NAME}.service
  fi
  if systemctl is-active --quiet ${STORY_SERVICE_NAME}.service; then
    sudo systemctl start ${STORY_SERVICE_NAME}.service
  fi
  if command -v pm2 >/dev/null; then
    if pm2 list | grep -q $STORY_SERVICE_NAME; then
      pm2 start $STORY_SERVICE_NAME
    fi
    if pm2 list | grep -q $GETH_SERVICE_NAME; then
      pm2 start $GETH_SERVICE_NAME
    fi
  fi
  echo -e "${COLOR_GREEN}Services started successfully.${COLOR_RESET}"
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
  lz4 -d -c Story_snapshot.lz4 | pv | sudo tar xv -C $STORY_DIR/story/ > /dev/null
  echo -e "${COLOR_GREEN}Story snapshot extracted successfully.${COLOR_RESET}"

  # Extract the geth snapshot
  echo -e "${COLOR_YELLOW}Extracting geth snapshot...${COLOR_RESET}"
  lz4 -d -c Geth_snapshot.lz4 | pv | sudo tar xv -C $STORY_DIR/geth/iliad/geth/ > /dev/null
  echo -e "${COLOR_GREEN}Geth snapshot extracted successfully.${COLOR_RESET}"
}

install_using_pm2() {
  echo_new_step "Installing using pm2"
  install_all_in_one
  install_pm2
  prompt_service_name
  create_pm2_service
  prompt_apply_snapshot
}

install_default() {
  echo_new_step "Begin default installation"
  install_all_in_one
  install_using_cosmovisor
  prompt_service_name
  create_story_service
  prompt_apply_snapshot
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
  (echo $STORY_SNAPSHOT_URL; echo $STORY_GETH_SNAPSHOT_URL) | aria2c -x 16 -s 16 -k 1M -i -

  prompt_service_name

  stop_services
  backup_config_files
  remove_old_data
  extract_snapshot
  restore_config_files
  start_services
}

prompt_apply_snapshot() {
  echo_new_step "Prompt to Apply Snapshot"
  read -p "Do you want to apply a snapshot? (y/n): " apply_snapshot_choice
  case $apply_snapshot_choice in
    y|Y) apply_snapshot ;;
    *) echo -e "${COLOR_YELLOW}Skipping snapshot application.${COLOR_RESET}" ;;
  esac
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
