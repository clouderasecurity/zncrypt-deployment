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

# This script will install zNcrypt and dependencies, create a randomized
# password (stored at $PASSWORD_FILE), register that password with the zTrustee
# server ($KEYSERVER), and mount an encrypted file system at $STORAGE_DIR and
# $MOUNT_DIR.

#################################################
# GLOBAL VARIABLES
#################################################

# zNcrypt Variables
PASSWORD_FILE=/root/zncryptpassword
STORAGE_DIR=/encrypted
MOUNT_DIR=/mnt/encrypted
KEYSERVER=ztdemo.gazzang.net
ACTIVATION_EMAIL=ross.mcdonald@gazzang.com

# Logging Variables
LOG_DIR=/var/log/zncrypt
LOG_FILE=install.log

# MySQL Server Variables
MYSQL_PASSWORD=mysqlpassword # valid for Ubuntu only, RHEL/CentOS must be set manually

# Directories to Encrypt
ENCRYPT_DIR=( /mnt/ephemeral/mysql /var/lib/mysqllogs/bin-log /var/lib/mysqllogs/slow-log )
ENCRYPT_CATEGORY=( @mysql @mysql @mysql )

# ACL Configuration Variables
ACL_BINARY=( /usr/libexec/mysqld /usr/bin/mysqld_safe )
ACL_CATEGORY=( @mysql @mysql )

#################################################
# FUNCTIONS
#################################################

# func setup_logging
# Enable logging to 
function enable_logging {
    #if [ ! -d $LOG_DIR ]; then
    #    mkdir -p $LOG_DIR
    #fi
    #exec > $LOG_DIR/$LOG_FILE 2>&1
}

# func exception
# Outputs a simple error message then exits with return code of 1
function exception {
    echo ""
    echo "EXCEPTION - $*"
    echo ""
    exit 1
}

# func notice
# Outputs a notice status to stdout (temporarily disabling logging)
function notice {
    echo ""
    echo "NOTICE - $*"
}

