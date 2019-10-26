#!/usr/bin/env bash

# Intel Acceleration Stack installer

# Copyright (C) 2018 Intel Corporation. All rights reserved.

# Your use of Intel Corporation's design tools, logic functions and other
# software and tools, and its AMPP partner logic functions, and any output files
# any of the foregoing (including device programming or simulation files), and
# any associated documentation or information are expressly subject to the terms
# and conditions of the Intel Program License Subscription Agreement, Intel
# MegaCore Function License Agreement, or other applicable license agreement,
# including, without limitation, that your use is for the sole purpose of
# programming logic devices manufactured by Intel and sold by Intel or its
# authorized distributors.  Please refer to the applicable agreement for
# further details.

################################################################################
# Global variables
################################################################################
PKG_TYPE="dev"

if [ "$PKG_TYPE" = "dev" ] ;then
    PRODUCT_NAME="Intel Acceleration Stack Development Package"
    PRODUCT_DIR="inteldevstack"
    
    QUARTUS_INSTALLER="QuartusProSetup-17.1.0.240-linux.run"
    QUARTUS_UPDATE="QuartusProSetup-17.1.1.273-linux.run"
    AOCL_INSTALLER="AOCLProSetup-17.1.1.273-linux.run"
    declare -a patches=("1.01dcp" "1.02dcp" "1.36" "1.38")

    qproduct="quartus"
    qproduct_env="QUARTUS_HOME"

    opencl="hld"
    opencl_dev_env="INTELFPGAOCLSDKROOT"

else
    PRODUCT_NAME="Intel Acceleration Stack Runtime Package"
    PRODUCT_DIR="intelrtestack"
    
    #QUARTUS_INSTALLER="QuartusProProgrammerSetup-17.1.1.273-linux.run"
    QUARTUS_UPDATE=""
    AOCL_INSTALLER="aocl-pro-rte-17.1.1.273-linux.run"
    declare -a patches=()

    qproduct="aclrte-linux64"
    qproduct_env="INTELFPGAOCLSDKROOT"

fi

prompt_opae=1
install_opae=1

DEFAULT_INSTALLDIR="$HOME/$PRODUCT_DIR"

DCP_INSTALLER="a10_gx_pac_ias_1_2_pv.tar.gz"

OPAE_VER="1.1.2-1"
DRIVER_VER="1.1.2-1"

SUPPORTED_CENTOS_VERSION="7.4"
SUPPORTED_CENTOS_KERNEL_VERSION="3.10"
SUPPORTED_UBUNTU_VERSION1="18.04"
SUPPORTED_UBUNTU_VERSION2="16.04"

################################################################################
# Parse command-line options
################################################################################

INSTALLDIR=''
DCP_LOC=''
YESTOALL=0
DRYRUN=0

POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        --installdir) # to specify the directory to install Quartus/OpenCL software
            INSTALLDIR="$2"
            shift # past argument
            shift # past value
            ;;
        --dcp_loc) # to specify the directory to install Intel Acceleration Stack, default is same as the installdir
            DCP_LOC="$2"
            shift # past argument
            shift # past value
            ;;
         --yes) # default to yes for all the prompts
            YESTOALL=1
            shift # past argument
            ;;
         --dryrun)
            DRYRUN=1 # dry run - without actually executing the commands
            shift # past argument
            ;;
        *)    # unknown option
            POSITIONAL+=("$1") # save it in an array for later
            shift # past argument
            ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


################################################################################
# Functions to support try/catch exceptions
################################################################################

function try()
{
    [[ $- = *e* ]]; SAVED_OPT_E=$?
    set +e
}

function throw()
{
    exit $1
}

function catch()
{
    export ex_code=$?
    (( $SAVED_OPT_E )) && set +e
    return $ex_code
}

function throwErrors()
{
    set -e
}

function ignoreErrors()
{
    set +e
}
################################################################################
# End - Functions to support try/catch exceptions
################################################################################


################################################################################
# Common Functions
################################################################################

comment()
{
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "- $1"
    echo "-------------------------------------------------------------------------------"
}

