#!/bin/bash
#
# zNcrypt interactive configuration script. This assumes zNcrypt is already installed.
#
# Author:: Ross McDonald (<ross.mcdonald@gazzang.com>)
# Copyright 2014, Gazzang, Inc.
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

password_file="/root/zncrypt-password"

function err {
    printf "\n\x1b[31mError:\x1b[0m $@\n"
    exit 1
}

function printBanner {
    color="\x1b[34m"
    company_color="\x1b[32m"
    echo -e "$color                          _                                             
 ____ _  __ _ _ _  _ _ __| |_                                           
|_ / ' \\/ _| '_| || | '_ \\  _|      __ _                    _           
/__|_||_\\__|_|  \\\\_, | .__/\\__|_ _  / _(_)__ _ _  _ _ _ __ _| |_ ___ _ _ 
                |__/|_/ _/ _ \\ ' \\|  _| / _\` | || | '_/ _\` |  _/ _ \\ '_|
                      \\__\\___/_||_|_| |_\\__, |\\_,_|_| \\__,_|\\__\\___/_|  
                                        |___/\x1b[0m Powered by$company_color Gazzang, Inc.\x1b[0m"
}

function createRandomPassword {
    test -f $password_file && return
    printf "Creating a password file at '$password_file'. You'll want to change this once configuration is completed.\n"
    tr -dc A-Za-z0-9_ < /dev/urandom | head -c 30 | tee $password_file &>/dev/null
    chown root:root $password_file
    chmod 400 $password_file
    if [[ ! -f $password_file ]]; then
        err "Password file ($password_file) could not be created. Please make sure that directory exists."
    fi
}

function verifyConnectivity {
    printf "Checking connectivity to the '$@' keystore.\n"
    curl https://$@/?a=fingerprint || err "Couldn't connect to keyserver. Check connectivity to '$@'."
}

function displayzNcryptPartitions {
    printf "\n__________________________________________________"
    printf "\nYou currently have the following mount points available:\n\n"
    cat /etc/zncrypt/ztab | awk '/^\// { print $1 }'
    printf "__________________________________________________\n"
}

function registerClient {
    test -f /etc/zncrypt/ztrustee/clientname && printf "\nzNcrypt is already registered. Skipping.\n" && return
    printf "\nzNcrypt is installed, but not registered."
    printf "\nWhat zTrustee Server would you like to register against? [ztdemo.gazzang.net]\n"
    read keyserver < /dev/tty
    test -z $keyserver && keyserver="ztdemo.gazzang.net"
    verifyConnectivity $keyserver

    printf "\n\nWhat organization would you like to register against? []\n"
    read org < /dev/tty
    printf "\nWhat is the authorization code for '$org' organization? []\n"
    read auth < /dev/tty

    register_command="zncrypt register -s $keyserver -t single-passphrase"
    # Test for 0 length strings to maintain compatibility with classic reg mode
    test -z $org || register_command="$register_command -o $org"
    test -z $auth || register_command="$register_command --auth=$auth"
    
    printf "__________________________________________________\n"
    printf "\nNote! This is the command we will be using to register:\n"
    printf "\n\$ $register_command\n"
    printf "\nPlease feel free to save this for future use."
    printf "__________________________________________________\n"
    
    printf "$(cat $password_file)\n$(cat $password_file)" | $register_command
    if [[ $? -ne 0 ]]; then
        err "Could not register with keyserver. Please check command output for more information."
    fi
}

function prepareClient {
    printf "Do you need to prepare any drives/directories for encryption? [no]\n"
    read response < /dev/tty
    test "${response:0:1}" = "y" || test "${response:0:1}" = "Y" || return
    unset response
    
    printf "\nWhere would you like to store the encrypted data? [/var/lib/zncrypt/.private]\n"
    read storage < /dev/tty
    test -z $storage && storage="/var/lib/zncrypt/.private"
    grep "$storage" /etc/zncrypt/ztab &>/dev/null && err "The location '$storage' is already marked as an encrypted partition."
    test -L $storage && storage="$(ls $storage | xargs readlink -f)" && printf "*You specified a symbolic link. Setting new encryption target to '$storage'.\n"
    test -b $storage && err "Sorry, block-level encryption is not support by this script (yet)."
    test -d $storage || mkdir -p $storage
    
    printf "\nAnd where would you like to mount the encrypted data? [/var/lib/zncrypt/encrypted]\n"
    read mount < /dev/tty
    test -z $mount && mount="/var/lib/zncrypt/encrypted"
    grep "$mount" /etc/zncrypt/ztab &>/dev/null && err "The location '$mount' is already marked as an encrypted partition."
    test -d $mount || mkdir -p $mount
    
    prepare_command="zncrypt-prepare $storage $mount"
    printf "\n__________________________________________________"
    printf "\nNote! This is the command we will be using to prepare the partition:\n"
    printf "\n\$ $prepare_command\n"
    printf "__________________________________________________\n"
    
    cat $password_file | eval "$prepare_command"
    if [[ $? -ne 0 ]]; then
        err "Could not prepare directory. Please check command output for more information."
    fi
}

function encryptData {
    printf "Do you want to encrypt any data? [no]\n"
    read response < /dev/tty
    test "${response:0:1}" = "y" || test "${response:0:1}" = "Y" || return
    unset response
    
    printf "\nWhat data would you like to encrypt? This can be either a directory or just a file.\n"
    read to_encrypt < /dev/tty
    test -z $to_encrypt && err "A valid directory or file location must be specified."
    test -L $to_encrypt && to_encrypt="$(ls $to_encrypt | xargs readlink -f)" && printf "*You specified a symbolic link. Setting new encryption target to '$to_encrypt'.\n"
    test -d $to_encrypt || test -f $to_encrypt || err "A valid directory or file location must be specified."
    
    if [[ -z $mount ]]; then
        displayzNcryptPartitions
        printf "\nWhat mount location would you like to use? []\n"
        read mount < /dev/tty
        test -z $mount && err "A valid encrypted partition must be specified."
    else
        printf "\nYou specified the mount location '$mount' from before. Would you like to use that location to store this encrypted data? [yes]\n"
        read response < /dev/tty
        test -z $response && response="yes"
        if [["${response:0:1}" = "n"] -o ["${response:0:1}" = "N"]]; then
            displayzNcryptPartitions
            printf "\nWhat mount location would you like to use? []\n"
            read mount < /dev/tty
            grep "$mount" /etc/zncrypt/ztab &>/dev/null || err "Need to specify a valid encrypted mount-point."
        fi
        unset response
    fi
    test -z $mount && err "You need to specify a valid mount location."
    
    printf "\nWhat category name would you like to encrypt this data with? [encrypted]\n"
    read category < /dev/tty
    test -z $category && category="encrypted"
    
    encrypt_command="zncrypt-move encrypt @$category $to_encrypt $mount"
    printf "\n__________________________________________________"
    printf "\nNote! This is the command we will be using to encrypt:\n"
    printf "\n\$ $encrypt_command\n"
    printf "__________________________________________________\n"
    
    cat $password_file | eval "$encrypt_command"
    if [[ $? -ne 0 ]]; then
        err "Could not encrypt object '$to_encrypt'. Please check command output for more information."
    fi
}

function addRules {
    printf "Do you want to set any ACL rules? [no]\n"
    read response < /dev/tty
    test "${response:0:1}" = "y" || test "${response:0:1}" = "Y" || return
    unset response
    
    printf "\nWhat binary would you like to allow access to the encrypted data?\n"
    read binary < /dev/tty
    test -z $binary && err "Please specify a valid binary."

    test -L $binary && binary="$(ls $binary | xargs readlink -f)" && printf "*You specified a symbolic link. Setting new binary target to '$binary'.\n"
    test -x $binary || err "A valid executable must be specified."
    
    if [[ -z $category ]]; then
        printf "\nWhat category name would you like to set for this rule? [encrypted]\n"
        read category < /dev/tty
        test -z $category && category="encrypted"
    else
        printf "\nYou used the category name '$category' before. Would you like to use the same name? [yes]\n"
        read response < /dev/tty
        test -z $response && response="yes"
        if [["${response:0:1}" = "n"] -o ["${response:0:1}" = "N"]]; then
            printf "\nWhat category name would you like to set for this rule? [encrypted]\n"
            read category < /dev/tty
            test -z $category && category="encrypted"
        fi
    fi
    test -z $category && err "A valid category name needs to be specified."
    
    acl_command="zncrypt acl --add -r \"ALLOW @$category * $binary\""
    printf "__________________________________________________\n"
    printf "\nNote! This is the command we will be using to add the ACL:\n"
    printf "\n\$ $encrypt_command\n"
    printf "__________________________________________________\n"
    
    cat $password_file | eval "$acl_command"
    if [[ $? -ne 0 ]]; then
        err "Could not add ACL for binary '$binary'. Please check command output for more information."
    fi
}

function printConclusion {
    printf "\nCompleted!\n"
    printf "We have randomly generated a password for you at '$password_file'. \nThis can (and should) be changed by running the following command:\n"
    printf "\n\t\$ cat $password_file | zncrypt key --change\n"
    printf "\nWhich will prompt you for your own master password.\n"
}

function main {
    printBanner
    test $UID -eq 0 || err "Please run with administrative privileges."
    which zncrypt &>/dev/null || err "Please install zNcrypt before continuing."
    createRandomPassword
    registerClient
    prepareClient
    encryptData
    addRules
    printConclusion
}

main

exit 0