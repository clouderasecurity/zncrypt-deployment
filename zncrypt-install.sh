#!/bin/bash 
#
# Author:: Ross McDonald (ross.mcdonald@gazzang.com)
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
# Currently* supported Linux distributions for zNcrypt:
#   - Ubuntu 12.04
#   - Amazon Linux 2013.09
#   - RHEL/CentOS 5.9+ (untested), 6.x
#
# Currently* supported Linux distributions for zTrustee Server:
#   - Ubuntu 12.04
#   - RHEL/CentOS 6.x
#
# * Please check zNcrypt product page for full listing of supported distros.

printf "Starting...\n"

#####
# Global variables
#####

declare package_manager
declare architecture
declare operating_system
declare codename
declare version

declare repo_username
declare repo_password

#####
# Error handling
#####

function err {
	printf "FATAL -- $@\n"
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
	if [[ -f /etc/lsb-release ]]; then
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
	case "$package_manager" in
		"yum" )
			if [[ ! -f /etc/yum.repos.d/gazzang.repo ]]; then
				printf "Creating Gazzang repo file.\n"
				printf "[gazzang]\nname=Gazzang - $operating_system\nbaseurl=https://archive.gazzang.com/redhat/$build_version/${version:0:1}\nenabled=1\ngpgcheck=1\ngpgkey=https://archive.gazzang.com/gpg_gazzang.asc\n" > /etc/yum.repos.d/gazzang.repo
				curl -sO https://archive.gazzang.com/gpg_gazzang.asc && rpm --import gpg_gazzang.asc && rm -f gpg_gazzang.asc && printf "Gazzang GPG signing key imported.\n"
			fi
			vault_repo_url="http://vault.centos.org/$version/os/$architecture"
			grep "$vault_repo_url" /etc/yum.repos.d/* &>/dev/null
			if [[ $? -ne 0 ]] && [[ $operating_system = "centos" ]]; then
				printf "Adding temporary repo for previous releases of CentOS.\n"
				printf "\n[C6.4-base]\nname=CentOS-6.4 - Base\nbaseurl=$vault_repo_url\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6\nenabled=1\n" >> /etc/yum.repos.d/gazzang.repo
			fi
			grep "enabled=0" /etc/yum.repos.d/gazzang.repo &>/dev/null
			if [[ $? -ne 0 ]]; then
				printf "Re-enabling Gazzang repositories.\n"
				sed -i s/enabled=0/enabled=1/ /etc/yum.repos.d/gazzang.repo &>/dev/null
			fi
			;;
		"apt-get" )
			cat /etc/apt/sources.list | grep "gazzang" &>/dev/null
			if [[ $? -ne 0 ]]; then
				printf "Adding Gazzang repository to apt-get's sources list.\n"
				printf "deb https://archive.gazzang.com/ubuntu/$build_version $codename main\n" >> /etc/apt/sources.list
				curl -sL https://archive.gazzang.com/gpg_gazzang.asc | apt-key add - &>/dev/null && printf "Gazzang GPG signing key imported.\n" || printf "Could not import Gazzang's GPG signing key. This might cause issues during the install.\n"
			fi
			;;
		* )
			err "Invalid package manager (check_repositories)."
			;;
	esac
	return 0
}

# Install zNcrypt prerequisites for the system.
function install_prerequisites {
	required_packages=( "make" "perl" "lsof" "haveged" )
	if [[ $package_manager = "yum" ]]; then
		check_command="rpm -q"
		search_command="yum list"
		refresh_command="yum clean all"
		required_packages=( ${required_packages[@]} "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" )
	elif [[ $package_manager = "apt-get" ]]; then
		check_command="dpkg -l"
		search_command="apt-cache search all"
		refresh_command="apt-get update"
		required_packages=( ${required_packages[@]} "linux-headers-$(uname -r)" )
	else
		err "Invalid package manager configuration (check_prerequisites)."
	fi
	printf "Refreshing package manager listings.\n" && $refresh_command &>/dev/null
	for package in ${required_packages[@]}; do
		printf "Checking for package $package.\n"
		$check_command $package &>/dev/null
		if [[ $? -ne 0 ]]; then
			printf "\t- Package $package not installed. Attempting to install with $package_manager.\n"
			$package_manager install $package -y &>/dev/null
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

# Install zNcrypt.
function install_zncrypt {
	printf "Checking for zncrypt.\n"
	case "$operating_system" in
		"centos" | "redhat" | "oracle" )
			rpm -q zncrypt &>/dev/null && printf "\t- Already installed.\n" && return 0
			printf "\t- Not present. Installing zNcrypt with yum.\n" && yum install zncrypt -y &>/dev/null || err "zNcrypt could not be installed. Stopping."
			chkconfig --level 2345 zncrypt-mount on &>/dev/null
			chkconfig --level 2345 haveged on &>/dev/null
			;;
		"ubuntu" | "debian" )
			dpkg --list | grep zncrypt &>/dev/null && printf "\t- Already installed.\n" && return 0
			printf "\t- Not present. Installing zNcrypt with apt-get.\n" && apt-get install zncrypt -y &>/dev/null
			;;
		"amazon" )
			rpm -q zncrypt &>/dev/null && printf "\t- Already installed.\n" && return 0
			# Begin hack
			printf "\t- Switching to Amazon Linux configuration.\n"
			printf "\t- Removing cryptsetup* packages.\n" && yum remove cryptsetup* -y &>/dev/null
			printf "\t- Readding keyutils.\n" && yum install keyutils -y &>/dev/null
			printf "\t- Re-installing cryptsetup-luks-libs-1.2.0-7.\n" && wget https://s3.amazonaws.com/gazzang-implementation/cryptsetup-luks-libs-1.2.0-7.el6.x86_64.rpm &>/dev/null && rpm -i cryptsetup-luks-libs-1.2.0-7.el6.x86_64.rpm &>/dev/null
			printf "\t- Re-installing cryptsetup-luks-1.2.0-7.\n" && wget https://s3.amazonaws.com/gazzang-implementation/cryptsetup-luks-1.2.0-7.el6.x86_64.rpm &>/dev/null && rpm -i cryptsetup-luks-1.2.0-7.el6.x86_64.rpm &>/dev/null
			printf "\t- Re-installing ecryptfs-utils-82-6.el6_1.3.\n" && wget https://s3.amazonaws.com/gazzang-implementation/ecryptfs-utils-82-6.el6_1.3.x86_64.rpm &>/dev/null && rpm -i ecryptfs-utils-82-6.el6_1.3.x86_64.rpm &>/dev/null
			printf "\t- Re-installing trousers-0.3.4-4.\n" && wget https://s3.amazonaws.com/gazzang-implementation/trousers-0.3.4-4.el6.x86_64.rpm &>/dev/null && rpm -i trousers-0.3.4-4.el6.x86_64.rpm &>/dev/null
			rm -f *.rpm &>/dev/null
			# End hack
			printf "\t- Installing zNcrypt with yum.\n" && yum install zncrypt -y &>/dev/null || err "zNcrypt could not be installed. Stopping."
			chkconfig --level 2345 zncrypt-mount on &>/dev/null
			chkconfig --level 2345 haveged on &>/dev/null
			;;
		* )
			err "Invalid package manager (install_zncrypt)."
			;;
	esac
	which zncrypt &>/dev/null || err "zNcrypt could not be installed (install_zncrypt)."
	return 0
}

# Disable repositories to prevent unintended upgrades.
function disable_repositories {
	case "$operating_system" in
		"redhat" | "centos" | "oracle" | "amazon" )
			sed -i s/enabled=1/enabled=0/ /etc/yum.repos.d/gazzang.repo &>/dev/null
			if [[ $? -ne 0 ]]; then
				printf "Could not disable Gazzang repositories. Please disable to prevent accidental upgrades.\n" && return 1
			else
				printf "Gazzang $package_manager repositories disabled to prevent accidental upgrade.\n" && return 0
			fi
			;;
		"ubuntu" )
			sed -i '/gazzang/d' /etc/apt/sources.list &>/dev/null
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

# Remove zncrypt-ping cron job.
function remove_zncrypt_ping {
	if [[ -f /etc/cron.hourly/zncrypt-ping ]]; then
		rm -f /etc/cron.hourly/zncrypt-ping &>/dev/null
	fi
}

# Check status of kernel module. If not present, build it.
function check_zncryptfs {
	which zncrypt-module-setup &>/dev/null || err "zNcrypt not installed (check_zncryptfs). Stopping."
	printf "Checking for zNcrypt kernel module.\n" && test -f /var/lib/dkms/zncryptfs/3*/$(uname -r)*/$(uname -i)/module/*.ko
	if [[ $? -ne 0 ]]; then
		printf "\t- Not found. Building zNcrypt kernel module.\n" && zncrypt-module-setup
		if [[ $? -ne 0 ]]; then
			err "zNcrypt kernel module (zncryptfs) did not build correctly."
		fi
	else
		printf "\t- Already present.\n"
	fi
	return 0
}

# Start the haveged service. This aids in secure key generation during zNcrypt's registration phase.
function start_haveged {
	/etc/init.d/haveged start &>/dev/null || printf "Could not start the haveged process. This might dramatically slow down your registration process. Continuing.\n" && return 1
	printf "Haveged (used for secure key generation) started.\n"
	return 0
}

# Stop apparmor (if applicable). If you have a requirement on apparmor, please contact support@gazzang.com.
function stop_apparmor {
	which apparmor_status &>/dev/null || return	
	printf "Checking current apparmor status.\n"
	apparmor_status | grep "0 profiles are in enforce mode." &>/dev/null 
	if [[ $? -ne 0 ]]; then
		service apparmor stop &>/dev/null && printf "\t- Service stopped.\n"
		service apparmor teardown &>/dev/null && printf "\t- Process tear-down complete.\n"
		update-rc.d apparmor disable &>/dev/null && printf "\t- Removed from start-order.\n"
		printf "\n*If you would like to re-enable apparmor, please contact support@gazzang.com\n\n"
	else
		printf "\t- Not running.\n"
	fi
}

# Stop selinux (if applicable). If you have a requirement on selinux, please contact support@gazzang.com.
function stop_selinux {
	which sestatus &>/dev/null || return	
	printf "Checking current selinux status.\n"
	sestatus | grep "Current mode:.*enabled" &>/dev/null 
	if [[ $? -eq 0 ]]; then
		setenforce 0 &>/dev/null && printf "\t- Currently enabled. Disabling.\n"
	else
		printf "\t- Already disabled.\n"
	fi
	
	if [[ -f /etc/selinux/config ]]; then
		cat /etc/selinux/config | grep SELINUX=enforcing &>/dev/null
		if [[ $? -eq 0 ]]; then
			sed -i.before_zncrypt s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config && printf "\t- Modified configuration from enforcing to disabled.\n"
		fi
	fi
}

#####
# Script meta
#####

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
	#echo -e "* Logging enabled, check '\x1b[36m$log_file\x1b[0m' for command output.\n"
}

function check_for_root {
	test $UID -eq 0 || err "Please rerun with super user (sudo/root) privileges."
	return 0
}

function check_script_prerequisites {
	check_for_root
	which curl &>/dev/null || err "The program 'curl' is required for this script to run. Please install before continuing."
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
	install_zncrypt || err "Could not install zNcrypt. Please check logs for more detail."
	remove_zncrypt_ping
	check_zncryptfs
	start_haveged
	stop_apparmor
	stop_selinux
	disable_repositories
	end_time="$(date +%s)"
}

main $@

#####
# Fin
#####

printf "\nExecution completed (took $(( $end_time - $start_time )) second(s)).\n"
