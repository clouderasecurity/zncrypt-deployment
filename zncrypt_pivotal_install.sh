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

# Gazzang-Pivotal Deployment Scripts for zNcrypt on Pivotal HD

#################################################
# GLOBAL VARIABLES
#################################################

ROOT_UID=0

# zTrustee registration/activation email
KEYSERVER=ztdemo.gazzang.net
ACTIVATION_EMAIL=

# Category to encrypt data.
# Current script functionality only supports one category
CATEGORY=hdfs

# ACL rules to add to encrypted data
ACL_RULES=( /usr/java/jdk1.6.0_43/bin/java \
            /usr/bin/du \
            /usr/libexec/bigtop-utils/jsvc )

# Mount directories to store encrypted data (mount dir and 
# storage dir will be the same)
STORAGE_DIRS=( )

# Directories/files that we want to encrypt
DIRS_TO_ENCRYPT=( )

#################################################
# FUNCTIONS
#################################################

# func exception
# Outputs a simple error message then exits with return code of 1
function exception {
    echo ""
    echo "!! EXCEPTION - $*"
    echo ""
    exit 1
}

# func notice
# Outputs a notice status to stdout (temporarily disabling logging)
function notice {
    echo "NOTICE - $*"
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
    
    return 0
}

# func get_sys_information
# Collects system information required for system information
function get_sys_information {
    notice "Collecting system information..."
    # Determine distribution and version
    if [ -f /etc/redhat-release ]; then # RedHat and CentOS
        OS="RedHat"
    elif [ -f /etc/lsb-release ]; then # Ubuntu and Debian
        exception "Sorry, Pivotal HD is not supported on Debian-based variants."
    elif [ -f /etc/system-release ]; then
        exception "Sorry, Amazon Linux is not supported."
    else
        OS=$(uname -s)
        VER=$(uname -r)
        exception "Sorry, this version of Linux is not yet supported."
    fi
    
    return 0
}

# func collect_password
# Collects a password from stdin used for zNcrypt registration
function collect_password {
    stty -echo
    read -p "zNcrypt password (16-32 characters): " PASSWORD1; echo
    stty echo
    stty -echo
    read -p "Confirm password: " PASSWORD2; echo
    stty echo
    
    HASH1=$(printf "%s" $PASSWORD1 | /usr/bin/md5sum | /bin/cut -f1 -d" ")
    HASH2=$(printf "%s" $PASSWORD2 | /usr/bin/md5sum | /bin/cut -f1 -d" ")
    if [ '$HASH1' = '$HASH2' ]; then
        exception "Passwords do not match."
    fi

    PASSWORD=$PASSWORD1
    unset -v PASSWORD1 PASSWORD2 HASH1 HASH2
    return 0
}

# func ubuntu_setup
# Configures repositories and installs zNcrypt dependencies on Ubuntu
function ubuntu_setup {
    notice "Configuring Ubuntu..."
    
    # configure repository
    cat /etc/apt/sources.list | grep http://archive.gazzang.com &>/dev/null
    if [ $? -ne 0 ]; then
        echo "deb http://archive.gazzang.com/$(echo $OS | tr '[A-Z]' '[a-z]')/stable $CODENAME main" >> /etc/apt/sources.list
        wget -O - http://archive.gazzang.com/gpg_gazzang.asc | sudo apt-key add -
    fi

    apt-get -qq update
    apt-get -qq install linux-headers-$(uname -r)

    return 0
}

# func rhel_setup
# Configures repositories and installs zNcrypt dependencies on RHEL 
function rhel_setup {
    notice "Configure RHEL/CentOS..."
    
    # Ensure make and perl are installed
    yum -y install make perl
    
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
        echo "[gazzang]" >> /etc/yum.repos.d/gazzang.repo
        echo "name=RHEL \$releasever - gazzang.com - base" >> /etc/yum.repos.d/gazzang.repo
        echo "baseurl=http://archive.gazzang.com/redhat/stable/\$releasever" >> /etc/yum.repos.d/gazzang.repo
        echo "enabled=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgcheck=1" >> /etc/yum.repos.d/gazzang.repo
        echo "gpgkey=http://archive.gazzang.com/gpg_gazzang.asc" >> /etc/yum.repos.d/gazzang.repo
        
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
        service haveged start

        notice "Disabling selinux."
        setenforce 0
    fi
    
    return 0
}

