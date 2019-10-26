# inteldevstack_ubuntu1804
Patches to install Intel OPAE development package on Ubuntu 18.04

The Intel® Acceleration Stack Version 1.2 is validated on RHEL 7.4, CentOS 7.4 and Ubuntu 16.04.
However, to install it on Ubuntu 18.04, some old packages on Ubuntu 16.04 should be installed manually.


First inistall the two libjson packages that are missing in Ubuntu 18.04:

  sudo dpkg -i libjson-c2_0.11-4ubuntu2_amd64.deb
  
  sudo dpkg -i libjson0_0.11-4ubuntu2_amd64.deb


Then modify the setup.sh script to install two php packages with version 7.2 instead of version 7.0:

  cmd="sudo -E apt-get -f install dkms libjson0 uuid-dev php7.0-dev php7.0-cli libjson-c-dev libhwloc-dev python-pip libjson-c-dev libhwloc-dev"

  cmd="sudo -E apt-get -f install dkms uuid-dev php7.2-dev php7.2-cli libjson-c-dev libhwloc-dev python-pip libjson-c-dev libhwloc-dev"


Reference:

https://www.intel.com/content/www/us/en/programmable/products/boards_and_kits/dev-kits/altera/acceleration-card-arria-10-gx/getting-started.html

https://packages.ubuntu.com/search?keywords=libjson0&searchon=names

https://packages.ubuntu.com/search?keywords=libjson-c2&searchon=names

https://packages.ubuntu.com/search?keywords=php7.0-dev&searchon=names

https://packages.ubuntu.com/search?keywords=php7.0-cli&searchon=names
