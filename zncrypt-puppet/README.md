Description
===========

This is a puppet module that will install and configure Gazzang's zNcrypt encryption utility.

Requirements
============

Platform
--------

* Debian, Ubuntu
* CentOS, Red Hat, Fedora

Tested on:

* Ubuntu 10.04, 12.04
* CentOS 6.4, RHEL 6.4

Puppet Module Dependencies
--------------------------

* apt

Connectivity
------------

An internet connection is required.

Usage
=====

There are a couple of parameters that need to be changed prior to running these scripts:

zTrustee Registration/Activation Options
----------------------------------------

$keyserver = ""

This will be the zTrustee Key Management server that the zNcrypt client will attempt to register with.

$activation_email = ""

This is the email address that the client will use to register against the keyserver above. This email address must be preregistered as an 'organization administrator' on the keyserver prior to installation. 

zNcrypt Configuration Options
-----------------------------

$passphrase = ""

$passphrase2 = ""

These will be the passphrases used to control access to the encrypted data. These passwords are hard-coded for testing purposes, but should be changed and randomized per machine for production environments.

$zncrypt_prefix = "/var/lib/zncrypt"

$zncrypt_mount = "/var/lib/zncrypt/mnt"

$zncrypt_storage = "/var/lib/zncrypt/storage"

These are the directories that will hold the zNcrypt encrypted file system. Because puppet does not have an equivalent path creation tool, each directory must be created explicitly.

License and Author
==================

Author:: Ross McDonald (<ross.mcdonald@gazzang.com>)

Copyright:: 2013 Gazzang, Inc

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Special Thanks
==============

- Darin Perusich (deadpoint)

