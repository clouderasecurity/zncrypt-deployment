#!/bin/bash
#
# Author:: Ross McDonald (ross.mcdonald@gazzang.com)
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

#####
# SUMMARY
#####
#
# This will install the latest version of Datastax Enterprise Cassandra on
# the current machine, with the recommended DSE system settings enabled. 
# Please only use for testing purposes.
#
# This script comes with no warranty or guarantee. You have been warned.
#
# Tested on Amazon Linux 2013.09+, 2014.03 - passing as of April 2nd, 2014

#####
# TO RUN
#####
#
# Steps to run:
# 1. Obtain repo credentials for DSE, fill in below (repo* variables)
# 2. Execute as root on instance
#
# Please note, if no other IPs are specified (node_ips, seed_ips, etc.) 
# then this will setup Cassandra only on this machine.

# datastax repo credentials
repo_username=""
repo_password=""

##########################################################################
# DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING
# FOR BUGS, PLEASE NOTIFY SUPPORT@GAZZANG.COM
##########################################################################

# WARNING, please use IPs for all fields below
# each node in the cluster
number_of_nodes=
node_ips=( )

# seed nodes
seed_ips=( )

# snitch to use (specified in /etc/dse/dse.yaml) -- TODO this is not functional yet
endpoint_snitch_type="com.datastax.bdp.snitch.DseSimpleSnitch"

# whether or not to run the packaged stress testing utility
run_performance="false"

# binary or packaged, packaged is straight from the DSE repositories (newest version) -- TODO not functional yet
install_type="packaged"

# log files
stdout_log="./cassandra_install_$(date +%Y%m%d_%H%M%S).out"
stderr_log="./cassandra_install_$(date +%Y%m%d_%H%M%S).out"

debug="true"

####
## Global Variables (script-use only, do not modify)
####

# string to declare operating system (ie rhel, oracle, ubuntu, debian, etc.)
declare os
# version only applies to rhel/centos-based systems (ie 5, 6)
declare os_version
declare this_node

####
## Utilities (pretty printing, error reporting, etc.)
####

