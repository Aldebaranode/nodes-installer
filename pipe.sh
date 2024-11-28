#!/bin/bash

SERVICE_DIR="/opt/dcdn"
SYSTEMD_FILE="/etc/systemd/system/dcdnd.service"
REGISTRY_URL="https://rpc.pipedev.network"

# Exit on errors
set -e

# Function to prompt for URLs
prompt_urls() {
    read -p "Enter the Pipe URL: " PIPE_URL
    read -p "Enter the DCDND URL: " DCDND_URL
}

# Function to prompt for ports and check if they are in use
prompt_ports() {
    while true; do
        read -p "Enter the gRPC Port (default 8002): " GRPC_PORT
        GRPC_PORT=${GRPC_PORT:-8002}
        if lsof -i:$GRPC_PORT >/dev/null; then
            echo "Port $GRPC_PORT is already in use. Please choose another port."
        else
            break
        fi
    done

    while true; do
        read -p "Enter the HTTP Port (default 8003): " HTTP_PORT
        HTTP_PORT=${HTTP_PORT:-8003}
        if lsof -i:$HTTP_PORT >/dev/null; then
            echo "Port $HTTP_PORT is already in use. Please choose another port."
        else
            break
        fi
    done
}

# Function to prompt for service user
prompt_service_user() {
    echo "Choose the service user to run the DCDN service:"
    echo "1) Current user ($(whoami))"
    echo "2) Dedicated dcdn-svc-user"
    read -p "Enter your choice (1 or 2): " USER_CHOICE

    if [ "$USER_CHOICE" -eq 1 ]; then
        SERVICE_USER=$(whoami)
        SERVICE_GROUP=$(id -gn)
        PERMISSIONLESS_DIR="/home/$SERVICE_USER/.permissionless"
        echo "Using current user: $SERVICE_USER"
    elif [ "$USER_CHOICE" -eq 2 ]; then
        SERVICE_USER="dcdn-svc-user"
        SERVICE_GROUP="dcdn-svc-user"
        PERMISSIONLESS_DIR="/home/$SERVICE_USER/.permissionless"
        echo "Creating and using dedicated service account: $SERVICE_USER"
        create_service_user
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
}

# Function to create dedicated service user
create_service_user() {
    sudo useradd -r -m -s /sbin/nologin $SERVICE_USER || echo "User already exists"
    sudo mkdir -p $PERMISSIONLESS_DIR
    sudo chown -R $SERVICE_USER:$SERVICE_GROUP $PERMISSIONLESS_DIR
}

# Function to download binaries
download_binaries() {
    echo "Creating directory: $SERVICE_DIR"
    sudo mkdir -p $SERVICE_DIR

    echo "Downloading pipe-tool binary..."
    sudo curl -L "$PIPE_URL" -o $SERVICE_DIR/pipe-tool

    echo "Downloading dcdnd binary..."
    sudo curl -L "$DCDND_URL" -o $SERVICE_DIR/dcdnd

    echo "Making binaries executable..."
    sudo chmod +x $SERVICE_DIR/pipe-tool
    sudo chmod +x $SERVICE_DIR/dcdnd
}

# Function to create systemd service file
create_service_file() {
    echo "Creating systemd service file..."
    sudo bash -c "cat > $SYSTEMD_FILE" << EOF
[Unit]
Description=DCDN Node Service
After=network.target
Wants=network-online.target

[Service]
ExecStart=$SERVICE_DIR/dcdnd \\
    --grpc-server-url=0.0.0.0:$GRPC_PORT \\
    --http-server-url=0.0.0.0:$HTTP_PORT \\
    --node-registry-url="$REGISTRY_URL" \\
    --cache-max-capacity-mb=1024 \\
    --credentials-dir=$PERMISSIONLESS_DIR \\
    --allow-origin=*

Restart=always
RestartSec=5

LimitNOFILE=65536
LimitNPROC=4096

StandardOutput=journal
StandardError=journal
SyslogIdentifier=dcdn-node

WorkingDirectory=$SERVICE_DIR
User=$SERVICE_USER
Group=$SERVICE_GROUP

[Install]
WantedBy=multi-user.target
EOF
}

# Function to configure firewall
configure_firewall() {
    echo "Opening required ports..."
    sudo ufw allow $GRPC_PORT/tcp
    sudo ufw allow $HTTP_PORT/tcp
    sudo ufw reload
}

# Function to enable and start the service
enable_and_start_service() {
    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    echo "Enabling dcdnd service at boot..."
    sudo systemctl enable dcdnd

    echo "Starting dcdnd service..."
    sudo systemctl start dcdnd

    echo "Checking service status..."
    sudo systemctl status dcdnd --no-pager
}

echo_manually_steps() {
    echo "Next steps:"
    echo "1. To log in to the pipe tool, use the following command:"
    echo "${SERVICE_DIR}/pipe-tool login --node-registry-url=\"${REGISTRY_URL}\" --credentials-dir=\"${PERMISSIONLESS_DIR}\""

    echo "2. Generate a registration token, use the following command:"
    echo "${SERVICE_DIR}/pipe-tool generate-registration-token --node-registry-url=\"${REGISTRY_URL}\" --credentials-dir=\"${PERMISSIONLESS_DIR}\""

    echo "3. Generate a wallet, use the following command:"
    echo "${SERVICE_DIR}/pipe-tool generate-wallet --node-registry-url=\"${REGISTRY_URL}\" --credentials-dir=\"${PERMISSIONLESS_DIR}\" --key-path=\"${PERMISSIONLESS_DIR}\""

    echo "4. Link a wallet to your node, use the following command:"
    echo "${SERVICE_DIR}/pipe-tool link-wallet --node-registry-url=\"${REGISTRY_URL}\" --credentials-dir=\"${PERMISSIONLESS_DIR}\" --key-path=\"${PERMISSIONLESS_DIR}\""

    echo "5. To restart the service, use the following command:"
    echo "sudo systemctl restart dcdnd"

    echo "6. To check the status of the service, use the following command:"
    echo "sudo systemctl status dcdnd --no-pager"

    echo "7. List all nodes registered, use the following command:"
    echo "${SERVICE_DIR}/pipe-tool list-nodes --node-registry-url=\"${REGISTRY_URL}\" --credentials-dir=\"${PERMISSIONLESS_DIR}\""
}

# Main execution flow
main() {

    # Prompts
    prompt_urls
    prompt_ports
    prompt_service_user

    # Operations
    download_binaries
    create_service_file
    configure_firewall
    enable_and_start_service
    echo_manually_steps
}

# Run the script
main
