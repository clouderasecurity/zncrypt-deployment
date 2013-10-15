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
}
