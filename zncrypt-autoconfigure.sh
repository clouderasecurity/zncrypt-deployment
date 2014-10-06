#!/bin/bash
#
# zNcrypt automated-configuration script. This assumes zNcrypt is already installed.
#
# Author:: Ross McDonald (ross.mcdonald@cloudera.com)
# Copyright 2014, Cloudera
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

printf "Starting...\n"

######################################
# global configuration variables (change these to fit your environment)
######################################

# zTrustee Server to register against. This will default to [ztdemo.gazzang.net] if not set.
keyserver=""

# Registration credentials for authenticating with the keyserver
org=""
auth=""

# Storage and mount locations (can be either an array or string)
storage=( "/encrypted/.private" )
mount=( "/encrypted/mnt" )

# Data to encrypt/protect
to_encrypt=( "/etc/issue" )

# ACL categories to set
category=( "demo" )
acl_binary=( "/bin/cat" )

# Please note, the last 5 variables listed above correspond 1:1 with eachother.
# Every array must be of equal length. For example, if you would like to encrypt
# more than one target against the same mount, you must list the mount/storage
# location twice to match both targets.

######################################
# cosmetic, meta variables/functions
######################################

# This variable controls whether or not zNcrypt performs SSL hostname verification
# Setting to 'true' will make you more vulnerable to MITM attacks
insecure="false"

# Location to store randomly-generated master password
password_file="/root/zncrypt-password"

function err {
    printf "\n\x1b[31mError:\x1b[0m $@\n"
    exit 1
}

