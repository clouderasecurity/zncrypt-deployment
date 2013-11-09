class zncrypt::repo::suse {
    #
    include zncrypt::params
    #
    case $::operatingsystem {
        "opensuse": { 
            $repo_name = "opensuse"
            $kernel_packages  = [ "linux-glibc-devel", "kernel-devel" ]
         }
        "sles":     {
            $repo_name = "sles"
            $kernel_packages  = [ "linux-kernel-headers", "kernel-default-devel" ]
        }
        default:    { fail("Unsupport operatingsystem: $::operatingsystem") }
    }
    #
    zypprepo { "gazzang":
        baseurl     => "$zncrypt::params::gazzang_baseurl/$repo_name/stable/$::lsbdistrelease",
        enabled     => 1,
        gpgcheck    => 1,
        gpgkey      => "$zncrypt::params::gazzang_gpgkey",
    }
    # kernel packages
    package { $kernel_packages:
        ensure  => installed,
        require => Zypprepo[ "gazzang" ]
    }
    #
    package { [ "dkms", "zncrypt" ]:
        ensure  => installed,
        require => Zypprepo[ "gazzang" ]
    }
}
