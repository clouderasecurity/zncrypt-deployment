# Class zncrypt::params
#
# The zncrypt configuration settings.
#
# Parameters:
#
# Actions:
#
# Requires:
#
# Sample Usage:
#
class zncrypt::params {
    $keyserver
    $activation_email
    $passphrase
    $passphrase2
    $zncrypt_prefix     = "/var/lib/zncrypt"
    $zncrypt_mount      = "${zncrypt_mount}/mnt"
    $zncrypt_storage    = "${zncrypt_mount}/storage"

    case $::osfamily
    {
        'RedHat': {
            yumrepo { "epel":
                descr => 'EPEL',
                mirrorlist => 'http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$releasever&arch=$basearch',
                enabled => 1,
                gpgcheck => 1,
                gpgkey => "https://fedoraproject.org/static/0608B895.txt";
            }
            yumrepo { "gazzang":
                descr  => 'Gazzang',
                baseurl => 'http://archive.gazzang.com/redhat/stable/$releasever',
                enabled => 1,
                gpgcheck => 1,
                gpgkey => "http://archive.gazzang.com/gpg_gazzang.asc",
            }
            package { ["kernel-devel","kernel-headers","dkms","zncrypt"]:
                ensure => present,
                require => Yumrepo[ "epel", "gazzang" ]
            }
        }
        'Debian': {
            include apt
            apt::key { "gazzang":
                ensure => present,
                key_source => 'http://archive.gazzang.com/gpg_gazzang.asc',
            }
            apt::source { "gazzang":
                location        => "http://archive.gazzang.com/ubuntu/stable",
                release         => $lsbdistcodenamestable,
                key_source      => 'http://archive.gazzang.com/gpg_gazzang.asc',
                include_src     => false,
            }

            # Ensure apt is setup before running apt-get update
            Apt::Key <| |> -> Exec["apt-update"]
            Apt::Source <| |> -> Exec["apt-update"]

            # Ensure apt-get update has been run before installing any packages
            Exec["apt-update"] -> Package <| |>

            exec { "apt-update":
                command     => "/usr/bin/apt-get update",
                refreshonly => true,
            }
            package { ["linux-headers-$kernelrelease","dkms","zncrypt"]:
                ensure => latest,
            }
        }
        'Suse': {
            zypprepo { "gazzang":
                baseurl     => "http://archive.gazzang.com/$::operatingsystem/stable",
                enabled     => 1,
                gpgcheck    => 1,
                gpgkey      => "http://archive.gazzang.com/gpg_gazzang.asc",
            }
        }
    }
}
