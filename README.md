zNcrypt Bash Deployment Scripts
==========================

Bash scripts built to enhance Gazzang zNcrypt deployments. Currently, there are two steps involved:
* Install zNcrypt (`zncrypt-install.sh`) - automated
* Configure zNcrypt (`zncrypt-configure.sh`) - interactive from `/dev/tty`

Please note that these scripts are meant for testing purposes only, and come with absolutely no warranty whatsoever.

Install
-------

Simply copy the following command into a Linux terminal to get started:
```
curl -sL https://raw.github.com/gazzang/zncrypt-deployment/master/zncrypt-install.sh | sudo bash
```

![zncrypt-deploy](https://s3.amazonaws.com/gazzang-implementation/zncrypt-install-run.gif)

This will attempt to install zNcrypt based on your current environment. This script can be run multiple times without issue.

Configurating
-------------

Once zNcrypt is installed, copy the following command into a Linux terminal to configure:

```
curl -sL https://raw.github.com/gazzang/zncrypt-deployment/master/zncrypt-configure.sh | sudo bash
```

![zncrypt-configure](https://s3.amazonaws.com/gazzang-implementation/zncrypt-configure-run.gif)

Which will run through an interactive console to register and configure zNcrypt. This script can also be run multiple times without issue.