run_command()
{
    cmd="$1"
    raise_error=${2:-1}
    echo ">>> Running cmd:"
    echo "      $cmd"
    echo ""
    try
    (
        if [ $DRYRUN -eq 1 ] ;then
            echo "dryrun -- skip"
        else
            eval exec "$cmd"
        fi

        echo ""
    )
    catch || {
        case $ex_code in
            *)
                echo "Command: \"$cmd\" exited with error code: $ex_code"
                echo ""
                if [ $raise_error -eq 1 ] ;then
                    throw $ex_code
                fi
                ;;
        esac
    }
}

yum_isinstalled()
{
  if sudo yum list installed "$@" >/dev/null 2>&1; then
    true
  else
    false
  fi
}

run_yum_command()
{
    operation=$1
    cmd=$2
    yum_cmd="sudo yum -y $operation $cmd"
    run_command "$yum_cmd"
}

do_yum_remove()
{
    if yum_isinstalled "$1"; then
        echo "$1 installed, removing it"
        run_yum_command "remove" "$1"
    fi
}

do_yum_install()
{
    run_yum_command "install" "$1"
}

do_yum_install_with_remove()
{
    pkg="${1%.*}"
    pkg=$(echo $pkg | sed -e s/-$OPAE_VER//)
    do_yum_remove $pkg
    do_yum_install "$1"
}

################################################################################
# End - Common Functions
################################################################################

################################################################################
# OPAE RPM Install Function
################################################################################
install_prerequisite_package_for_centos()
{
    ################################################################################
    #Install the Extra Packages for Enterprise Linux (EPEL):
    # $ sudo yum install epel-release
    ################################################################################
    comment "Install the Extra Packages for Enterprise Linux (EPEL)"
    yum_install="epel-release"
    do_yum_install "$yum_install"

    ################################################################################
    # Before you can install and build the OPAE software, you must install the required 
    # packages by running the following command:
    # $ sudo yum install gcc gcc-c++ \
    #    cmake make autoconf automake libxml2 \ 
    #    libxml2-devel json-c-devel boost ncurses ncurses-devel \ 
    #    ncurses-libs boost-devel libuuid libuuid-devel python2-jsonschema \
    #    doxygen rsync hwloc-devel
    # Note: Some packages may already be installed. This command only installs the packages
    # that are missing.
    ################################################################################
    comment "Install Pre-requisite packages"
    yum_install="gcc gcc-c++ cmake make autoconf automake libxml2 libxml2-devel json-c-devel boost ncurses ncurses-devel ncurses-libs boost-devel libuuid libuuid-devel python2-jsonschema doxygen rsync hwloc-devel libpng12 python2-pip"
    do_yum_install "$yum_install"
	sudo pip install intelhex
}

install_prerequisite_package_for_ubuntu()
{
    comment "Install Pre-requisite packages"
    cmd="sudo -E apt-get -f install dkms uuid-dev php7.2-dev php7.2-cli libjson-c-dev libhwloc-dev python-pip libjson-c-dev libhwloc-dev"
    run_command "$cmd"
    sudo -E pip install intelhex
}

install_opae_rpm_package_for_centos()
{
    comment "Installing OPAE rpm packages for RedHat/CentOS ..."
    ################################################################################
    #Remove any previous version of the OPAE FPGA driver by running the command:
    # sudo yum remove opae-intel-fpga-drv.x86_64.
    ################################################################################
    comment "Remove any previous version of the OPAE FPGA driver"
    yum_install="opae-intel-fpga-drv.x86_64"
    do_yum_remove "$yum_install"
    
    yum_install="opae-intel-fpga-driver.x86_64"
    do_yum_remove "$yum_install"
    
    ################################################################################
    #Remove any previous version of the OPAE FPGA libraries by running the commands:
    # sudo yum remove opae-ase.x86_64 
    # sudo yum remove opae-tools.x86_64 
    # sudo yum remove opae-tools-extra.x86_64 
    # sudo yum remove opae-devel.x86_64 
    # sudo yum remove opae-libs.x86_64
    ################################################################################
    comment "Remove any previous version of the OPAE FPGA libraries"
    yum_install="opae-ase.x86_64"
    do_yum_remove "$yum_install"
    
    yum_install="opae-tools.x86_64"
    do_yum_remove "$yum_install"
    
    yum_install="opae-tools-extra.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae-devel.x86_64"
    do_yum_remove "$yum_install"
    
    yum_install="opae-libs.x86_64"
    do_yum_remove "$yum_install"
    
 
    ################################################################################
    #Install the Altera® FPGA kernel drivers:
    # $ cd $DCP_LOC/sw
    # $ sudo yum install $DCP_LOC/sw/opae-intel-fpga-driver-${DRIVER_VER}.x86_64.rpm
    ################################################################################
    cd $DCP_LOC/sw
    comment "Update kernel source"
    sudo yum install kernel-devel-`uname -r`
    comment "Update kernel headers"
    sudo yum install kernel-headers-`uname -r`
    comment "Install the Altera® FPGA kernel drivers"
    yum_install="opae-intel-fpga-driver-${DRIVER_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    
    ################################################################################
    #Check the Linux kernel installation:
    # lsmod | grep fpga
    #    Sample output:
    #    intel_fpga_fme         51462  0 
    #    intel_fpga_afu         31735  0 
    #    fpga_mgr_mod           14693  1 intel_fpga_fme
    #    intel_fpga_pci         25804  2 intel_fpga_afu,intel_fpga_fme
    ################################################################################
    comment "Check the Linux kernel installation"
    lsmod_cmd="lsmod | grep fpga"
    run_command "$lsmod_cmd" 0
    
    ################################################################################
    #Install the OPAE Software
    ################################################################################
    comment "installing OPAE software ..."
    
    ################################################################################
    #Complete the following steps to install the OPAE software:
    # 1. Install shared libraries at location /usr/lib, required for user applications to link against:
    #    sudo yum install opae-libs-${OPAE_VER}.x86_64.rpm
    # 2. Install the OPAE header at location /usr/include:
    #    sudo yum install opae-devel-${OPAE_VER}.x86_64.rpm
    # 3. Install the OPAE provided tools at location /usr/bin (For example: fpgaconf and fpgainfo):
    #    sudo yum install opae-tools-${OPAE_VER}.x86_64.rpm
    #    sudo yum install opae-tools-extra-${OPAE_VER}.x86_64.rpm
    #    For more information about tools, refer to the OPAE tools document.
    # 4. Install the ASE related shared libraries at location /usr/lib:
    #    sudo yum install opae-ase-${OPAE_VER}.x86_64.rpm
    # 5. Run ldconfig
    #    sudo ldconfig
    ################################################################################
    comment "1. Install shared libraries at location /usr/lib, required for user applications to link against"
    yum_install="opae-libs-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    
    comment "2. Install the OPAE header at location /usr/include"
    yum_install="opae-devel-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    
    comment "3. Install the OPAE provided tools at location /usr/bin (For example: fpgaconf and fpgainfo)"
    yum_install="opae-tools-extra-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    echo ""
    yum_install="opae-tools-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    
    comment "4. Install the ASE related shared libraries at location /usr/lib"
    yum_install="opae-ase-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    
    comment "5. sudo ldconfig"
    cmd="sudo ldconfig"
    run_command "$cmd" 0
}

install_opae_rpm_package_for_ubuntu()
{
    comment "Installing OPAE deb packages for Ubuntu ..."

    #1)	To remove any ubuntu deb packages installed
    comment "Remove any previous version of the OPAE FPGA libraries"
    cmd="sudo dpkg -r opae-intel-fpga-driver"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-ase"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-tools-extra"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-tools"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-devel"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-libs"
    run_command "$cmd"
    
    ################################################################################
    #Install the Altera® FPGA kernel drivers:
    # $ cd $DCP_LOC/sw
    # $ sudo dpkg -i opae-intel-fpga-driver-${DRIVER_VER}.x86_64.deb
    ################################################################################
    cd $DCP_LOC/sw
    
    #2)	Install OPAE FPGA driver
    comment "Install the Altera® FPGA kernel drivers"
    cmd="sudo dpkg -i opae-intel-fpga-driver-${DRIVER_VER}.x86_64.deb"
    run_command "$cmd"

    #3)	 Install OPAE Libraries
    comment "installing OPAE software ..."
    cmd="sudo dpkg -i opae-libs-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    cmd="sudo dpkg -i opae-devel-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    cmd="sudo dpkg -i opae-tools-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    cmd="sudo dpkg -i opae-tools-extra-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    cmd="sudo dpkg -i opae-ase-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"
}

install_quartus_dev_package()
{
    comment "Installing the Intel FPGA Quartus Prime Pro Edition Software"
    QINSTALLDIR="$INSTALLDIR/intelFPGA_pro"
    
    installer="$SCRIPT_PATH/$QUARTUS_INSTALLER"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --disable-components quartus_update --accept_eula 1"
    install_cmd="$installer $install_arg"
    run_command "$install_cmd"

    installer="$SCRIPT_PATH/$QUARTUS_UPDATE"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --skip_registration 1"
    install_cmd="$installer $install_arg"
    run_command "$install_cmd"

    ## loop through the array of patches
    for p in "${patches[@]}"
    do
        installer="$SCRIPT_PATH/quartus-17.1.1-${p}-linux.run"
        install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1 --skip_registration 1"
        install_cmd="$installer $install_arg"
        run_command "$install_cmd"
    done
    
    installer="$SCRIPT_PATH/$AOCL_INSTALLER"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1"
    install_cmd="$installer $install_arg"
    run_command "$install_cmd"
}


install_quartus_rte_package()
{
    comment "Installing the Intel FPGA RTE for OpenCL"
    QINSTALLDIR="$INSTALLDIR/opencl_rte"
    
    #installer="$SCRIPT_PATH/$QUARTUS_INSTALLER"
    #install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1"
    #install_cmd="$installer $install_arg"
    #run_command "$install_cmd"

    installer="$SCRIPT_PATH/$AOCL_INSTALLER"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1 --skip_registration 1"
    install_cmd="$installer $install_arg"
    run_command "$install_cmd"
}


################################################################################
# Main script starts
################################################################################

comment "Beginning installing $PRODUCT_NAME"

# Check if we are running on a supported version of Linux distribution
# Both RedHat and CentOS have the /etc/redhat-release file.
unsupported_os=1
unsupported_kernel=1
is_ubuntu=0
os_file="/etc/redhat-release"

# check for RedHat/CentOS
if [ -f $os_file ] ;then
    
	os_version=`cat $os_file | grep release | sed -e 's/ (.*//g'`
	os_platform=`echo ${os_version} | grep "Red Hat Enterprise" || echo ${os_version} | grep "CentOS"`
    
	if [ "$os_platform" != "" ] ;then
        os_rev=`echo ${os_platform} | awk -F "release " '{print $2}' | sed -e 's/ .*//g'`
        if [[ ${os_rev} = ${SUPPORTED_CENTOS_VERSION}* ]]; then
            unsupported_os=0
        fi
	fi
fi

kernal_ver=`uname -r`
if [[ ${kernal_ver} = ${SUPPORTED_CENTOS_KERNEL_VERSION}* ]] ;then
    unsupported_kernel=0
fi

if [[ $unsupported_os -eq 1 ]] ;then
  # check fo Ubuntu
  os_file="/etc/issue"

  if [ -f $os_file ] ;then
	os_version=`cat $os_file`
	os_platform=`echo ${os_version} | grep "Ubuntu"`
	os_version=`head -n 1 $os_file`

	if [ "$os_platform" != "" ] ;then
        os_rev=`echo ${os_platform} | awk -F "Ubuntu " '{print $2}' | sed -e 's/ .*//g'`
        if [[ ${os_rev} = ${SUPPORTED_UBUNTU_VERSION1}* ]] || [[ ${os_rev} = ${SUPPORTED_UBUNTU_VERSION2}* ]]; then
            unsupported_os=0
            unsupported_kernel=0
            is_ubuntu=1
        fi
	fi
  fi
fi


DEFAULT="y"

if [[ $unsupported_os -eq 1 ]] || [[ $unsupported_kernel -eq 1 ]] ;then
	echo ""
	echo "$PRODUCT_NAME is only supported on RedHat or CentOS ${SUPPORTED_CENTOS_VERSION}.* kernel ${SUPPORTED_CENTOS_KERNEL_VERSION}.* or Ubuntu ${SUPPORTED_UBUNTU_VERSION},"
	echo "you're currently on $os_version using kernel ${kernal_ver}."
	echo "Refer to the $PRODUCT_NAME Quick Start Guide,"
	echo "    https://www.altera.com/documentation/dnv1485190478614.html,"
	echo "for complete operating system support information."
	echo ""

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        read -e -p "Do you want to continue to install the software? (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
			exit
		fi
	done
fi

if [ `uname -m` != "x86_64" ] ;then
	echo ""
	echo "The Intel software you are installing is 64-bit software and will not work on the 32-bit platform on which it is being installed."
	echo ""

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        read -e -p "Do you want to continue to install the software? (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"
        
		if [ "$answer" = "n" ] ;then
			exit
		fi
	done
fi

if [ $prompt_opae -eq 1 ] ;then

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        echo ""
        read -e -p "Do you wish to install OPAE? Note: Installing will require administrative access (sudo) and network access. (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
            install_opae=0
            echo ""
            echo "*** Note: You can install OPAE software package manually by following the Quick Start Guide section: Installing the OPAE Software Package."
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            echo ""
			break
		fi
	done
fi

# get script path
SCRIPT_PATH=`dirname "$0"`
if test "$SCRIPT_PATH" = "." -o -z "$SCRIPT_PATH" ; then
	SCRIPT_PATH=`pwd`
fi
SCRIPT_PATH="$SCRIPT_PATH/components"

################################################################################
# show license agreement
################################################################################
more "$SCRIPT_PATH/../licenses/license.txt"

	answer="n"
    
	while [ "$answer" != "y" ]
	do
        read -e -p "Do you accept this license? (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
			exit
		fi
	done


################################################################################
# checking validation of INSTALLDIR    
################################################################################
is_valid=0

if [[ "$INSTALLDIR" = "" ]] && [ $YESTOALL -eq 1 ] ;then
    INSTALLDIR="$DEFAULT_INSTALLDIR"
    is_valid=1
fi

while [ $is_valid -eq 0 ]
do
    if [ "$INSTALLDIR" = "" ] ;then
        INSTALLDIR="$DEFAULT_INSTALLDIR"

        answer=""
        echo ""
        echo -n "Enter the path you want to extract the Intel PAC with Intel Arria10 GX FPGA release package [default: $INSTALLDIR]: "
	    read answer
        
	    if [ "$answer" != "" ] ;then
            INSTALLDIR=$answer
        fi
    fi

    if [ -f "$INSTALLDIR" ] ;then
	    echo "Error: $INSTALLDIR already exists as a file, you need to specify a directory path."
        INSTALLDIR=""
        YESTOALL=0
    else
        if [ -d "$INSTALLDIR" ] ;then
	        to_continue="n"
            if [ $YESTOALL -eq 1 ] ;then
	            to_continue="y"
                is_valid=1
            fi

	        while [ "$to_continue" != "y" ]
	        do
                read -e -p "Directory $INSTALLDIR already exists, do you want to continue to install to this location? (Choosing 'y' will remove all the existing files there) (Y/n): " to_continue
                to_continue="${to_continue:-${DEFAULT}}"
                to_continue="${to_continue,,}"
                
		        if [ "$to_continue" = "y" ] ;then
                    is_valid=1
                    break
		        fi
		        if [ "$to_continue" = "n" ] ;then
                    INSTALLDIR=""
                    break
		        fi
	        done
        else
            is_valid=1
        fi
    fi
done

#remove the trailing slash
INSTALLDIR="${INSTALLDIR%/}"

#add PRODUCT_DIR to INSTALLDIR if it is not there
if [[ "${INSTALLDIR}" != *"$PRODUCT_DIR"* ]] ;then
    INSTALLDIR="${INSTALLDIR}/$PRODUCT_DIR"
fi

if [ "$DCP_LOC" = "" ] ;then
    DCP_LOC="${INSTALLDIR}"
fi

echo ""
echo INSTALLDIR="${INSTALLDIR}"

# install the prerequisite packages first to see if user has sudo permission
if [ $install_opae -eq 1 ] ;then
    if [ $is_ubuntu -eq 1 ] ;then
        install_prerequisite_package_for_ubuntu
    else
        install_prerequisite_package_for_centos
    fi
fi

################################################################################
# unzip the DCP installer
################################################################################

if [ -d "$INSTALLDIR" ] ;then
    echo ""
    echo "Removing ${INSTALLDIR} ..."
    chmod -R +w "$INSTALLDIR"
    rm -rf "$INSTALLDIR"
fi

if [ ! -d "$INSTALLDIR" ] ;then
    mkdir -p "$INSTALLDIR"
fi

comment "Copying $DCP_INSTALLER to $INSTALLDIR"
cp_cmd="cp -pf $SCRIPT_PATH/$DCP_INSTALLER $INSTALLDIR"
run_command "$cp_cmd"

if [ "$DCP_LOC" != "" ] ;then
    
    #remove the trailing slash
    DCP_LOC="${DCP_LOC%/}"
    
    #always add package name to the path
    DCP_LOC="${DCP_LOC}/${DCP_INSTALLER/.*/}"
    
    if [ -d "$DCP_LOC" ] ;then
        rm -rf "$DCP_LOC"
    fi
    
    mkdir -p $DCP_LOC
    cd $DCP_LOC
    
    comment "Untar $DCP_INSTALLER"
    echo DCP_LOC="${DCP_LOC}"
    untar_cmd="tar -xzf $SCRIPT_PATH/$DCP_INSTALLER"
    run_command "$untar_cmd"

    untar_cmd="tar xf ${DCP_LOC}/opencl/opencl_bsp*.tar.gz -C ${DCP_LOC}/opencl/"
    run_command "$untar_cmd"

    comment "Copying $SCRIPT_PATH/setup_fim_and_bmc.sh to $DCP_LOC"
    cp_cmd="cp -pf $SCRIPT_PATH/setup_fim_and_bmc.sh $DCP_LOC"
    run_command "$cp_cmd"

    comment "Copying fpgaflash tool to $DCP_LOC/sw"
    cp_cmd="cp -pf $SCRIPT_PATH/fpgaflash $DCP_LOC/sw"
    run_command "$cp_cmd"

    comment "Copying afu_platform_info tool to $DCP_LOC/sw"
    cp_cmd="cp -pf $SCRIPT_PATH/afu_platform_info $DCP_LOC/sw"
    run_command "$cp_cmd" 
fi

################################################################################
#Installing the OPAE RPM packages
################################################################################
if [ $install_opae -eq 1 ] ;then
    if [ $is_ubuntu -eq 1 ] ;then
        install_opae_rpm_package_for_ubuntu
    else
        install_opae_rpm_package_for_centos
    fi
fi

################################################################################
#Installing the Intel FPGA Quartus Prime Pro Edition Software
################################################################################
if [ "$PKG_TYPE" = "dev" ] ;then
    install_quartus_dev_package
else
    install_quartus_rte_package
fi

################################################################################
#    Create env.sh to be sourced to setup the the environment
################################################################################

QENV="$INSTALLDIR/init_env.sh"
comment "Creating ${QENV}"

echo "" > "${QENV}"
echo "echo export ${qproduct_env}=\"${QINSTALLDIR}/${qproduct}\"" >> "${QENV}"
echo "export ${qproduct_env}=\"${QINSTALLDIR}/${qproduct}\"" >> "${QENV}"
echo "" >> "${QENV}"

if [ "$PKG_TYPE" = "dev" ] ;then
	echo "echo export ${opencl_dev_env}=\"${QINSTALLDIR}/${opencl}\"" >> "${QENV}"
	echo "export ${opencl_dev_env}=\"${QINSTALLDIR}/${opencl}\"" >> "${QENV}"
	echo "export CL_CONTEXT_COMPILER_MODE_INTELFPGA=3" >> "${QENV}"
	echo "" >> "${QENV}"	
	QUARTUS_BIN="${QINSTALLDIR}/${qproduct}/bin"
	echo "QUARTUS_BIN=\"${QUARTUS_BIN}\"" >> "${QENV}"
	echo "if [[ \":\${PATH}:\" = *\":\${QUARTUS_BIN}:\"* ]] ;then" >> "${QENV}"
	echo "    echo \"\\\$${qproduct_env}/bin is in PATH already\"" >> "${QENV}"
	echo "else" >> "${QENV}"
	echo "    echo \"Adding \\\$${qproduct_env}/bin to PATH\"" >> "${QENV}"
	echo "    export PATH=\"\${QUARTUS_BIN}\":\"\${PATH}\"" >> "${QENV}"
	echo "fi"  >> "${QENV}"
	echo "" >> "${QENV}"
fi

if [ "$DCP_LOC" != "" ] ;then
    echo "echo export OPAE_PLATFORM_ROOT=\"${DCP_LOC}\"" >> "${QENV}"
    echo "export OPAE_PLATFORM_ROOT=\"${DCP_LOC}\"" >> "${QENV}"
    echo "" >> "${QENV}"
   
    echo "echo export AOCL_BOARD_PACKAGE_ROOT=\"${DCP_LOC}/opencl/opencl_bsp\"" >> "${QENV}"
    echo "export AOCL_BOARD_PACKAGE_ROOT=\"${DCP_LOC}/opencl/opencl_bsp\"" >> "${QENV}"  
    if [ $install_opae -eq 1 ] ; then 
        echo "echo source \$AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/setup_permissions.sh" >> "${QENV}"
        echo "source \$AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/setup_permissions.sh >> /dev/null " >> "${QENV}" 
    fi
    OPAE_PLATFORM_BIN="${DCP_LOC}/bin"
    echo "OPAE_PLATFORM_BIN=\"${OPAE_PLATFORM_BIN}\"" >> "${QENV}"
    echo "if [[ \":\${PATH}:\" = *\":\${OPAE_PLATFORM_BIN}:\"* ]] ;then" >> "${QENV}"
    echo "    echo \"\\\$OPAE_PLATFORM_ROOT/bin is in PATH already\"" >> "${QENV}"
    echo "else" >> "${QENV}"
    echo "    echo \"Adding \\\$OPAE_PLATFORM_ROOT/bin to PATH\"" >> "${QENV}"
    echo "    export PATH=\"\${PATH}\":\"\${OPAE_PLATFORM_BIN}\"" >> "${QENV}"
    echo "fi"  >> "${QENV}"
    echo "echo sudo cp \"${DCP_LOC}/sw/fpgaflash\" /usr/bin/" >> "${QENV}"
    echo "sudo cp \"${DCP_LOC}/sw/fpgaflash\" /usr/bin/" >> "${QENV}"
    echo "sudo chmod 755 /usr/bin/fpgaflash" >> "${QENV}"
    echo "echo sudo cp \"${DCP_LOC}/sw/afu_platform_info\" /usr/bin/" >> "${QENV}"
    echo "sudo cp \"${DCP_LOC}/sw/afu_platform_info\" /usr/bin/" >> "${QENV}"
    echo "sudo chmod 755 /usr/bin/afu_platform_info" >> "${QENV}"
    echo "echo find \"$DCP_LOC/hw/samples/\" -type d -name *S10* -exec rm -r {} +" >> "${QENV}"
    echo "find \"$DCP_LOC/hw/samples/\" -type d -name *S10* -exec rm -r {} +" >> "${QENV}"
    echo "" >> "${QENV}"
fi

if [ "$PKG_TYPE" = "rte" ] ;then
        echo "echo source \$${qproduct_env}/init_opencl.sh" >> "${QENV}"
        echo "source \$${qproduct_env}/init_opencl.sh >> /dev/null" >> "${QENV}"
fi

################################################################################
#    End of the installation
################################################################################
comment "Finished installing $PRODUCT_NAME"
echo ""
echo "*** Note: You need to source ${QENV} to set up your environment. ***"
echo ""
