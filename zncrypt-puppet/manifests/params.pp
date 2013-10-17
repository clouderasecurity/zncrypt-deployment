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
    $keyserver          = ""
    $activation_email   = ""
    $passphrase         = ""
    $passphrase2        = ""
    $zncrypt_prefix     = "/var/lib/zncrypt"
    $zncrypt_mount      = "${zncrypt_mount}/mnt"
    $zncrypt_storage    = "${zncrypt_mount}/storage"
    $gazzang_baseurl    = "http://archive.gazzang.com"
    $gazzang_gpgkey     = "$gazzang_gpgkey/gpg_gazzang.asc"

    case $::osfamily {
        'RedHat':   { class { "zncrypt::repo::redhat": } }
        'Debian':   { class { "zncrypt::repo::debian": } }
        'Suse':     { class { "zncrypt::repo::suse": } }
        default:    { fail("Unsupport osfamily: $::::osfamily") }
    }
}
