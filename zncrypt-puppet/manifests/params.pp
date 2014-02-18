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
    $zncrypt_prefix     = "/var/lib/zncrypt"
    $zncrypt_mount      = "${zncrypt_prefix}/mnt"
    $zncrypt_storage    = "${zncrypt_prefix}/storage"
    $gazzang_baseurl    = "http://archive.gazzang.com"
    $gazzang_gpgkey     = "$gazzang_baseurl/gpg_gazzang.asc"

    case $::osfamily {
        'RedHat':   { class { "zncrypt::repo::redhat": } }
        'Debian':   { class { "zncrypt::repo::debian": } }
        'Suse':     { class { "zncrypt::repo::suse": } }
        default:    { fail("Unsupport osfamily: $::::osfamily") }
    }
}
