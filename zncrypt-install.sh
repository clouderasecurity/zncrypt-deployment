#!/bin/bash
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
#
# Currently supported Linux distributions:
#   - Ubuntu 10.04, 12.04+
#   - Amazon Linux 2013.09x
#   - RHEL/CentOS 5.9+, 6.x

##########################################################################
# DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING
# FOR BUGS, PLEASE NOTIFY SUPPORT@GAZZANG.COM
##########################################################################

####
## Configuration Variables (can modify, but be careful)
####

# Display extra messages during script execution
debug="false"

# string to identify which repo to install from, acceptable values are: stable|proposed|testing|unstable
# please note that credentials are required to use the unstable/testing repos (leave blank otherwise)
repo="stable"
# credentials for the unstable/testing repositories
repo_username=""
repo_password=""

####
## Global Variables (script-use only, do not modify)
####

# string to declare operating system (ie rhel, oracle, ubuntu, debian, etc.)
declare os
# version only applies to rhel/centos-based systems (ie 5, 6)
declare os_version
# codename only applies to ubuntu-based distributions (ie precise, natty, etc.)
declare os_codename
# string to declare system default package manaager (ie yum, apt-get, etc.)
declare package_manager

# log files
log_file="/tmp/zncrypt-installation-$(date +%Y%m%d_%H%M%S).log"

####
## Utilities (pretty printing, error reporting, etc.)
####

function print_banner {
    color="\x1b[34m"
    company_color="\x1b[32m"
    echo -e "$color                          _                  
 ____ _  __ _ _ _  _ _ __| |_  
|_ / ' \\/ _| '_| || | '_ \\  _|               
/__|_||_\\__|_|_ \\_, | .__/\\__|   _ _         
             (_)|__/|_|| |_ __ _| | |___ _ _ 
             | | ' \\(_-<  _/ _\` | | / -_) '_|
             |_|_||_/__/\\__\\__,_|_|_\\___|_|\x1b[0m Powered by$company_color Gazzang, Inc.\x1b[0m
"
    echo -e "* Logging enabled, check '\x1b[36m$log_file\x1b[0m' for command output.\n"
}

function print_error {
    printf "\x1b[31mError: \x1b[0m$@\n"
}

function print_warning {
    printf "\x1b[33mWarning: \x1b[0m$@\n"
}

function print_info {
    printf "\x1b[32mInfo: \x1b[0m$@\n"
}

function execute {
    local full_redirect="1>>$log_file 2>>$log_file"
    /bin/bash -c "$@ $full_redirect"
    ret=$?
    if [[ $debug = "true" ]]; then
        if [ $ret -ne 0 ]; then
            print_warning "Executed command \'$@\', returned non-zero code: $ret"
        else
            print_info "Executed command \'$@\', returned successfully."
        fi
    fi
    return $ret
}

####
## Functions
####

function check_for_root {
    if [[ $UID -ne 0 ]]; then
        print_error "Please run with super user privileges."
        exit 1
    fi
}

function check_prereqs {
    print_info "Checking your system prerequisites..."
    case "$package_manager" in
        yum )
        execute "rpm -q make"
        if [[ $? -ne 0 ]]; then
            print_info "Make is not installed. Attempting to install."
            execute "yum install make -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install make. This may cause issues when compiling the kernel module."
            fi
        fi
        execute "rpm -q perl"
        if [[ $? -ne 0 ]]; then
            print_info "Perl is not installed. Attempting to install."
            execute "yum install perl -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install perl. This may cause issues when compiling the kernel module."
            fi
        fi
        execute "rpm -q kernel-devel-$(uname -r)"
        if [[ $? -ne 0 ]]; then
            print_info "Kernel-devel for your running kernel is not installed. Attempting to install."
            execute "yum install kernel-devel-$(uname -r) -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install kernel-devel. This may cause issues when compiling the kernel module."
            fi
        fi
        execute "rpm -q kernel-headers-$(uname -r)"
        if [[ $? -ne 0 ]]; then
            print_info "Kernel headers for your running kernel is not installed. Attempting to install."
            execute "yum install kernel-headers-$(uname -r) -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install kernel headers. This may cause issues when compiling the kernel module."
            fi
        fi
        execute "rpm -q lsof"
        if [[ $? -ne 0 ]]; then
            print_info "The application 'lsof' is not installed. Attempting to install."
            execute "yum install lsof -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install 'lsof'. This may cause issues later."
            fi
        fi
        #execute "cat /etc/yum.conf | grep \"#.*exclude=kernel\""
        #if [[ $? -eq 0 ]]; then
        #    print_error "Kernel updates have been disabled in your yum configuration. Please enable, then restart installation."
        #    exit 1
        #fi
        ;;
        apt )
        print_info "Updating APT package listings..."
        execute "apt-get update"
        execute "dpkg -l | grep make"
        if [[ $? -ne 0 ]]; then
            print_warning "Make is not installed. Attempting to install."
            execute "apt-get install make -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install make. This may cause issues when compiling the kernel module."
            fi
        fi
        execute "dpkg -l | grep perl"
        if [[ $? -ne 0 ]]; then
            print_warning "Perl is not installed. Attempting to install."
            execute "yum install perl -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install perl. This may cause issues when compiling the kernel module."
            fi
        fi
        execute "dpkg -l | grep linux-headers-$(uname -r)"
        if [[ $? -ne 0 ]]; then
            print_warning "Linux headers for your running kernel are not installed. Attempting to install."
            execute "apt-get install linux-headers-$(uname -r) -y"
            if [[ $? -ne 0 ]]; then
                print_warning "Could not install kernel headers. This may cause issues when compiling the kernel module."
            fi
        fi
        ;;
        * )
        print_error "Sorry, this package manager is not supported yet."
        exit 1
        ;;
    esac
}

