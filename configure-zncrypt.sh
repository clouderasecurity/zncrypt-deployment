#!/bin/bash
#
#

# zNcrypt automatic configuration script. This assumes zNcrypt is already installed.

password_file="/root/zncrypt-password"

function err {
    printf "\nError: $@\n"
    exit 1
}

function createRandomPassword {
    test ! -f $password_file || return
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

function registerClient {
    test ! -f /etc/zncrypt/ztrustee/clientname || return
    printf "\nWhat zTrustee Server would you like to use? [ztdemo.gazzang.net]\n"
    read keyserver
    test ! -z $keyserver || keyserver="ztdemo.gazzang.net"
    verifyConnectivity $keyserver

    printf "\n\nWhat organization would you like to register against? []\n"
    read org
    printf "\nWhat is the authorization code for '$org' organization? []\n"
    read auth

    register_command="zncrypt register -s $keyserver -t single-passphrase"
    # Test for 0 length strings to maintain compatibility with classic reg mode
    test -z $org || register_command="$register_command -o $org"
    test -z $auth || register_command="$register_command --auth=$auth"
    
    printf "__________________________________________________\n"
    printf "\nNote!\nTo manually register more clients, you can use the following command:\n"
    printf "\n\$ $register_command\n"
    printf "__________________________________________________\n"
    
    printf "$(cat $password_file)\n$(cat $password_file)" | $register_command
    if [[ $? -ne 0 ]]; then
        err "Could not register with keyserver."
    fi
}

function prepareClient {
    printf "\nDo you need to prepare any drives/directories for encryption? [no]\n"
    read response
    test "${response:0:1}" = "y" || test "${response:0:1}" = "Y" || return
    unset response
    
    printf "\nWhere would you like to store the encrypted data? [/var/lib/zncrypt/.private]\n"
    read storage
    test ! -z $storage || storage="/var/lib/zncrypt/.private"
    test ! -b $storage || err "Sorry, block-level encryption is not support by this script (yet)."
    test -d $storage || mkdir -p $storage
    
    printf "\nAnd where would you like to mount the encrypted data? [/var/lib/zncrypt/encrypted]\n"
    read mount
    test ! -z $mount || mount="/var/lib/zncrypt/encrypted"
    test -d $mount || mkdir -p $mount
    
    prepare_command="zncrypt-prepare $storage $mount"
    printf "__________________________________________________\n"
    printf "\nNote!\nTo manually prepare more drives, you can use a command similar to:\n"
    printf "\n\$ $prepare_command\n"
    printf "__________________________________________________\n"
    
    cat $password_file | eval "$prepare_command"
    if [[ $? -ne 0 ]]; then
        err "Could not prepare directory."
    fi
}

function encryptData {
    printf "\nDo you want to encrypt any data? [no]\n"
    read response
    test "${response:0:1}" = "y" || test "${response:0:1}" = "Y" || return
    unset response
    
    printf "\nWhat data would you like to encrypt? This can be either a directory or just a file.\n"
    read to_encrypt
    test ! -z $to_encrypt || err "A valid directory or file location must be specified."
    test -L $to_encrypt || to_encrypt="$(ls $to_encrypt | xargs readlink -f)" && printf "You specified a symbolic link. Setting new encryption target to '$to_encrypt'.\n"
    test -d $to_encrypt || test -f $to_encrypt || err "A valid directory or file location must be specified."
    
    if [[ -z $mount ]]; then
        printf "\nWhat encrypted partition would you like to use to store your data?"
        read response
        test ${response:0:1} = "y" || test ${response:0:1} = "Y" || return
        unset response
    else
        printf "\nYou specified the mount location: $mount from before. Would you like to use that location to store encrypted data? [yes]"
        read response
        test ${response:0:1} = "y" || test ${response:0:1} = "Y" || return
        unset response
    fi
    test -z $mount || err "Need to specify encrypted partition."
    cat $password_file | zncrypt-move encrypt @auto $to_encrypt $mount
}

function addRules {
    printf "\nDo you want to set any ACL rules? [no]\n"
    read response
    test "${response:0:1}" = "y" || test "${response:0:1}" = "Y" || return
    unset response
    
    printf "\nWhat binary would you like to allow access to the encrypted data?\n"
    read binary
    test -z $binary || err "Please specify a valid binary."
    test -L $binary || binary="$(ls $binary | xargs readlink -f)" && printf "You specified a symbolic link. Setting new binary target to '$binary'.\n"
    test -x $binary || err "A valid executable must be specified."
    cat $password_file | zncrypt acl --add -r "ALLOW @auto * $binary"
}

function main {
    test $UID -eq 0 || err "Please run with administrative privileges."
    which zncrypt &>/dev/null || err "Please install zNcrypt before continuing."
    createRandomPassword
    registerClient
    prepareClient
    encryptData
    addRules
}

main

exit 0