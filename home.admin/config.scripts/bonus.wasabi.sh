#!/bin/bash

# Wasabi Backend/Coordinator deployment bonus script for RaspiBlitz v1.11.4 (26/01/2025)
WasabiVersion="v2.5.1"

PGPsigner="web-flow"
PGPpubkeyLink="https://github.com/web-flow.gpg"
PGPpubkeyFingerprint="6FB3872B5D42292F59920797856348328949861E"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch Wasabi Coordinator/Backend on or off"
  echo "bonus.wasabi.sh [on|off]"
  echo "enables/disables the coordinator and backend"
  echo "bonus.wasabi.sh [install|uninstall]"
  echo "installs Wasabi Wallet $WasabiVersion"
  echo "To update to the latest release published on github run:"
  echo "bonus.wasabi.sh update"
  echo
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
# get cpu architecture (checked with 'uname -m')
source /home/admin/raspiblitz.info
source <(/home/admin/_cache.sh get state)

function CoordinatorService() {
  echo "# create the wasabicoordinator.service"
  echo "
[Unit]
Description=Wasabi Coordinator daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
ExecStart=/home/wasabi/dotnet/dotnet run \
 -c Release --project \"/home/wasabi/WalletWasabi/WalletWasabi.Coordinator/WalletWasabi.Coordinator.csproj\"
User=wasabi
Group=wasabi
Type=simple
PIDFile=/run/wasabi/wasabicoordinator.pid
Restart=always
RestartSec=10

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/wasabicoordinator.service
  sudo systemctl daemon-reload
}

function BackendService() {
  echo "# create the wasabibackend.service"
  echo "
[Unit]
Description=Wasabi Backend daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
ExecStart=/home/wasabi/dotnet/dotnet run \
 -c Release --project \"/home/wasabi/WalletWasabi/WalletWasabi.Backend/WalletWasabi.Backend.csproj\"
User=wasabi
Group=wasabi
Type=simple
PIDFile=/run/wasabi/wasabibackend.pid
Restart=always
RestartSec=10

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/wasabibackend.service
  sudo systemctl daemon-reload
}

########################################
# INSTALL (just user, code & compile)
########################################

if [ "$1" = "install" ]; then

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c wasabi)
  if [ "${isInstalled}" != "0" ]; then
    echo "# already installed"
    exit 0
  fi

    echo "# create wasabi user"
    sudo adduser --system --group --home /home/wasabi wasabi
    cd /home/wasabi || exit 1

    # Clone repository
    sudo -u wasabi git clone https://github.com/WalletWasabi/WalletWasabi.git

    # Install latest dotnet SDK 8.0
    sudo -u wasabi wget https://download.visualstudio.microsoft.com/download/pr/bb17a3ab-7122-41bd-96cf-33e35b1d4318/7b09327fdd49b7130cf94838f2979aa6/dotnet-sdk-8.0.405-linux-arm64.tar.gz
    
    # Verify download hash
    expectedHash="07988b784bf71913f607ce0ced50434c69980ae715ca62fb6af68f7eaa26810c3f9ffe24df1d8706d1a557c3eb7756143e5357016089cf1508714baa1cce828a"
    actualHash=$(sha512sum dotnet-sdk-8.0.405-linux-arm64.tar.gz | cut -d' ' -f1)
    if [ "$actualHash" != "$expectedHash" ]; then
      echo "Error: Downloaded file hash does not match expected hash."
      exit 1
    fi

    sudo mkdir -p $HOME/dotnet && tar zxf dotnet-sdk-8.0.405-linux-arm64.tar.gz -C $HOME/dotnet
    export DOTNET_ROOT=$HOME/dotnet
    export PATH=$PATH:$HOME/dotnet

    # Remove downloaded tar/zip file
    sudo rm dotnet-sdk-8.0.405-linux-arm64.tar.gz

    # Disable telemetry
    export DOTNET_CLI_TELEMETRY_OPTOUT=1

    # Build Wasabi Backend
    echo "build Wasabi Backend"
    cd /home/wasabi/WalletWasabi/WalletWasabi.Backend/
    sudo -u wasabi $HOME/dotnet/dotnet build -c Release \
      /home/wasabi/WalletWasabi/WalletWasabi.Backend/WalletWasabi.Backend.csproj || exit 1


    # Build Wasabi Coordinator
    echo "build Wasabi Coordinator"
    cd /home/wasabi/WalletWasabi/WalletWasabi.Coordinator
    sudo -u wasabi $HOME/dotnet/dotnet build -c Release \
      /home/wasabi/WalletWasabi/WalletWasabi.Coordinator/WalletWasabi.Coordinator.csproj || exit 1

    echo "# make sure wasabi is member of the bitcoin group"
    sudo /usr/sbin/usermod --append --groups bitcoin wasabi
    exit 0
    echo "Finished installing Wasabi Backend & Coordinator! Happy Co 🕶️"
fi

########################################
# UNINSTALL (remove from system)
########################################

if [ "$1" = "uninstall" ]; then

  isActive=$(sudo ls /etc/systemd/system/wasabicoordinator.service 2>/dev/null | grep -c 'wasabicoordinator.service')
  if [ "${isActive}" != "0" ]; then
    echo "# cannot uninstall if still 'on'"
    exit 1
  fi

  # clear dotnet cache
  /home/wasabi/dotnet/dotnet nuget locals all --clear 2>/dev/null

  # remove dotnet
  sudo rm -rf /usr/share/dotnet 2>/dev/null

  # nuke user
  sudo userdel -rf wasabi 2>/dev/null

  echo "# uninstall done"

  exit 0
fi
########################################
# UPDATE (pull latest master branch)
########################################
echo "# Update Wasabi Wallet"
sudo -r wasabi git pull -p 

########################################
# ON (activate & config)
########################################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  CoordinatorService
  sudo systemctl enable wasabicoordinator
  sudo systemctl start wasabicoordinator

  BackendService
  sudo systemctl enable wasabibackend
  sudo systemctl start wasabibackend
fi
########################################
# OFF (deactivate)
########################################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # removing service: wasabicoordinator
  sudo systemctl stop wasabicoordinator
  sudo systemctl disable wasabicoordinator
  sudo rm /etc/systemd/system/wasabicoordinator.service
  # removing service: wasabibackend
  sudo systemctl stop wasabibackend
  sudo systemctl disable wasabibackend
  sudo rm /etc/systemd/system/wasabibackend.service
fi