function get_system_parameters {
    check_for_root
    print_info "Collecting system configuration..."
    if [[ -f /etc/redhat-release ]]; then
        if [[ -f /etc/oracle-release ]]; then
            os="oracle"
        else
            os="redhat"
        fi
        execute "cat /etc/redhat-release | grep 5\.."
        if [[ $? -eq 0 ]]; then
            os_version=5
        fi
        execute "cat /etc/redhat-release | grep 6\.."
        if [ $? -eq 0 ]; then
            os_version=6
        fi
    elif [[ -f /etc/lsb-release ]]; then
        os="ubuntu"
        os_codename="$(cat /etc/lsb-release | tr = \ | awk '/CODENAME/ { print $2 }')"
        if [[ -z $os_codename ]]; then
            print_error "Sorry, could not determine your Ubuntu codename (ie, precise, etc). Exiting."
            exit 1
        fi
    elif [[ -f /etc/system-release ]]; then
        execute "grep -i \"amazon\" /etc/system-release"
        if [[ $? -ne 0 ]]; then
            print_error "Sorry, this version of Linux is not yet supported."
            exit 1
        fi
        os="amazon"
        os_version="6"
    else
        print_error "Sorry, this version of Linux is not yet supported."
        exit 1
    fi
    
    if [[ -f /usr/bin/yum ]]; then
        package_manager="yum"
    elif [[ -f /usr/bin/apt-get ]]; then
        package_manager="apt"
    else
        print_error "Unsupported package manager. Please contact support@gazzang.com."
        exit 1
    fi
}

function import_key {
    case "$package_manager" in
        yum )
        print_info "Importing Gazzang public key to RPM for package signing verification..."
        execute "curl -o gpg_gazzang.asc http://archive.gazzang.com/gpg_gazzang.asc"
        execute "rpm --import gpg_gazzang.asc"
        if [ $? -ne 0 ]; then
            print_warning "Could not import the Gazzang public key. This might lead to issues later."
        fi
        execute "rm -f gpg_gazzang.asc"
        ;;
        apt )
        print_info "Importing Gazzang public key to APT for package signing verification..."
        execute "curl -o gpg_gazzang.asc http://archive.gazzang.com/gpg_gazzang.asc"
        execute "apt-key add gpg_gazzang.asc"
        if [ $? -ne 0 ]; then
            print_warning "Could not import the Gazzang public key. This might lead to issues later."
        fi
        execute "rm -f gpg_gazzang.asc"
        ;;
        * )
        print_error "Sorry, this package manager is not supported yet."
        exit 1
        ;;
    esac
}

function add_repo {
    import_key
    case "$package_manager" in
        yum )
        print_info "Adding Gazzang repository to yum configuration..."
        if [ ! -f /etc/yum.repos.d/gazzang.repo ]; then
            if [[ -z $repo_username ]]; then
                cat <<EOF > /etc/yum.repos.d/gazzang.repo
[gazzang]
name=RHEL $os_version - gazzang.com - base
baseurl=https://archive.gazzang.com/redhat/$repo/$os_version
enabled=1
gpgcheck=1
gpgkey=http://archive.gazzang.com/gpg_gazzang.asc
EOF
            else
                cat <<EOF > /etc/yum.repos.d/gazzang.repo
[gazzang]
name=RHEL $os_version - gazzang.com - base
baseurl=https://$repo_username:$repo_password@archive.gazzang.com/redhat/$repo/$os_version
enabled=1
gpgcheck=1
gpgkey=http://archive.gazzang.com/gpg_gazzang.asc
EOF
            fi
            execute "test -f /etc/yum.repos.d/gazzang.repo"
            if [ $? -ne 0 ]; then
                print_warning "Could not add Gazzang repository file. Installation might not succeed."
            fi
        fi
        ;;
        apt )
        if [[ -z $os_codename ]]; then
            print_error "Could not determine OS codename."
            exit 1
        fi
        execute "echo \"deb http://archive.gazzang.com/ubuntu/$repo $os_codename main\" | tee -a /etc/apt/sources.list"
        ;;
        * )
        print_error "Sorry, this package manager is not supported yet."
        exit 1
        ;;
    esac
}

function start_haveged {
    print_info "Starting the haveged service for faster key generation..."
    execute "service haveged start"
}