# func check_vars
# Checks to make sure global variables are set correctly.
function check_vars {
    notice "Checking global variable configuration..."
    if [ ${#ACL_BINARY[@]} -ne ${#ACL_CATEGORY[@]} ]; then
        exception "Size of ACL_BINARY and ACL_CATEGORY does not match. Please ensure number of specified categories is equal to the number of specified binaries."
    fi
    if [ ${#ENCRYPT_DIR[@]} -ne ${#ENCRYPT_CATEGORY[@]} ]; then
        exception "Size of ENCRYPT_DIR and ENCRYPT_CATEGORY does not match. Please ensure number of specified categories is equal to the number of specified directories to encrypt."
    fi
}

# func check_sys_compatibilty
# Checks to make sure system is compatible based on a few outstanding issues with distros, VM's, etc.
function check_sys_compatibilty {
    notice "Checking system compatibility..."
    # Check for linux
    if [ "$OSTYPE" != "linux-gnu" ]; then 
        exception "Sorry, zNcrypt is only compatible with Linux-based operating systems."
    fi

    # Check for OpenVZ, which is not currently supported by zNcrypt
    if [ -f /proc/user_beancounters ]; then
        exception "Sorry, you are using an incompatible virtualization software. Please contact support@gazzang.com for a list of supported platforms."
    fi
}

# func get_sys_information
# Collects system information required for system information
function get_sys_information {
    notice "Collecting system information..."
    # Determine distribution and version
    if [ -f /etc/redhat-release ]; then # RedHat and CentOS
        OS="RedHat"
    elif [ -f /etc/lsb-release ]; then # Ubuntu and Debian
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
        CODENAME=$DISTRIB_CODENAME
    elif [ -f /etc/system-release ]; then
        OS=Amazon
        VER=$(cat /etc/system-release)
    else
        OS=$(uname -s)
        VER=$(uname -r)
        exception "Sorry, this version of Linux is not yet supported."
    fi
}

# func create_password
# Creates a randomized password used for zNcrypt registration
function create_password {
    notice "Creating master password at $PASSWORD_FILE..."
    tr -dc A-Za-z0-9_ < /dev/urandom | head -c 30 | xargs >> $PASSWORD_FILE
}

# func ubuntu_setup
# Configures repositories and installs zNcrypt dependencies on Ubuntu
function ubuntu_setup {
    notice "Configuring Ubuntu..."
    
    # Install MySQL Server as demonstration
    if [ ! -f /etc/init.d/mysqld ]; then
        apt-get -qq update
        # Hardcoding password as an example
        debconf-set-selections <<< 'mysql-server mysql-server/root_password password $MYSQL_PASSWORD'
        debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD'
        apt-get install -y mysql-server
    fi
    
    # configure repository
    cat /etc/apt/sources.list | grep http://archive.gazzang.com &>/dev/null
    if [ $? -ne 0 ]; then
        echo "deb http://archive.gazzang.com/$(echo $OS | tr '[A-Z]' '[a-z]')/stable $CODENAME main" >> /etc/apt/sources.list
        wget -O - http://archive.gazzang.com/gpg_gazzang.asc | sudo apt-key add -
    fi
    
    apt-get -qq update
    apt-get -qq install linux-headers-$(uname -r)
    
    if [ ! -f $PASSWORD_FILE ]; then 
        create_password
    fi
}

# func rhel_setup
# Configures repositories and installs zNcrypt dependencies on RHEL 
function rhel_setup {
    notice "Configuring RHEL/CentOS..."

    # Install MySQL Server as a demonstration
    if [ ! -f /etc/init.d/mysqld ]; then
        notice "No MySQL server instance found, installing..."
        # To pull MySQL 5.5, need to add extra repos
        rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
        rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-6.rpm
        yum --enablerepo=remi,remi-test install mysql mysql-server -y
        service mysqld start
    fi

    # Ensure make is installed
    yum -y install make

    # Check for Azure version of OpenLogic CentOS 6.3 (which disables kernel updates by default)
    cat /etc/yum.conf -n | grep exclude=kernel &>/dev/null
    if [ $? -eq 0 ]; then
        notice "Kernel updates have been disabled. Enabling..."
        # Remove line disabling kernel updates
        sed -i".old" '/exclude=kernel*/d' /etc/yum.conf
        # NOTE - Backup of old yum.conf still kept at /etc/yum.conf.old
    fi

    # configure repository
    if [ ! -f /etc/yum.repos.d/gazzang.repo ]; then        
        notice "Adding Gazzang repository..."
        echo "[gazzang]" >> /etc/yum.repos.d/gazzang.repo
        echo "name=RHEL \$releasever - gazzang.com - base" >> /etc/yum.repos.d/gazzang.repo
        echo "baseurl=http://archive.gazzang.com/redhat/stable/\$releasever" >> /etc/yum.repos.d/gazzang.repo
        echo "enabled=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgcheck=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgkey=http://archive.gazzang.com/gpg_gazzang.asc" >> /etc/yum.repos.d/gazzang.repo
    fi

    # retrieve and add Gazzang gpg key
    notice "Adding Gazzang public key..."
    wget http://archive.gazzang.com/gpg_gazzang.asc
    if [ $? -ne 0 ]; then
        curl -o gpg_gazzang.asc http://archive.gazzang.com/gpg_gazzang.asc
    fi
    rpm --import gpg_gazzang.asc
    if [ $? -ne 0 ]; then
        exception "Could not import Gazzang Repository public key. Exiting."
    fi
    rm gpg_gazzang.asc

    # install kernel headers and devel
    notice "Installing kernel-devel..."
    yum -y install kernel-devel-$(uname -r)
    if [ $? -ne 0 ]; then
        yum -y install kernel-devel # sometimes doesnt work
        if [ $? -ne 0 ]; then
            exception "Could not install kernel-devel. Exiting."
        fi
    fi
    notice "Installing kernel headers..."
    yum -y install kernel-headers-$(uname -r)
    if [ $? -ne 0 ]; then
        yum -y install kernel-headers # sometimes doesnt work
        if [ $? -ne 0 ]; then
            exception "Could not install kernel-headers. Exiting."
        fi
    fi

    notice "Installing haveged..."
    yum -y install haveged
    /etc/init.d/haveged start
    if [ ! -f $PASSWORD_FILE ]; then 
        create_password
    fi

    # Disable SELinux, note this will only disable selinux until reboot. Need permanent solution.
    setenforce 0

    return 0
}


function amazon_setup {
    notice "Configuring Amazon Linux..."
    
    notice "Installing kernel-devel..."
    yum -y install kernel-devel-$(uname -r)
    if [ $? -ne 0 ]; then # if devel for current kernel version not available, install latest kernel
        yum -y install kernel
        yum -y install kernel-devel
        if [ $? -ne 0 ]; then
            exception "Could not install kernel-devel. Exiting."
        fi
    fi
    notice "Installing kernel headers..."
    yum -y install kernel-headers-$(uname -r)
    if [ $? -ne 0 ]; then
        yum -y install kernel-headers
        if [ $? -ne 0 ]; then
            exception "Could not install kernel-headers. Exiting."
        fi
    fi

    notice "Installing zNcrypt dependencies..."
    yum install -y dkms gcc keyutils
    if [ $? -ne 0 ]; then
        exception "Could not install zNcrypt dependencies."
    fi

    # configure repository
    if [ ! -f /etc/yum.repos.d/gazzang.repo ]; then        
        notice "Adding Gazzang repository..."
        echo "[gazzang]" >> /etc/yum.repos.d/gazzang.repo
        echo "name=RHEL 6 - gazzang.com - base" >> /etc/yum.repos.d/gazzang.repo
        echo "baseurl=http://archive.gazzang.com/redhat/stable/6" >> /etc/yum.repos.d/gazzang.repo
        echo "enabled=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgcheck=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgkey=http://archive.gazzang.com/gpg_gazzang.asc" >> /etc/yum.repos.d/gazzang.repo
    fi
    
    notice "Adding Gazzang public key..."
    wget http://archive.gazzang.com/gpg_gazzang.asc
    sudo rpm --import gpg_gazzang.asc
    rm gpg_gazzang.asc
    
    notice "Installing haveged..."
    rpm -Uvh https://archive.gazzang.com/redhat/stable/6/Packages/haveged-1.3-2.el6.x86_64.rpm
    #if [ $? -ne 0 ]; then
    #    exception "Could not install haveged."
    #fi
    /etc/init.d/haveged start
    
    notice "Installing zNcrypt dependencies..."
    yum install -y ecryptfs-utils
    #if [ $? -ne 0 ]; then
    #    exception "Could not install zNcrypt ecryptfs-utils."
    #fi
    
    notice "Installing libcryptsetup..."
    yum remove -y cryptsetup-luks-libs-1.2.0-7.11.amzn1.x86_64
    rpm -Uvh http://mirror.centos.org/centos/6/os/x86_64/Packages/cryptsetup-luks-libs-1.2.0-7.el6.x86_64.rpm
    #if [ $? -ne 0 ]; then
    #    exception "Could not install libcryptsetup."
    #fi
    
    notice "Installing libztrustee..."
    rpm -Uvh https://archive.gazzang.com/redhat/stable/6/Packages/libztrustee-3.4.0.666_rhel6-1.x86_64.rpm
    #if [ $? -ne 0 ]; then
    #    exception "Could not install libztrustee."
    #fi
    
    notice "Installing zNcrypt Kernel Module..."
    rpm -Uvh https://archive.gazzang.com/redhat/stable/6/Packages/zncrypt-kernel-module-3.2.2_rhel6-528.x86_64.rpm
    #if [ $? -ne 0 ]; then
    #    exception "Could not install zNcrypt Kernel Module."
    #fi
    
    notice "Installing zNcrypt..."
    rpm -Uvh https://archive.gazzang.com/redhat/stable/6/Packages/zncrypt-3.2.2_rhel6-526.x86_64.rpm
    #if [ $? -ne 0 ]; then
    #    exception "Could not install zNcrypt."
    #fi

    if [ ! -f $PASSWORD_FILE ]; then 
        create_password
    fi

    notice "zNcrypt installed. Testing kernel setup..."
    zncrypt-module-setup
    if [ $? -ne 0 ]; then
        notice "Module build unsuccesful, restarting the system..."
        shutdown -r now
    fi

    return 0
}

# func register_zncrypt
# Registers the zNcrypt client with the zTrustee server. Retries if it fails. 
function register_zncrypt {
    notice "Registering zNcrypt with $KEYSERVER..."
    # set flag for exiting
    RETVAL=1
    # set a counter to make sure we don't continue registering forever
    local COUNT=0
    while [ $RETVAL -ne 0 ]; do
        # register zNcrypt client and collect return code
        printf "$(cat $PASSWORD_FILE)\n$(cat $PASSWORD_FILE)" | zncrypt register --key-type=single-passphrase --server=$KEYSERVER
        RETVAL=$?
        
        # stop the 'already registered' feedback loop
        if [ $RETVAL -ne 0 ]; then
            rm -rf /etc/zncrypt/ztrustee
        fi
        
        if [ $COUNT -gt 5 ]; then
            # we gave it a shot
            exception "Could not register zNcrypt client. Exiting."
        fi
        let COUNT=COUNT+1
    done
    
    # request activation for zNcrypt client
    notice "Activating zNcrypt client with contact $ACTIVATION_EMAIL..."
    zncrypt request-activation -c $ACTIVATION_EMAIL
    
    return 0
}

# func prepare_zncrypt
# Prepares the system for encryption by executing the zncrypt-prepare scipts.
function prepare_zncrypt {
    notice "Preparing file system for encryption..."
    mkdir -p $STORAGE_DIR
    mkdir -p $MOUNT_DIR
    cat /etc/zncrypt/ztab | grep $STORAGE_DIR
    if [ $? -ne 0 ]; then
        notice "No existing encrypted file system detected, mounting $STORAGE_DIR at $MOUNT_DIR..."
        cat $PASSWORD_FILE | zncrypt-prepare $STORAGE_DIR $MOUNT_DIR
        if [ $? -ne 0 ]; then
            exception "zNcrypt prepare failed. Exiting."
        fi
    fi
    return 0
}

# func configure_mysql
# Encrypt and configure ACL rules for MySQL Server
function configure_mysql {
    case "$OS" in
        "Ubuntu")
        notice "Checking for MySQL server..."
        if [ -f /etc/init.d/mysql ]; then
            notice "Found, stopping service..."
            service mysql stop
            notice "Encrypting data..."
            NUM_RULES=${#ENCRYPT_DIR[@]}
            for (( COUNT=0; COUNT<${NUM_RULES}; i++)); do
                cat $PASSWORD_FILE | zncrypt-move encrypt ${ENCRYPT_CATEGORY[$COUNT]} ${ENCRYPT_DIR[$COUNT]} $MOUNT_DIR
            done
            notice "Adding ACL rules..."
            NUM_RULES=${#ACL_BINARY[@]}
            for (( COUNT=0; COUNT<${NUM_RULES}; i++)); do
                cat $PASSWORD_FILE | zncrypt acl --add --rule=\"ALLOW ${ACL_CATEGORY[$COUNT]} * ${ACL_BINARY[$COUNT]}\"
            done
            notice "Restarting MySQL service..."
            service mysql start
        fi
        ;;
        "RedHat")
        notice "Checking for MySQL server..."
        if [ -f /etc/init.d/mysqld ]; then
            notice "Found, stopping service..."
            service mysqld stop
            notice "Encrypting data..."
            NUM_RULES=${#ENCRYPT_DIR[@]}
            for (( COUNT=0; COUNT<${NUM_RULES}; i++)); do
                cat $PASSWORD_FILE | zncrypt-move encrypt ${ENCRYPT_CATEGORY[$COUNT]} ${ENCRYPT_DIR[$COUNT]} $MOUNT_DIR
            done
            notice "Adding ACL rules..."
            NUM_RULES=${#ACL_BINARY[@]}
            for (( COUNT=0; COUNT<${NUM_RULES}; i++)); do
                cat $PASSWORD_FILE | zncrypt acl --add --rule=\"ALLOW ${ACL_CATEGORY[$COUNT]} * ${ACL_BINARY[$COUNT]}\"
            done
            notice "Restarting MySQL service..."
            service mysqld start
        fi
        ;;
    esac
    return 0
}

#################################################
# START OF SCRIPT
#################################################

echo ""
echo "     ____"                                
echo "    / ___| __ _ __________ _ _ __   __ _ "
echo "   | |  _ / _\` |_  /_  / _\` | \'_ \ / _\`| "
echo "   | |_| | (_| |/ / / / (_| | | | | (_| |    "
echo "    \____|\__,_/___/___\__,_|_| |_|\__, |    "
echo "                                   |___/  " 
echo ""
echo ""
echo "Gazzang zNcrypt Installation/Configuration Script"
echo "---> Author: Ross McDonald, ross.mcdonald@gazzang.com"
echo ""
echo "For logs, please check $LOG_DIR"
echo ""

enable_logging

# Check for root user
if [ "$UID" -ne "0" ]; then
    exception "Please run as root."
fi

check_vars
check_sys_compatibilty
get_sys_information

case "$OS" in
    "Ubuntu")
    notice "Ubuntu system detected..."
    ubuntu_setup
    apt-get install -y zncrypt
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        exception "Installation of zNcrypt failed. Exiting."
    fi
    ;;
    "RedHat")
    notice "RHEL system detected..."
    rhel_setup
    yum install -y zncrypt
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        exception "Installation of zNcrypt failed. Exiting."
    fi
    ldconfig # change in next iteration
    ;;
    "Amazon")
    notice "Amazon system detected..."
    amazon_setup
    ;;
    "")
    exception "Invalid operating system. Exiting."
    ;;
esac

# Register the zNcrypt client
register_zncrypt

# Prepare the system for encryption by creating the encrypted file system
#prepare_zncrypt

# Encrypt and configure ACL rules for MySQL Server
#configure_mysql

exit 0
