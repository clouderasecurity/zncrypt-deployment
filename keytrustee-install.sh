#!/bin/bash 
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
#
# * Please check Key Trustee Server product page for list of supported 
# Linux distributions and versions.

printf "Starting...\n"

# FILL THESE IN!
repo_username=""
repo_password=""

#####
# Global variables
#####

log_file="/tmp/keytrustee-server-install.log"

declare package_manager
declare architecture
declare operating_system
declare codename
declare version

#####
# Error handling
#####

function err {
    printf "\n\nFATAL -- $@\n\n"
    test -f $log_file && cat $log_file
    exit 1
}

#####
# Installation helper functions
#####

# Determine which package manager the system is using. Only `apt-get` and `yum` are currently supported.
function get_package_manager {
    if [[ -x /usr/bin/yum ]]; then
        package_manager="yum"
    elif [[	 -x /usr/bin/apt-get ]]; then
        package_manager="apt-get"
    else
        err "Could not find any valid package managers. Stopping."
    fi
    return 0
}

# Retrieve system architecture.
function get_architecture {
    architecture="$(uname -p)"
    return 0
}

# Determine the system Linux distribution.
function get_distribution {
    test -f /etc/lsb-release && grep -i "ubuntu" /etc/lsb-release &>/dev/null
    if [[ $? -eq 0 ]]; then
        operating_system="ubuntu"
    elif [[ -f /etc/redhat-release ]]; then
        if [[ -f /etc/oracle-release ]]; then
            operating_system="oracle"
        elif [[ -f /etc/centos-release ]]; then
            operating_system="centos"
        else
            operating_system="redhat"
        fi
    elif [[ -f /etc/system-release ]]; then
        operating_system="amazon"
    else
        err "Could not reliably determine operating system. Stopping."
    fi
    return 0
}

# Retrieve detailed version information for the system.
function get_version_information {
    case "$operating_system" in
        ubuntu )
        codename="$(cat /etc/lsb-release | tr = \ | awk '/CODENAME/ { print $2 }')"
        test -z $codename && err "Could not determine $operating_system codename/version. Stopping." 
        version="$(cat /etc/lsb-release | tr = \ | awk '/DISTRIB_RELEASE/ { print $2 }')"
        test -z $version && printf "Could not determine version information. Continuing, but this might cause issues later.\n"
        ;;
        redhat | oracle | centos )
        version="$(cat /etc/$operating_system-release | grep -i "\<[0-9]\.[0-9]" | tr -d [:alpha:],[=\(=],[=\)],[:blank:])"
        test -z $version && err "Could not determine $operating_system version. Stopping." 
        ;;
        amazon )
        # set to 6 due to there not being a repo for amazon linux
        version="6"
        test -z $version && err "Could not determine $operating_system version. Stopping."
        ;;
        * )
        err "Invalid operating system version (get_version_information). Stopping."
        ;;
    esac
    return 0
}

# Determine all system settings and parameters (version, codenames, etc.).
function set_system_parameters {
    get_package_manager || err "Could not determine your package manager information."
    get_architecture || err "Could not reliably determine your architecture."
    get_distribution || err "Could not reliably determine your Linux distribution."
    get_version_information || err "Could not reliably determine your distribution version information."
    printf "System parameters:\n"
    printf "\t- operating system = $(uname -s)\n"
    printf "\t- distribution = $operating_system\n"
    if [[ $operating_system = "ubuntu" ]]; then
        printf "\t- codename = $codename\n"
    fi
    printf "\t- version = $version\n"
    printf "\t- architecture = $architecture\n"
    printf "\t- kernel version = $(uname -r)\n"
    printf "\t- package manager = $package_manager\n"
    printf "\n* If errors are encountered, please send the above information to support@gazzang.com.\n\n"
    return 0
}

