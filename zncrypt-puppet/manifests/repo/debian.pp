class zncrypt::repo::debian {
    include apt
    apt::key { "gazzang":
        ensure => present,
        key_source => 'http://archive.gazzang.com/gpg_gazzang.asc',
    }
    apt::source { "gazzang":
        location    => "http://archive.gazzang.com/ubuntu/stable",
        release     => $lsbdistcodenamestable,
        key_source  => 'http://archive.gazzang.com/gpg_gazzang.asc',
        include_src => false,
    }
    # Ensure apt is setup before running apt-get update
    Apt::Key    <| |> -> Exec["apt-update"]
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