function printBanner {
    color="\x1b[32m"
    company_color="\x1b[34m"
    echo -e "$color                          _
 ____ _  __ _ _ _  _ _ __| |_
|_ / ' \\/ _| '_| || | '_ \\  _|      __ _                    _
/__|_||_\\__|_|  \\\\_, | .__/\\__|_ _  / _(_)__ _ _  _ _ _ __ _| |_ ___ _ _
                |__/|_/ _/ _ \\ ' \\|  _| / _\` | || | '_/ _\` |  _/ _ \\ '_|
                      \\__\\___/_||_|_| |_\\__, |\\_,_|_| \\__,_|\\__\\___/_|
                                        |___/\x1b[0m Now powered by$company_color Cloudera\x1b[0m"
}

function createRandomPassword {
    test -f $password_file && return
    printf "Creating a password file at '$password_file'\n"
    tr -dc A-Za-z0-9_ < /dev/urandom | head -c 30 | tee $password_file &>/dev/null
    chown root:root $password_file
    chmod 400 $password_file
    if [[ ! -f $password_file ]]; then
        err "Password file ($password_file) could not be created. Please make sure that directory exists."
    fi
}

function verifyConnectivity {
    which curl &>/dev/null || err "curl needs to be installed in order to determine connectivity."
    printf "Checking connectivity to the '$@' keystore..."
    curl http://$@ &>/dev/null || err "Couldn't connect to keyserver over port 80. Check connectivity to '$@'."
    curl -k https://$@/?a=fingerprint &>/dev/null || err "Couldn't connect to keyserver over port 443. Check connectivity to '$@'."
    printf " connection verified.\n"
}

function registerClient {
    test -f /etc/zncrypt/ztrustee/clientname && printf "Client is already registered. Skipping registration.\n" && return
    test -z $keyserver && err "No key server specified for registration."
    test -z $org && err "No organization specified for registration with [$keyserver] server."
    test -z $auth && err "No authorization code specified for registration against the [$org] organization."
    verifyConnectivity $keyserver

    register_command="zncrypt register -s $keyserver -t single-passphrase"
    test -z $org || register_command="$register_command -o $org"
    test -z $auth || register_command="$register_command --auth=$auth"
    test $insecure = "true" && register_command="$register_command --skip-ssl-check"

    printf "Registering client with keyserver [$keyserver]...\n"
    printf "$(cat $password_file)\n$(cat $password_file)" | $register_command | tail -n+3
    if [[ $? -ne 0 ]]; then
        err "Could not register with keyserver [$keyserver]. Please check command output for more information."
    fi
}

function prepareClient {
    test ${#storage[@]} -eq ${#mount[@]} || err "Unequal number of storage/mount locations."
    test ${#storage[@]} -eq 0 && printf "No mount/storage locations specified. Skipping prepare step.\n" && return

    local count=0
    while [[ $count -lt ${#storage[@]} ]]; do
        grep "${storage[$count]}\\s" /etc/zncrypt/ztab &>/dev/null || grep "${mount[$count]}\\s" /etc/zncrypt/ztab &>/dev/null
        if [[ $? -ne 0 ]]; then
            printf "Mounting encrypted partition at [${storage[$count]}], storage at [${mount[$count]}]\n"
            test -L ${storage[$count]} && storage="$(ls ${storage[$count]} | xargs readlink -f)" && printf "\t- You specified a symbolic link. Setting new storage target to [${storage[$count]}].\n"

            if [[ -b ${storage[$count]} ]]; then
                printf "\t- Block device specified. Cleaning device.\n"
                dd if=/dev/zero of=${storage[$count]} bs=1M count=1 &>/dev/null
            else
                test -d ${storage[$count]} || mkdir -p ${storage[$count]} && printf "\t- Storage directory [${storage[$count]}] created.\n"
            fi
            test -d ${mount[$count]} || mkdir -p ${mount[$count]} && printf "\t- Directory [${mount[$count]}] created.\n"

            prepare_command="zncrypt-prepare ${storage[$count]} ${mount[$count]}"
            cat $password_file | eval "$prepare_command"
            if [[ $? -ne 0 ]]; then
                err "Could not prepare directory. Please check command output for more information."
            fi
            printf "\n"
        fi
        let count=count+1
    done
}

function encryptData {
    test ${#to_encrypt[@]} -eq 0 && printf "No targets specified for encryption. Skipping encryption step.\n" && return
    test ${#to_encrypt[@]} -eq ${#mount[@]} || err "Unequal number of mount locations and encryption targets. These values need to correspond 1:1."
    test ${#to_encrypt[@]} -eq ${#category[@]} || err "Unequal number of encryption targets and ACL categories. These values need to correspond 1:1."

    local count=0
    while [[ $count -lt ${#to_encrypt[@]} ]]; do
        if [[ -L ${to_encrypt[$count]} ]]; then
            printf "Skipping encryption of [${to_encrypt[$count]}], as it's already a symbolic link.\n"
        else
            test -d ${to_encrypt[$count]} || mkdir -p ${to_encrypt[$count]} && printf "Target [${to_encrypt[$count]}] does not exist, creating directory."
            printf "Encrypting target [${to_encrypt[$count]}]\n"
            encrypt_command="zncrypt-move encrypt @${category[$count]} ${to_encrypt[$count]} ${mount[$count]}"
            cat $password_file | eval "$encrypt_command"
            if [[ $? -ne 0 ]]; then
                err "Could not encrypt object '${to_encrypt[$count]}'. Please check command output for more information."
            fi
        fi
        let count=$count+1
    done
}

function addRules {
    test ${#acl_binary[@]} -eq ${#category[@]} || err "Unequal number of ACL processes and ACL categories. These values need to correspond 1:1."

    local count=0
    while [[ $count -lt ${#acl_binary[@]} ]]; do
        cat $password_file | zncrypt acl --list | grep -r "${category[$count]}.*${acl_binary[$count]}" &>/dev/null
        if [[ $? -ne 0 ]]; then
            printf "Creating ACL rule for target [${acl_binary[$count]}], under the [@${category[$count]}] category\n"
            acl_command="zncrypt acl --add -r \"ALLOW @${category[$count]} * ${acl_binary[$count]}\""
            cat $password_file | eval "$acl_command" | tail -n+2
            if [[ $? -ne 0 ]]; then
                err "Could not add ACL for binary '${acl_binary[$count]}'. Please check command output for more information."
            fi
        fi
        let count=$count+1
    done
}

function main {
    printBanner
    test $UID -eq 0 || err "Please run with administrative privileges."
    which zncrypt &>/dev/null || err "Please install zNcrypt before continuing."
    printf "\n"
    createRandomPassword
    registerClient
    prepareClient
    encryptData
    addRules
    printf "\nCompleted! Your zNcrypt password can be found at: $password_file\n"
}

main
