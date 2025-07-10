#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: [myhrmans]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/spliit-app/spliit

# App Default Values
APP="spliit"
var_tags="finance;expense-tracking"
var_cpu="1"
var_ram="1024"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  
  if [[ ! -d /opt/spliit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  
  # Get latest release
  RELEASE=$(curl -fsSL https://api.github.com/repos/spliit-app/spliit/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  
  # If no release tag found, use latest commit from main branch
  if [[ -z "$RELEASE" ]]; then
    msg_info "No release tags found, checking latest commit..."
    RELEASE=$(curl -fsSL https://api.github.com/repos/spliit-app/spliit/commits/main | grep '"sha"' | head -1 | awk '{print substr($2, 2, 7)}')
    RELEASE_TYPE="commit"
  else
    RELEASE_TYPE="tag"
  fi
  
  # Check current version
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE_TYPE} ${RELEASE}"
    
    # Backup current installation
    msg_info "Backing up current installation..."
    cp -r /opt/spliit /opt/spliit-backup
    
    # Stop the service
    systemctl stop spliit
    
    # Update the application
    cd /opt/spliit
    git fetch --all &>/dev/null
    if [[ "$RELEASE_TYPE" == "tag" ]]; then
      git checkout "tags/${RELEASE}" &>/dev/null
    else
      git pull origin main &>/dev/null
    fi
    
    # Install dependencies and run migrations
    export NODE_ENV=production
    npm ci --only=production &>/dev/null
    npm run build &>/dev/null
    npx prisma migrate deploy &>/dev/null
    
    # Update version file
    echo "${RELEASE}" >/opt/${APP}_version.txt
    
    # Start the service
    systemctl start spliit
    
    # Clean up backup if successful
    if systemctl is-active --quiet spliit; then
      rm -rf /opt/spliit-backup
      msg_ok "Updated ${APP} to ${RELEASE_TYPE} ${RELEASE}"
    else
      msg_error "Update failed, restoring backup..."
      rm -rf /opt/spliit
      mv /opt/spliit-backup /opt/spliit
      systemctl start spliit
      exit 1
    fi
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE_TYPE} ${RELEASE}."
  fi
  
  # Update OS packages
  msg_info "Updating OS packages"
  apt-get update &>/dev/null
  apt-get -y upgrade &>/dev/null
  msg_ok "Updated OS packages"
  
  exit
}

# Start installation
start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