# Ensure Gazzang repositories are installed and active.
function check_repositories {
    build_version="stable"
    test -z $repo_username && err "Please specify a repository username."
    test -z $repo_password && err "Please specify a repository password."
    case "$package_manager" in
        "yum" )
        if [[ ! -f /etc/yum.repos.d/gazzang.repo ]]; then
            printf "Creating Gazzang repo file.\n"
            printf "[gazzang]\nname=RHEL $build_version - Gazzang\nbaseurl=https://$repo_username:$repo_password@archive.gazzang.com/redhat/$build_version/${version:0:1}\nenabled=1\ngpgcheck=1\ngpgkey=https://archive.gazzang.com/gpg_gazzang.asc\n" > /etc/yum.repos.d/gazzang.repo
            curl -sO https://archive.gazzang.com/gpg_gazzang.asc && rpm --import gpg_gazzang.asc && rm -f gpg_gazzang.asc && printf "Gazzang GPG signing key imported.\n"
        fi
        grep "enabled=0" /etc/yum.repos.d/gazzang.repo &>$log_file
        if [[ $? -ne 0 ]]; then
            printf "Re-enabling Gazzang repositories.\n"
            sed -i s/enabled=0/enabled=1/ /etc/yum.repos.d/gazzang.repo &>$log_file
        fi
        ls -la /etc/yum.repos.d/*epel* &>$log_file
        if [[ $? -ne 0 ]]; then
            printf "Adding the EPEL repository.\n"
            if [[ ${version:0:1} -eq 6 ]]; then
                rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm &>$log_file || printf "Could not add EPEL repository. This might cause package resolution errors later.\n"
            elif [[ ${version:0:1} -eq 5 ]]; then
                rpm -Uvh http://download.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm &>$log_file || printf "Could not add EPEL repository. This might cause package resolution errors later.\n"
            else
                printf "Skipped adding EPEL repository.\n"
            fi
        fi
        ;;
        "apt-get" )
        cat /etc/apt/sources.list | grep "gazzang" &>$log_file
        if [[ $? -ne 0 ]]; then
            printf "Adding Gazzang repository to apt-get's sources list.\n"
            printf "deb https://$repo_username:$repo_password@archive.gazzang.com/ubuntu/$build_version $codename main\n" >> /etc/apt/sources.list
            curl -sL https://archive.gazzang.com/gpg_gazzang.asc | apt-key add - &>$log_file && printf "Gazzang GPG signing key imported.\n" || printf "Could not import Gazzang's GPG signing key. This might cause issues during the install.\n"
        fi
        ;;
        * )
        err "Invalid package manager (check_repositories)."
        ;;
    esac
    return 0
}

function install_prerequisites {
    required_packages=( "haveged" )
    if [[ $package_manager = "yum" ]]; then
        check_command="rpm -q"
        search_command="yum list"
        refresh_command="yum clean all"
    elif [[ $package_manager = "apt-get" ]]; then
        check_command="dpkg -l"
        search_command="apt-cache search all"
        refresh_command="apt-get update"
    else
        err "Invalid package manager configuration (check_prerequisites)."
    fi
    printf "Refreshing package manager listings.\n" && $refresh_command &>$log_file
    for package in ${required_packages[@]}; do
        printf "Checking for package $package.\n"
        $check_command $package &>$log_file
        if [[ $? -ne 0 ]]; then
            printf "\t- Package $package not installed. Attempting to install with $package_manager.\n"
            $package_manager install $package -y &>$log_file
            $check_command $package &>$log_file
            if [[ $? -ne 0 ]]; then
                printf "\t- Could not install $package. Continuing, but this might cause issues later.\n"
            else
                printf "\t- Successfully installed.\n"
            fi
        else
            printf "\t- Already installed.\n"
        fi
    done
}

function install_keytrustee_server {
    printf "Checking for Key Trustee Server.\n"
    case "$operating_system" in
        "centos" | "redhat" | "oracle" )
        rpm -q ztrustee-server &>$log_file && printf "\t- Already installed.\n" && return 0
        printf "\t- Not present. Installing Key Trustee Server with yum.\n" && yum install ztrustee-server -y &>$log_file || err "Key Trustee Server could not be installed. Stopping."
        chkconfig --level 2345 httpd on &>$log_file
        chkconfig --level 2345 postgresql on &>$log_file
        chkconfig --level 2345 postfix &>$log_file
        chkconfig --level 2345 haveged on &>$log_file
        ;;
        "ubuntu" | "debian" )
        dpkg --list | grep ztrustee-server &>$log_file && printf "\t- Already installed.\n" && return 0
        printf "\t- Not present. Installing Key Trustee Server with apt-get.\n" && apt-get install ztrustee-server -y &>$log_file
        ;;
        * )
        err "Invalid package manager (install_keytrustee_server)."
        ;;
    esac
    test -d /usr/lib/ztrustee-server || err "Key Trustee Server could not be installed (install_keytrustee_server)."
    return 0
}

# Disable repositories to prevent unintended upgrades.
function disable_repositories {
    case "$operating_system" in
        "redhat" | "centos" | "oracle" | "amazon" )
        sed -i s/enabled=1/enabled=0/g /etc/yum.repos.d/gazzang.repo &>$log_file
        if [[ $? -ne 0 ]]; then
            printf "Could not disable Gazzang repositories. Please disable to prevent accidental upgrades.\n" && return 1
        else
            printf "Gazzang $package_manager repositories disabled to prevent accidental upgrade.\n" && return 0
        fi
        ;;
        "ubuntu" )
        sed -i '/gazzang/d' /etc/apt/sources.list &>$log_file
        if [[ $? -ne 0 ]]; then
            printf "Could not disable Gazzang repository. Please disable to prevent accidental upgrades.\n" && return 1
        else
            printf "Gazzang repository removed from $package_manager sources list.\n" && return 0
        fi
        ;;
        * )
        err "Invalid operating system (disable_repositories)."
        ;;
    esac
    return 0
}

function start_haveged {
    /etc/init.d/haveged start &>$log_file || printf "Could not start the haveged process. This might dramatically slow down your registration process. Continuing.\n" && return 1
    printf "Haveged (used for secure key generation) started.\n"
    return 0
}

function stop_iptables {
    which iptables &>/dev/null || return
    printf "Checking current iptables status.\n"
    service iptables status &>/dev/null
    if [[ $? -eq 0 ]]; then
	printf "\t- Stopping iptables.\n"
	service iptables stop &>$log_file || printf "Could not stop iptables. This might cause issues later. Continuing...\n" && return 1
    else
	printf "\t- Not running.\n"
    fi
}

# Stop apparmor (if applicable). If you have a requirement on apparmor, please contact support@gazzang.com.
function stop_apparmor {
    which apparmor_status &>$log_file || return	
    printf "Checking current apparmor status.\n"
    apparmor_status | grep "0 profiles are in enforce mode." &>$log_file 
    if [[ $? -ne 0 ]]; then
        service apparmor stop &>$log_file && printf "\t- Service stopped.\n"
        service apparmor teardown &>$log_file && printf "\t- Process tear-down complete.\n"
        update-rc.d apparmor disable &>$log_file && printf "\t- Removed from start-order.\n"
        printf "\n*If you would like to re-enable apparmor, please contact support@gazzang.com\n\n"
    else
        printf "\t- Not running.\n"
    fi
}

# Stop selinux (if applicable). If you have a requirement on selinux, please contact support@gazzang.com.
function stop_selinux {
    which sestatus &>$log_file || return	
    printf "Checking current selinux status.\n"
    sestatus | grep "Current mode:.*enforcing" &>$log_file 
    if [[ $? -eq 0 ]]; then
        setenforce 0 &>$log_file && printf "\t- Currently enabled. Disabling.\n"
    else
        printf "\t- Already disabled.\n"
    fi
	
    if [[ -f /etc/selinux/config ]]; then
        cat /etc/selinux/config | grep SELINUX=enforcing &>$log_file
        if [[ $? -eq 0 ]]; then
            sed -i.before_keytrustee s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config && printf "\t- Modified configuration from enforcing to disabled.\n"
        fi
    fi
}

function run_postinst_configuration {
    case "$operating_system" in
        "rhel" | "centos" | "oracle" )
	    test -f /usr/lib/ztrustee-server/postinst/completed && return
	    printf "Running post-installation steps...\n"
	    hostname -f &>/dev/null || err "Please ensure your system's hostname is properly set."
	    /usr/lib/ztrustee-server/postinst/setup-rh &>$log_file || err "Post-installation scripts failed. Please check log output."
	    touch /usr/lib/ztrustee-server/postinst/completed
	    ;;
	*)
	    return
	    ;;
    esac
}

function verify_install {
    curl -k https://localhost/?a=fingerprint &>$log_file || err "Could not retrieve public key from install. Please check logs for more information."
    printf "Installation verified. Server is up and servicing requests.\n"
}

#####
# Script meta
#####

function print_banner {
    color="\x1b[32m"
    company_color="\x1b[34m"
	echo -e "$color                _____                _            
  /\\ /\\___ _   /__   \_ __ _   _ ___| |_ ___  ___ 
 / //_/ _ \ | | |/ /\\/ '__| | | / __| __/ _ \\/ _ \\
/ __ \\  __/ |_| / /  | |  | |_| \\__ \\ ||  __/  __/
\/  \/\\___|\__, \/   |_|   \\__,_|___/\\__\\___|\\___|
     _____ |___/     _        _ _                 
     \\_   \\_ __  ___| |_ __ _| | | ___ _ __       
      / /\\/ '_ \\/ __| __/ _\` | | |/ _ \\ '__|      
   /\\/ /_ | | | \\__ \ || (_| | | |  __/ |         
   \\____/ |_| |_|___/\\__\\__,_|_|_|\\___|_|\x1b[0m Powered by$company_color Cloudera\x1b[0m
"
}

function check_for_root {
    test $UID -eq 0 || err "Please rerun with super user (sudo/root) privileges."
    return 0
}

function check_script_prerequisites {
    check_for_root
    which curl &>$log_file || err "The program 'curl' is required for this script to run. Please install before continuing."
    return 0
}


#####
# Main function
#####

function main {
    start_time="$(date +%s)"
    print_banner
    check_script_prerequisites
    set_system_parameters
    check_repositories
    install_prerequisites || err "System prerequisites could not be installed. Please check log output for more detail."
    start_haveged
    install_keytrustee_server || err "Could not install Key Trustee Server. Please check logs for more detail."
    stop_apparmor
    stop_selinux
    stop_iptables
    disable_repositories
    run_postinst_configuration
    verify_install
    end_time="$(date +%s)"
}

main $@

#####
# Fin
#####

printf "\nExecution completed (took $(( $end_time - $start_time )) second(s)).\n"