function add_epel {
    execute "ls -la /etc/yum.repos.d/*epel*"
    if [[ $? -ne 0 ]]; then
        print_info "Adding the EPEL repository to yum configuration..."
        if [[ $os_version -eq 5 ]]; then
            execute "curl -o epel.rpm -L http://download.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm"
            execute "rpm -i epel.rpm"
            execute "rm -f epel.rpm"
        elif [[ $os_version -eq 6 ]]; then
            execute "curl -o epel.rpm -L http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm"
            execute "rpm -i epel.rpm"
            execute "rm -f epel.rpm"
        fi
    fi
}

function check_if_installed {
    print_info "Checking to see if zNcrypt is installed..."
    case "$package_manager" in
        yum )
        execute "rpm -qa | grep zncrypt"
        return $?
        ;;
        apt )
        execute "dpkg --list | grep zncrypt"
        return $?
        ;;
        *)
        print_error "This package manager is not supported yet."
        exit 1
    esac
}

function install_amazon {
    print_info "Switching to Amazon Linux configuration..."
    execute "yum remove cryptsetup* -y"
    execute "yum install keyutils -y"
    execute "wget ftp://ftp.icm.edu.pl/vol/rzm4/linux-centos/6.5/os/x86_64/Packages/cryptsetup-luks-1.2.0-7.el6.x86_64.rpm"
    execute "wget ftp://ftp.pbone.net/mirror/ftp.scientificlinux.org/linux/scientific/6.1/x86_64/updates/security/ecryptfs-utils-82-6.el6_1.3.x86_64.rpm"
    execute "wget ftp://ftp.pbone.net/mirror/ftp.scientificlinux.org/linux/scientific/6rolling/x86_64/os/Packages/trousers-0.3.4-4.el6.x86_64.rpm"
    execute "wget http://mirror.centos.org/centos/6/os/x86_64/Packages/cryptsetup-luks-libs-1.2.0-7.el6.x86_64.rpm"
    execute "rpm -i cryptsetup-luks-libs-1.2.0-7.el6.x86_64.rpm"
    execute "rpm -i cryptsetup-luks-1.2.0-7.el6.x86_64.rpm"
    execute "rpm -i trousers-0.3.4-4.el6.x86_64.rpm"
    execute "rpm -i ecryptfs-utils-82-6.el6_1.3.x86_64.rpm"
    execute "rm -f *.rpm"
}

function install {
    check_if_installed
    if [[ $? -eq 0 ]]; then
        print_info "zNcrypt is already installed. Skipping installation step."
        return
    fi
    add_repo
    case "$package_manager" in
        yum )
        add_epel
        if [[ "$os" = "amazon" ]]; then
            install_amazon
        fi
        print_info "Installing packages from Gazzang repository..."
        execute "yum install zncrypt haveged -y"
        if [[ $? -ne 0 ]]; then
            print_error "Could not install zNcrypt."
            exit 1
        fi
        ;;
        apt )
        print_info "Updating APT package listings..."
        execute "apt-get update"
        print_info "Installing packages from Gazzang repository..."
        execute "apt-get install zncrypt haveged -y"
        if [[ $? -ne 0 ]]; then
            print_error "Could not install zNcrypt. Please check error logs."
            exit 1
        fi
        ;;
        * )
        print_error "Sorry, this package manager is not supported yet."
        exit 1
        ;;
    esac
}

function remove_zncrypt_ping {
    if [ -f /etc/cron.hourly/zncrypt-ping ]; then
        execute "rm -f /etc/cron.hourly/zncrypt-ping"
    fi
}

function check_kernel_module {
    print_info "Checking for zNcrypt kernel module..."
    execute "modprobe zncryptfs"
    if [ $? -ne 0 ]; then
        print_info "zNcrypt module not loaded. Building module..."
        execute "zncrypt-module-setup"
        if [ $? -ne 0 ]; then
            print_error "Could not compile zncrypt kernel module. Exiting."
            exit 1
        fi
    fi
}

function stop_selinux {
    which sestatus &>/dev/null || return
    status="$(sestatus | awk '/status/ { print $3 }')"
    if [[ "$status" = "enabled" ]]; then
        print_info "Stopping current selinux process..."
        execute "setenforce 0"
    fi
    if [[ -f /etc/selinux/config ]]; then
        print_info "Disabling selinux through configuration..."
        execute "sed -i.old s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config"
    fi
}

function configure {
    print_info "Configuring zNcrypt..."
    start_haveged
    check_kernel_module
    remove_zncrypt_ping
    case "$os" in
        redhat | oracle | amazon )
        stop_selinux
        execute "chkconfig --level 235 zncrypt-mount on"
        execute "chkconfig --level 235 haveged on"
        ;;
        ubuntu )
        return
        ;;
        * )
        print_error "Sorry, this operating system is not supported yet."
        exit 1
        ;;
    esac
}

####
## Main
####

function main {
    print_banner
    local start_time="$(date +%s)"
    get_system_parameters
    check_prereqs
    install
    configure
    local end_time="$(date +%s)"
    print_info "Done! We took $((end_time - start_time)) seconds in total."
    echo ""
}

main $@