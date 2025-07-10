#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/spliit-app/spliit

# Import Functions and Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  git \
  gnupg \
  ca-certificates \
  postgresql \
  postgresql-contrib \
  openssl
msg_ok "Installed Dependencies"

# Install Node.js 20
msg_info "Installing Node.js"
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - &>/dev/null
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

# Setting up PostgreSQL Database
msg_info "Setting up Database"
DB_NAME=spliit_db
DB_USER=spliit_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

# Start PostgreSQL
systemctl start postgresql &>/dev/null
systemctl enable postgresql &>/dev/null

# Create database and user
sudo -u postgres psql <<EOF &>/dev/null
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
\q
EOF

# Grant schema permissions
sudo -u postgres psql -d $DB_NAME <<EOF &>/dev/null
GRANT ALL ON SCHEMA public TO $DB_USER;
\q
EOF

{
  echo "Spliit Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
} >>~/spliit.creds
msg_ok "Set up Database"

# Test database connection
msg_info "Testing database connection"
PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -h localhost -c '\q' &>/dev/null
if [ $? -eq 0 ]; then
  msg_ok "Database connection successful"
else
  msg_error "Database connection failed"
  exit 1
fi

# Setup Spliit Application
msg_info "Setting up Spliit"
cd /opt

# Clone repository
git clone https://github.com/spliit-app/spliit.git &>/dev/null
cd spliit

# Get latest release or commit info for version tracking
RELEASE=$(curl -fsSL https://api.github.com/repos/spliit-app/spliit/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
if [[ -z "$RELEASE" ]]; then
  RELEASE=$(git rev-parse --short HEAD)
fi
echo "${RELEASE}" >/opt/spliit_version.txt

# Create .env file with all required variables
NEXTAUTH_SECRET=$(openssl rand -base64 32)
POSTGRES_URL="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}?schema=public"

cat <<EOF >/opt/spliit/.env
DATABASE_URL="${POSTGRES_URL}"
POSTGRES_PRISMA_URL="${POSTGRES_URL}"
POSTGRES_URL_NON_POOLING="${POSTGRES_URL}"
NEXTAUTH_SECRET="${NEXTAUTH_SECRET}"
NEXTAUTH_URL="http://localhost:3000"
NEXT_PUBLIC_BASE_URL="http://localhost:3000"
NODE_ENV="production"
EOF

msg_info "Database URL configured"

# Install dependencies and build
msg_info "Installing npm dependencies (this may take a while)..."
cd /opt/spliit
export NODE_OPTIONS="--max-old-space-size=2048"
$STD npm install
msg_info "Building application..."
$STD NODE_ENV=production npm run build
msg_info "Pruning development dependencies..."
$STD npm prune --production
msg_ok "Set up Spliit"

# Creating Service
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/spliit.service
[Unit]
Description=Spliit Application
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spliit
Environment="NODE_ENV=production"
Environment="PORT=3000"
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now spliit
msg_ok "Created Service"

# Update .env with actual container IP
CONTAINER_IP=$(hostname -I | awk '{print $1}')
sed -i "s|http://localhost:3000|http://${CONTAINER_IP}:3000|g" /opt/spliit/.env

# Add credentials info
{
  echo ""
  echo "Web Interface: http://${CONTAINER_IP}:3000"
  echo "Default Port: 3000"
} >>~/spliit.creds

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"