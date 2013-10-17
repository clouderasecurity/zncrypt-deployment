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
        baseurl     => 'http://archive.gazzang.com/redhat/stable/$releasever',
        enabled     => 1,
        gpgcheck    => 1,
        gpgkey      => "http://archive.gazzang.com/gpg_gazzang.asc",
    }
    package { ["kernel-devel","kernel-headers","dkms","zncrypt"]:
        ensure  => present,
        require => Yumrepo[ "epel", "gazzang" ]
    }
}
