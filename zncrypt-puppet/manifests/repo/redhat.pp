class zncrypt::repo::redhat {
    yumrepo { "epel":
        descr       => 'EPEL',
        mirrorlist  => 'http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$releasever&arch=$basearch',
        enabled     => 1,
        gpgcheck    => 1,
        gpgkey      => "https://fedoraproject.org/static/0608B895.txt";
    }
    yumrepo { "gazzang":
        descr       => 'Gazzang',
        baseurl     => "$zncrypt::params::gazzang_baseurl/redhat/stable/$releasever",
        enabled     => 1,
        gpgcheck    => 1,
        gpgkey      => "$zncrypt::params::gazzang_gpgkey",
    }
    package { ["kernel-devel","kernel-headers","dkms","zncrypt"]:
        ensure  => present,
        require => Yumrepo[ "epel", "gazzang" ]
    }
}
