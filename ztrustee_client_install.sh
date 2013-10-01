#!/bin/bash

# Author:: Ross McDonald (<ross.mcdonald@gazzang.com>)
# Copyright 2013, Gazzang, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#################################################
# GLOBAL VARIABLES
#################################################

ROOT_UID=0

INSTALL_LOG=install.log

#################################################
# FUNCTIONS
#################################################

# func exception
# Outputs a simple error message then exits with return code of 1
function exception {
    cat install.log
    echo ""
    echo "!! EXCEPTION - $*"
    echo "!! Please check $(pwd)/$INSTALL_LOG for more details."
    echo ""
    exit 1
}

# func notice
# Outputs a notice status to stdout
function notice {
    echo "NOTICE - $*"
}

# func check_sys_compatibilty
# Checks to make sure system is compatible based on a few outstanding issues with distros, VM's, etc.
function check_sys_compatibilty {
    notice "Checking system compatibility..."
    # Check for linux
    if [ "$OSTYPE" != "linux-gnu" ]; then 
        exception "Sorry, zTrustee Client is only compatible with Linux-based operating systems."
    fi
    
    return 0
}

# func get_sys_information
# Collects system information required for system information
function get_sys_information {
    notice "Collecting system information..."
    # Determine distribution and version
    if [ -f /etc/redhat-release ]; then # RedHat/CentOS/Oracle
        OS="RedHat"
        cat /etc/issue | grep 5\.. &>$INSTALL_LOG
        if [ $? -eq 0 ]; then 
            notice "Red Hat 5 variant detected..."
            VER=5
        fi
        cat /etc/issue | grep 6\.. &>$INSTALL_LOG
        if [ $? -eq 0 ]; then
            notice "Red Hat 6 variant detected..."
            VER=6
        fi
    elif [ -f /etc/lsb-release ]; then # Ubuntu and Debian
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
        CODENAME=$DISTRIB_CODENAME
    elif [ -f /etc/system-release ]; then
        exception "Sorry, Amazon Linux is not supported."
    else
        OS=$(uname -s)
        VER=$(uname -r)
        exception "Sorry, this version of Linux is not yet supported."
    fi
    
    return 0
}

# func ubuntu_setup
# Configures repositories and installs zNcrypt dependencies on Ubuntu
function ubuntu_setup {
    notice "Switching to Ubuntu configuration..."
    
    # configure repository
    cat /etc/apt/sources.list | grep http://archive.gazzang.com &>$INSTALL_LOG
    if [ $? -ne 0 ]; then
        notice "Adding Gazzang repository..."
        echo "deb http://archive.gazzang.com/$(echo $OS | tr '[A-Z]' '[a-z]')/stable $CODENAME main" >> /etc/apt/sources.list
        wget http://archive.gazzang.com/gpg_gazzang.asc &>$INSTALL_LOG
        sudo apt-key add gpg_gazzang.asc &>$INSTALL_LOG
        rm -f gpg_gazzang.asc &>$INSTALL_LOG
    fi

    notice "Updating package lists..."
    apt-get update &>$INSTALL_LOG
    
    notice "Installing zTrustee Client..."
    apt-get install ztrustee-client -y &>$INSTALL_LOG
    if [ $? -ne 0 ]; then
        exception "Could not install zTrustee Client. Exiting."
    fi

    return 0
}

# func rhel_setup
# Configures repositories and installs zNcrypt dependencies on RHEL 
function rhel_setup {
    notice "Switching to RHEL/CentOS configuration..."

    # configure repository
    if [ ! -f /etc/yum.repos.d/gazzang.repo ]; then 
        echo "[gazzang]" >> /etc/yum.repos.d/gazzang.repo
        echo "name=RHEL $VER - gazzang.com - base" >> /etc/yum.repos.d/gazzang.repo
        echo "baseurl=http://archive.gazzang.com/redhat/stable/$VER" >> /etc/yum.repos.d/gazzang.repo
        echo "enabled=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgcheck=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgkey=http://archive.gazzang.com/gpg_gazzang.asc" >> /etc/yum.repos.d/gazzang.repo
        
        # retrieve and add Gazzang gpg key
        notice "Adding Gazzang public key..."
        curl -o gpg_gazzang.asc http://archive.gazzang.com/gpg_gazzang.asc &>$INSTALL_LOG
        rpm --import gpg_gazzang.asc &>$INSTALL_LOG
        if [ $? -ne 0 ]; then
            exception "Could not import Gazzang Repository public key. Exiting."
        fi
        rm gpg_gazzang.asc
        
        notice "Installing haveged..."
        yum install haveged -y &>$INSTALL_LOG
        service haveged start &>$INSTALL_LOG
        if [ $? -ne 0 ]; then
            notice "WARNING! Haveged could not be started. Key generation might take a while..."
        fi
        
        notice "Installing zTrustee Client..."
        yum install ztrustee-client -y &>$INSTALL_LOG
        if [ $? -ne 0 ]; then
            exception "Could not install zTrustee client. Exiting."
        fi
    fi
    
    return 0
}

#################################################
# START OF SCRIPT
#################################################

echo ""
echo "     ____"                                
echo "    / ___| __ _ __________ _ _ __   __ _ "
echo "   | |  _ / _\` |_  /_  / _\` | \'_ \/ _\` | "
echo "   | |_| | (_| |/ / / / (_| | | | | (_| |    "
echo "    \____|\__,_/___/___\__,_|_| |_|\__, |    "
echo "                     Gazzang, Inc. |___/  " 
echo ""

# Check for root user
if [ "$UID" -ne "$ROOT_UID" ]; then
    exception "Please run as root."
fi

check_sys_compatibilty
get_sys_information

case "$OS" in
    "Ubuntu") 
    ubuntu_setup
    ;;
    "RedHat")
    rhel_setup
    ;;
    "")
    exception "Invalid operating system. Exiting."
    ;;
esac

notice "Done!"
exit 0