# func register_zncrypt
# Registers the zNcrypt client with the zTrustee server. Retries if it fails. 
function register_zncrypt {
    notice "Registering zNcrypt with $KEYSERVER..."
    
    if [ -f /etc/zncrypt/ztrustee/clientname ]; then
        notice "zNcrypt already registered."
        return 0
    fi
    
    collect_password
    
    # set flag for exiting
    local RETVAL=1
    # set a counter to make sure we don't continue registering forever
    local COUNT=0
    while [ $RETVAL -ne 0 ]; do
        # register zNcrypt client and collect return code
        printf "%s\n%s" $PASSWORD $PASSWORD | zncrypt register \
                                            --key-type=single-passphrase \
                                            --server=$KEYSERVER \
                                            --skip-ssl-check
        RETVAL=$?
        if [ $RETVAL -ne 0 ]; then
            # stop the 'already registered' feedback loop
            rm -rf /etc/zncrypt/ztrustee
        fi
        
        if [ $COUNT -gt 5 ]; then
            # well, we gave it a shot
            exception "Could not register zNcrypt client. Exiting."
        fi
        let COUNT=COUNT+1
    done
    
    return 0
}

# func activate_zncrypt
# Sends an activation request for the zNcrypt client
function activate_zncrypt {
    notice "Activating zNcrypt client with contact $ACTIVATION_EMAIL..."
    zncrypt request-activation -c $ACTIVATION_EMAIL
    return 0
}

# func prepare_zncrypt
# Prepares the system for encryption by executing zncrypt-prepare.
function prepare_zncrypt {
    notice "Preparing file system for encryption..."

    for DIR in ${STORAGE_DIRS[@]} ; do
        cat /etc/zncrypt/ztab | grep $DIR
        if [ $? -ne 0 ]; then
            notice "Mounting encrypted directory $DIR ..."
            if [ ! -d $DIR ]; then
                mkdir -p $DIR
            fi
            printf "%s" $PASSWORD | zncrypt-prepare $DIR $DIR
            if [ $? -ne 0 ]; then
                exception "zNcrypt prepare failed. Exiting."
            fi
        fi
    done
    
    return 0
}

# func encrypt_directories
# Encrypts target directories one at a time.
function encrypt_directories {
    notice "Encrypting target directories..."

    local COUNT=0
    while [ $COUNT -lt ${#DIRS_TO_ENCRYPT[@]} ]; do
        test -h $DIR
        if [ $? -ne 0 ]; then
            notice "Encrypting directory ${DIRS_TO_ENCRYPT[$COUNT]}..."
            printf "%s" $PASSWORD | zncrypt-move encrypt @$CATEGORY \
                                    ${DIRS_TO_ENCRYPT[$COUNT]} \
                                    ${STORAGE_DIRS[$COUNT]}
            if [ $? -ne 0 ]; then
                exception "zncrypt-move failed. Exiting."
            fi
        fi
        let COUNT=COUNT+1
    done
    
    return 0
}

# func add
# Add appropriate ACL rules.
function add_acls {
    notice "Adding ACL rules..."

    for RULE in ${ACL_RULES[@]} ; do
        notice "Adding ACL rule:\"ALLOW @$CATEGORY * $RULE\""
        printf "%s" $PASSWORD | zncrypt acl --add --rule="ALLOW @$CATEGORY * $RULE"
        if [ $? -ne 0 ]; then
            exception "Adding of ACL rule failed. Exiting."
        fi
    done
    
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
echo "                          Gazzang, Inc.   "
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
    apt-get install zncrypt -y
    if [ $? -ne 0 ]; then
        exception "Installation of zNcrypt failed. Exiting."
    fi
    ;;
    "RedHat")
    rhel_setup
    yum install zncrypt -y 
    if [ $? -ne 0 ]; then
        exception "Installation of zNcrypt failed. Exiting."
    fi
    ;;
    "")
    exception "Invalid operating system. Exiting."
    ;;
esac

register_zncrypt
activate_zncrypt
echo "[PRESS ENTER TO CONTINUE]"
read
prepare_zncrypt
encrypt_directories
add_acls

unset -v PASSWORD

exit 0
