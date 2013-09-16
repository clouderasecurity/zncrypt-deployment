class zncrypt {

    ###############################################################
    # Hard-coded values
    #
    # IMPORTANT: Do NOT leave the passphrase and/or passphrase2 in
    #   this script!  We recommend generating a strong random
    #   passphrase or alternatively using an RSA key
    ###############################################################

    # zTrustee Key Server to register against
    $keyserver = ""
    # Email address to use for activation request
    $activation_email = ""
    
    # Example master passphrases
    $passphrase = ""
    $passphrase2 = ""
    
    # zNcrypt directories that are required for operation
    $zncrypt_prefix = "/var/lib/zncrypt"
    # The mount-point for the encrypted file system
    $zncrypt_mount = "/var/lib/zncrypt/mnt"
    # The location where the encrypted file system will be stored
    $zncrypt_storage = "/var/lib/zncrypt/storage"

    ###############################################################
    # Set variables or execute commands that depend on the OS
    ###############################################################

    case $::operatingsystem 
    {
        'CentOS': 
        {
            yumrepo 
            { 
                "epel":
                descr => 'EPEL',
                mirrorlist => 'http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$releasever&arch=$basearch',
                enabled => 1,
                gpgcheck => 1,
                gpgkey => "https://fedoraproject.org/static/0608B895.txt";
                "gazzang":
                descr  => 'Gazzang',
                baseurl => 'http://archive.gazzang.com/redhat/stable/$releasever',
                enabled => 1,
                gpgcheck => 1,
                gpgkey => "http://archive.gazzang.com/gpg_gazzang.asc",
            }
            package 
            { 
                ["kernel-devel","kernel-headers","dkms","zncrypt"]:
                ensure => present,
                require => Yumrepo[ "epel", "gazzang" ]
            }
        }
        'Ubuntu': 
        {
            include apt
            apt::key 
            { 
                "gazzang":
                ensure => present,
                key_source => 'http://archive.gazzang.com/gpg_gazzang.asc',
            }
            apt::source 
            { 
                "gazzang":
                location      	=> "http://archive.gazzang.com/ubuntu/stable",
                release       	=> $lsbdistcodenamestable,
                key_source    	=> 'http://archive.gazzang.com/gpg_gazzang.asc',
                include_src   	=> false,
            }

            # Ensure apt is setup before running apt-get update
            Apt::Key <| |> -> Exec["apt-update"]
            Apt::Source <| |> -> Exec["apt-update"]

            # Ensure apt-get update has been run before installing any packages
            Exec["apt-update"] -> Package <| |>

            exec { "apt-update":
                command 	=> "/usr/bin/apt-get update",
                refreshonly => true,
            }
            package { 
                ["linux-headers-$kernelrelease","dkms","zncrypt"]:
                ensure => latest,
            }
        }
    }

    # Create necessary directories
    file { [$zncrypt_prefix, $zncrypt_mount, $zncrypt_storage]:
        ensure => "directory",
        owner => "root",  
    }

    ###############################################################
    # Execute the steps to configure, activate, and start zNcrypt
    ###############################################################

    exec {
        "zncrypt_register":
        command => "printf '$passphrase\n$passphrase\n$passphrase2\n$passphrase2' | zncrypt register --server=$keyserver --key-type=dual-passphrase --clientname=$(hostname)",
        creates => "/etc/zncrypt/ztrustee/clientname",
        path => "/usr/bin:/usr/sbin:/bin",
    }

    exec {
        "zncrypt_activate":
        command => "zncrypt request-activation -c $activation_email",
        require => Exec["zncrypt_register"],
        before => Exec["zncrypt_prepare"],
        path => "/usr/bin:/usr/sbin:/bin",
    }

    exec { 
        "zncrypt_prepare":
        command => "printf '$passphrase\n$passphrase2' | zncrypt-prepare $zncrypt_storage $zncrypt_mount",
        onlyif => ["test -d $zncrypt_storage", "test -d $zncrypt_mount"],
        path => "/usr/bin:/usr/sbin:/bin",
    }
}