function print_banner {
    color="34m"
    company_color="32m"
    echo -e "\x1b[$color
    ____                              _             ___           _        _ _ 
   / ___|__ _ ___ ___  __ _ _ __   __| |_ __ __ _  |_ _|_ __  ___| |_ __ _| | |
  | |   / _\` / __/ __|/ _\` | '_ \\ / _\` | '__/ _\` |  | || '_ \\/ __| __/ _\` | | |
  | |__| (_| \\__ \\__ \\ (_| | | | | (_| | | | (_| |  | || | | \\__ \\ || (_| | | |
   \\____\\__,_|___/___/\\__,_|_| |_|\\__,_|_|  \\__,_| |___|_| |_|___/\\__\\__,_|_|_|\x1b[0m"
    echo -e "\n* Logging enabled, check '\x1b[36m$stdout_log\x1b[0m' and '\x1b[36m$stderr_log\x1b[0m' for respective output.\n"
}

function print_error {
    printf "$(date +%s) \x1b[31m:: ERROR :: \x1b[0m$@\n"
}

function print_warning {
    printf "$(date +%s) \x1b[33m:: WARNING :: \x1b[0m$@\n"
}

function print_info {
    printf "$(date +%s) \x1b[32m:: INFO :: \x1b[0m$@\n"
}

function execute {
    local full_redirect="1>>$stdout_log 2>>$stderr_log"
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

function check_for_aws {
    if [[ ${#node_ips[@]} -eq 0 ]]; then
        print_info "No node IPs specified. Assuming single-node installation."
        return
    fi
    # Note: this trick requires AWS instances
    #me="$(wget -q -O - http://169.254.169.254/latest/meta-data/public-hostname)"
    #me="$(wget -q -O - http://169.254.169.254/latest/meta-data/local-ipv4)"
    count=0
    for ip in ${node_ips[@]}; do
        execute "ifconfig | grep $ip"
        if [[ $? -eq 0 ]]; then
            me="$ip"
            this_node=$count
            print_info "This servers IP address: ${node_ips[$this_node]}"
            print_info "This is node: $this_node"
            break
        fi
        let count+=1
    done
    unset count
    if [[ -z $this_node ]]; then
        print_error "Could not find node number. Please check configuration."
        exit 1
    fi
}

function get_system_parameters {
    check_for_root
    check_for_aws
    print_info "Collecting system configuration..."
    if [[ -f /etc/redhat-release ]]; then
        if [[ -f /etc/oracle-release ]]; then
            os="oracle"
        else
            os="redhat"
            execute "cat /etc/redhat-release | grep 5\.."
            if [[ $? -eq 0 ]]; then 
                os_version=5
            fi
            execute "cat /etc/redhat-release | grep 6\.."
            if [ $? -eq 0 ]; then
                os_version=6
            fi
        fi 
    elif [[ -f /etc/lsb-release ]]; then
        print_error "Sorry, this version of Linux is not yet supported."
        exit 1
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
    package_manager="yum"
    check_prereqs
}

function install_java {
    # TODO - make this not hard-coded
    print_info "Downloading java packages..."

    # NOTE: By using the Oracle JDK packages, you agree to their license agreement
    # See here: http://www.oracle.com/technetwork/java/javase/terms/license/index.html
    execute "wget https://s3.amazonaws.com/gazzang-implementation/jdk-6u45-linux-x64-rpm.bin"
    execute "chmod +x jdk-6u45-linux-x64-rpm.bin"
    print_info "Unpacking binaries..."
    execute "./jdk-6u45-linux-x64-rpm.bin"
    execute "rm -f jdk-6u45-linux-x64-rpm.bin"
    execute "test -x /usr/java/jdk1.6.0_45/jre/bin/java"
    if [[ $? -ne 0 ]]; then
        print_error "Java installation not successful. Stopping."
        exit 1
    fi
    print_info "Setting up alternatives..."
    execute "alternatives --install /usr/bin/java java /usr/java/jdk1.6.0_45/jre/bin/java 30000"
}

function check_prereqs {
    print_info "Checking for prerequisites..."
    execute "which wget"
    if [[ $? -ne 0 ]]; then
        print_info "Installing wget..."
        execute "yum install wget -y"
    fi
    execute "which java"
    if [[ $? -eq 0 ]]; then
        execute "java -version 2>&1 | grep -i \"openjdk\""
        if [[ $? -eq 0 ]]; then
            # only openjdk, need oracle
            install_java
        fi
    else
        install_java
    fi
}

function add_repo {
    case "$package_manager" in
        yum )
        print_info "Adding DSE repository to yum configuration..."
	if [ -z $repo_username ]; then
		print_error "No DSE repo credentials specified. Please add credentials before continuing."
		exit 1
	fi
        if [ ! -f /etc/yum.repos.d/dse.repo ]; then
            cat <<EOF > /etc/yum.repos.d/dse.repo
[datastax]
name= DataStax Repo for Apache Cassandra
baseurl=http://$repo_username:$repo_password@rpm.datastax.com/enterprise
enabled=1
gpgcheck=0
EOF
            execute "test -f /etc/yum.repos.d/dse.repo"
            if [ $? -ne 0 ]; then
                print_warning "Could not add Datastax repository file. Installation might not succeed."
            fi
        fi
        ;;
        * )
        print_error "Sorry, this package manager is not supported yet."
        exit 1
        ;;
    esac
}

function stop_selinux {
    if [[ -f /etc/selinux/config ]]; then
        print_info "Disabling selinux..."
        execute "sed -i.old s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config"
    fi
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

function stop_iptables {
    print_info "Disabling the firewall..."
    execute "service iptables stop"
}

function binary_install {
    # Not recommended
    print_info "Downloading Cassandra packages..."
    execute "wget http://www.gtlib.gatech.edu/pub/apache/cassandra/1.1.12/apache-cassandra-1.1.12-src.tar.gz -O ~/cassandra.tgz"
    print_info "Unpacking..."
    execute "tar xvzf ~/cassandra.tgz -C ~/"
}

function packaged_install {
    print_info "Installing Cassandra packages..."
    ### WARNING, HACK (DSE requires JNA to be installed, which is not available through the Amazon repositories)
    #latest_version="$(yum list | awk '/dse-libcassandra/ { print $2 }')"
    # The real latest version 4.0.1-1 (as of April 1st, 2014) is incompatible, pegging to 3.2.5-1 until updates are made
    latest_version="3.2.5-1"
    execute "curl -O http://rpm.datastax.com/enterprise/noarch/dse-libcassandra-$latest_version.noarch.rpm -u $repo_username:$repo_password"
    execute "rpm -ivh --nodeps dse-libcassandra-$latest_version.noarch.rpm"
    execute "rm -f dse-libcassandra-$latest_version.noarch.rpm"
    ### END HACK, PLEASE RESUME BUSINESS AS NORMAL
    print_info "Installing DSE packages..."
    execute "yum install dse-full-$latest_version -y"
    
    print_info "Installing JNA..."
    execute "wget https://maven.java.net/content/repositories/releases/net/java/dev/jna/jna/4.0.0/jna-4.0.0.jar"
    execute "mv jna-4.0.0.jar /usr/share/dse/cassandra/lib/"
    execute "wget https://maven.java.net/content/repositories/releases/net/java/dev/jna/jna-platform/4.0.0/jna-platform-4.0.0.jar"
    execute "mv jna-platform-4.0.0.jar /usr/share/dse/cassandra/lib/"
}

function install {
    get_system_parameters
    add_repo
    add_epel
    stop_selinux
    stop_iptables
    if [[ $install_type = "packaged" ]]; then
        execute "which dse"
        if [[ $? -ne 0 ]]; then
            packaged_install
        else
            print_info "DSE already installed. Skipping installation step."
        fi
    else
        binary_install
    fi
}

function disable_swap {
    print_info "Disabling system swap..."
    execute "swapoff --all"
}

function configure_limits {
    print_info "Setting system security limits.conf file for Datastax's recommended settings..."
    execute "test -f /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        print_warning "Could not find limits.conf file. Skipping..."
        return 1
    fi
    execute "grep \"^\*.*soft.*nofile.*32768$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"*   soft    nofile  32768\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^\*.*hard.*nofile.*32768$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"*   hard    nofile  32768\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^root.*soft.*nofile.*32768$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"root    soft    nofile  32768\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^root.*hard.*nofile.*32768$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"root    hard    nofile  32768\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^\*.*soft.*memlock.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"*   soft    memlock unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^\*.*hard.*memlock.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"*   hard    memlock unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^root.*soft.*memlock.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"root    soft    memlock unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^root.*hard.*memlock.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"root    hard    memlock unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^\*.*soft.*as.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"*   soft    as  unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^\*.*hard.*as.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"*   hard    as  unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^root.*soft.*as.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"root    soft    as  unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "grep \"^root.*hard.*as.*unlimited$\" /etc/security/limits.conf"
    if [[ $? -ne 0 ]]; then
        execute "echo \"root    hard    as  unlimited\" | tee -a /etc/security/limits.conf"
    fi
    execute "sed -i.before_cassandra_install 's/^\*.*soft.*nproc.*1024$/*\tsoft\tnproc\t10240/' /etc/security/limits.d/90-nproc.conf"
    print_info "Modifying system maximum map count to 131072..."
    execute "sysctl -w vm.max_map_count=131072"
}

function calculate_token {
    print_info "Calculating this nodes token..."
    if [[ -z $this_node ]]; then
        print_error "Could not determine which node this is. Skipping token generation..."
        return
    fi
    execute "which bc"
    if [[ $? -ne 0 ]]; then
        print_error "Cannot generate token, no suitable calculator found."
        return 1
    fi
    my_token=$(printf "$this_node*(2^127)/$number_of_nodes\n" | bc)
    print_info "This nodes token: $my_token"
}

function set_token {
    if [[ ${#node_ips[@]} -eq 0 ]]; then
        print_info "No node IP's specified. Assuming single-node setup."
        return
    fi
    calculate_token
    if [[ -z "$my_token" ]]; then
        print_error "Token was not generated! Could not set this nodes token..."
        return 1
    fi
    print_info "Setting this nodes token..."
    #execute "cat /etc/dse/cassandra/cassandra.yaml"
    execute "sed -i.before_token_change 's/initial_token:.*/initial_token:/' /etc/dse/cassandra/cassandra.yaml"
    execute "sed -i.before_token_change 's/^#.*num_tokens:.*$/num_tokens: 256/' /etc/dse/cassandra/cassandra.yaml"
}

function is_seed {
    for i in ${seed_ips[@]}; do
        if [ "$i" = "${node_ips[$this_node]}" ]; then
            return 0
        fi
    done
    return 1
    
    if [[ $this_node -eq 0 ]]; then
        # 0 by default will be a seed node
        return 0
    fi
    local num_seeds=${#seed_ips[@]}
    local diff=$(($num_seeds / ${#node_ips[@]}))
    local x=$(($this_node % $diff))
    if [[ $x -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

function set_seeds {
    if [[ ${#seed_ips[@]} -eq 0 ]]; then
        print_info "No seeds specified. Skipping cluster configuration..."
        return
    fi
    local combined=""
    # check if this node is a seed
    is_seed
    if [[ $? -eq 0 ]]; then
        # if this node is a seed, make it the first in the list
        combined="${node_ips[$this_node]}"
    fi
    for ip in ${seed_ips[@]}; do
        # check to see if we're already on the list
        execute "echo $ip | grep \"${node_ips[$this_node]}\""
        if [[ $? -ne 0 ]]; then
            if [[ -z $combined ]]; then
                combined="$ip"
            else
                combined="$combined,$ip"
            fi
        fi
    done
    print_info "Checking seed configuration..."
    execute "grep \"- seeds: \"$combined\"\" /etc/dse/cassandra/cassandra.yaml"
    if [[ $? -ne 0 ]]; then
        print_info "Updating seed info to reflect seeds: $combined"
        execute "sed -i.before_seed_change 's/-.*seeds:.*$/- seeds: \"$combined\"/' /etc/dse/cassandra/cassandra.yaml"
    else
        print_info "No modification to seed configuration necessary..."
    fi
}

function set_listen_address {
    execute "grep 'listen_address:.*$me' /etc/dse/cassandra/cassandra.yaml"
    if [[ $? -ne 0 ]]; then
        print_info "Setting Cassandra's listen_address to: $me"
        execute "sed -i.changed_listen_address 's/^listen_address:.*$/listen_address: $me/' /etc/dse/cassandra/cassandra.yaml"
    fi
}

function set_rpc_address {
    execute "grep 'rpc_address:*${node_ips[$this_node]}' /etc/dse/cassandra/cassandra.yaml"
    if [[ $? -ne 0 ]]; then
        print_info "Setting Cassandra's rcp_address to: ${node_ips[$this_node]}"
        execute "sed -i.changed_rcp_address 's/^rpc_address:.*$/rpc_address: ${node_ips[$this_node]}/' /etc/dse/cassandra/cassandra.yaml"
    fi
}

function configure {
    # implement DSE recommended configurations: http://www.datastax.com/docs/1.1/install/recommended_settings
    print_info "Making the necessary configuration changes..."
    execute "sudo mkdir -p /var/log/cassandra"
    execute "sudo chown -R cassandra:cassandra /var/log/cassandra"
    execute "sudo mkdir -p /var/lib/cassandra"
    execute "sudo chown -R cassandra:cassandra /var/lib/cassandra"
    disable_swap
    configure_limits
    set_token
    set_seeds
    set_listen_address
    set_rpc_address
    # TODO - ensure clocks are synchronized
    # TODO - check for raid
}

function start_cassandra {
    print_info "Checking Cassandra status..."
    if [[ $install_type = "packaged" ]]; then
        execute "service dse status"
        if [[ $? -ne 0 ]]; then
            print_info "Starting the Cassandra service..."
            execute "service dse start"
            sleep 10
            execute "service dse status"
            if [[ $? -ne 0 ]]; then
                print_error "Cassandra won't start. Please check logs and configuration."
                exit 1
            fi
        else
            print_info "Cassandra already running."
        fi
    else
        execute "~/apache-cassandra*/bin/cassandra -p /var/run/cassandra.pid &"
        execute "test -f /var/run/cassandra.pid"
        if [[ $? -ne 0 ]]; then
            print_error "Cassandra won't start. Please check logs and configuration."
            exit 1
        fi
    fi
}

function run_performance {
    if [[ $run_performance = "false" ]]; then
        print_info "Skipping performance tests..."
        return 0
    fi
    print_info "Performance tests commencing..."
    execute "which cassandra-stress"
    if [[ $? -ne 0 ]]; then
        print_error "Could not find cassandra-stress binary. Stopping."
        exit 1
    fi
    for test_num in $(seq 1 3); do 
        print_info "Starting performance test number: $test_num / 5"
        #execute "cassandra-stress -o insert -n 100 -i 1 -e ONE -c 100000000 -d localhost -t 150 -f ~/$(date +%s)_cassandra_test_$test_num.csv"
        execute "cassandra-stress -o insert -e ONE -c 1000 -d localhost -f ./$(date +%m%d%Y%H%M%S)_cassandra_test_$test_num.csv"
        #execute "service dse stop"
        #sleep 10
        #execute "service dse start"
        #sleep 5
        #execute "service dse status"
        #if [[ $? -ne 0 ]]; then
        #    print_warning "DSE would not start again."
        #fi
    done
}

function main {
    print_banner
    install
    configure
    start_cassandra
    run_performance
    print_info "Stopping."
}

main
