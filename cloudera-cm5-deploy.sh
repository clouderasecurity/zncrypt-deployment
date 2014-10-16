#!/bin/bash 
#
# Author:: Ross McDonald (ross.mcdonald@cloudera.com)
# Copyright 2014, Cloudera, Inc.
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

echo "- Starting."

log_file=/tmp/cm5-deploy.log

function err {
    # Fatal error, kill it
    test -f $log_file && cat $log_file
    printf "FATAL :: $@\n" && exit 1
}

function warn {
    # Just a warning, carry on
    printf "WARNING :: $@\n"
}

# Check prereqs
test $UID -eq 0 || err "Please run with administrative privileges."
test -f /etc/redhat-release || err "Sorry, only RHEL-variant systems are supported by this script."

# Check system memory, make sure we have enough
total_memory="$(awk '/MemTotal/ { print $2}' /proc/meminfo)"
minimum_memory=996  
test $total_memory -gt $minimum_memory || err "You need at least 1024 MB of memory to run CM5 (you have $total_memory)."

# Install EPEL (if not already there)
if [[ ! -f /etc/yum.repos.d/epel.repo ]]; then
    echo "-- Installing EPEL repositories."
    rpm -Uvh http://download.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm &>$log_file || warn "Received a bad return value during EPEL installation. Continuing..."
fi

# Install python (if not already there)
which python &>/dev/null
if [[ $? -ne 0 ]]; then 
    echo "-- Installing python."
    yum install python -y &>$log_file || warn "Received a bad return code while attempting to install python. Continuing..."
fi

# Disable iptables
echo "-- Stopping iptables." && service iptables stop &>$log_file

# Disable selinux
current_selinux_status="$(sestatus | awk '/Current mode/ { print $3 }')"
if [[ $current_selinux_status = "enforcing" ]]; then
    echo "-- Disabling selinux" && setenforce 0
fi

# Add the Cloudera Manager 5 repository, and import the signing key
if [[ ! -f /etc/yum.repos.d/cloudera-manager.repo ]]; then
    echo "-- Installing Cloudera Manager 5 repository."
    curl http://mirror.infra.cloudera.com &>/dev/null
    if [[ $? -eq 0 ]]; then
	echo "--- Using internal mirror."
	curl -o /etc/yum.repos.d/cloudera-manager.repo http://mirror.infra.cloudera.com/archive/cm5/redhat/6/x86_64/cm/cloudera-manager.repo &>$log_file || err "Could not retrieve CM5 repository file."
    else
	curl -o /etc/yum.repos.d/cloudera-manager.repo http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/cloudera-manager.repo &>$log_file || err "Encountered an error while downloding the CM5 repository file."
    fi
    rpm --import $(awk '/GPG/ { print $3 }' /etc/yum.repos.d/cloudera-manager.repo) &>$log_file || warn "Received a bad return code while importing the Cloudera GPG key. Continuing..."
fi

required_packages=( "jdk" "cloudera-manager-daemons" "cloudera-manager-server" "cloudera-manager-server-db-2" )
for p in ${required_packages[@]}; do
    rpm -qa | grep $p &>$log_file
    if [[ $? -ne 0 ]]; then
	echo "-- Installing package: $p"
	yum install $p -y &>$log_file || err "Encountered an error while installing: $p"
    fi
done

# Initialize the database, but ignore any errors
test -x /etc/init.d/postgresql && service postgresql initdb &>$log_file

services_to_start=( "cloudera-scm-server-db" "cloudera-scm-server" )
for s in ${services_to_start[@]}; do
    echo "-- Starting service: $s"
    service $s start &>$log_file || err "Could not start service: $s"
done

echo -n "-- Waiting for CM server to come up. This process may take up to 5 minutes on first boot, so hang tight."
for i in $(seq 1 31); do
    # Sleep for 5 seconds, then check for something (hopefully CM) listening on port 7180
    sleep 10
    netstat -tlupn | grep 7180 &>$log_file && break
    printf "."
done
echo ""

netstat -tlupn | grep 7180 &>$log_file || err "CM never came up. Please check log output."

echo "- Done."
#echo ""
#echo "Protip: Want to access the console without having to configure your firewall? Use SSH tunneling (from your local machine):"
#echo ""
#curl -s 169.254.169.254 --connect-timeout 1 &>/dev/null
#if [[ $? -eq 0 ]]; then
#    # AWS
#    echo "ssh -L 7180:$(curl -s http://169.254.169.254/latest/meta-data/public-hostname):7180 $(whoami)@$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)"
#else
    # Not AWS
#    echo "ssh -L 7180:$(hostname -f):7180 $(whoami)@$(hostname -f)"
#fi
#echo ""
#echo "And then visit (from a web browser): http://localhost:7180"
#echo ""
