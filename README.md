# Description

This is a work in progress, it is fully usable and runs correctly, but documentation is still incomplete.

**Buildroot-armv7** is a Docker image (in wich Buildroot is not included), a set of scripts, configuration files and Buildroot external tree to easily setup an emulation environment where to run, debug and reverse engineer the *Netgear DVA 5592* router executables. This environment uses Docker, Buildroot and Qemu to build a root file system and emulate a board with an ARMv7 Cortex A9 processor, a quite old Linux kernel, version 3.4.11-rt19 with appropriate patches, uClibc 0.9.33.2, and old versions of other libraries.

# Table of Contents

- [Description](#description)
- [Table of Contents](#table-of-contents)
- [Quick Start](#quick-start)
- [Building the emulation environment](#building-the-emulation-environment)
	- [Emulation environment requirements](#emulation-environment-requirements)
	- [Choosing the tool to build the Root File System](#choosing-the-tool-to-build-the-root-file-system)
	- [Issues to overcome](#issues-to-overcome)
	- [The Docker image](#the-docker-image)
	- [Buildroot configuration](#buildroot-configuration)
	- [Running Buildroot](#running-buildroot)
- [Reverse Engineering Router's Binaries](#reverse-engineering-routers-binaries)
	- [File system and console output analysis](#file-system-and-console-output-analysis)
	- [Reverse Engineering `sig_verify`](#reverse-engineering-sigverify)
		- [Listing `sig_verify` library calls](#listing-sigverify-library-calls)
		- [Starting the emulated Machine](#starting-the-emulated-machine)
		- [Starting `gdbserver` on the emulated Machine](#starting-gdbserver-on-the-emulated-machine)
		- [Starting `gdb` in the host machine](#starting-gdb-in-the-host-machine)
		- [Generate a Public Key file in *pem* format with the MPIs in `sig_verify`](#generate-a-public-key-file-in-pem-format-with-the-mpis-in-sigverify)
		- [`mysig_verify`: a script that does the same job as `sig_verify`](#mysigverify-a-script-that-does-the-same-job-as-sigverify)
		- [Conclusion on reverse engineering `sig_verify`](#conclusion-on-reverse-engineering-sigverify)

# Quick Start

On a Linux box, the only OS supported:

  * install Docker, [this guide](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-18-04), or similar guides, can be useful
  * add your username to the *docker* group with a command similar to the following (can be different in some Linux distributions):
     ```
     $ sudo adduser *yourusername* docker
     ```
  * install [Qemu](https://www.qemu.org/), using something similar to the following commands:
    ```
    $ sudo apt-get install qemu qemu-block-extra qemu-kvm qemu-slof qemu-system \
      qemu-system-arm qemu-system-common qemu-system-mips qemu-system-misc \
      qemu-system-ppc qemu-system-s390x qemu-system-sparc qemu-system-x86 \
      qemu-user qemu-user-binfmt qemu-utils
    ```
  * install [Binwalk](https://github.com/ReFirmLabs/binwalk), using something similar to the following commands:
    ```
    $ sudo apt-get install binwalk
    ```
  * install [Jefferson](https://github.com/sviehb/jefferson), following instructions on the GitHub repository
  * download this project with command similar to the followings:
    ```
    valerio@ubuntu-hp:~$ mkdir br      # configuration script will create folders here
    valerio@ubuntu-hp:~$ cd br
    valerio@ubuntu-hp:~/br$ git clone https://github.com/digiampietro/buildroot-armv7.git buildroot-armv7
    ```
  * type the following commands, the `br-armv7-config.sh` script will download Buildroot, Linux kernel, router firmware and will configure the environment
    ```
    valerio@ubuntu-hp:~/br$ cd buildroot-armv7   
    valerio@ubuntu-hp:~/br/buildroot-armv7$ ./br-armv7-config.sh
    ```
  * download the docker image from the Docker repository
    ```
    valerio@ubuntu-hp:~/br/buildroot-armv7$ docker pull digiampietro/buildroot-armv7
    ```
  * run the docker image, it is based on the old Debian Wheezy to run the old buildroot-2014-02; the current username and home directory are mapped inside the docker host. Inside the docker host the command prompt has changed, the hostname now is *BRHOST*:
    ```
    valerio@ubuntu-hp:~/br/buildroot-armv7$ cd docker/
    valerio@ubuntu-hp:~/br/buildroot-armv7/docker$ ./dockrun.sh
    valerio@BRHOST:~$ cd ~/br/buildroot-armv7
    ```
  * run the *Buildroot* make using the *brmake* shell script that sets the *BR2_EXTERNAL* environment variable to use a customized buildroot external tree:
    ```
    valerio@BRHOST:~/br/buildroot-armv7$ ./brmake dvaemu-emu_arm_vexpress_defconfig
    valerio@BRHOST:~/br/buildroot-armv7$ ./brmake # takes a loooong time
    ```
  * at the end of the buildroot process a root file system image has been built, ready to be used by *Qemu*, running outside the docker machine:
    ```
    valerio@BRHOST:~/br/buildroot-armv7$ exit
    root@BRHOST:/src/misc# exit
    valerio@ubuntu-hp:~/br/buildroot-armv7/docker$ cd ../qemu-run/
    valerio@ubuntu-hp:~/br/buildroot-armv7/qemu-run$ ./qr
    ...
    reeing init memory: 160K
    smsc911x 4e000000.ethernet: eth0: SMSC911x/921x identified at 0xc08c0000, IRQ: 47
    Welcome to Buildroot
    buildroot login: root
    root@buildroot:~# uname -a
    Linux buildroot 3.4.11-rt19 #1 SMP PREEMPT Fri Sep 28 18:46:38 UTC 2018 armv7l GNU/Linux
    root@buildroot:~#
    ```
  * an ARM virtual machine is now available to run debug and reverse engineer the most interesting router executables. The router root file system has been included in the ARM image in the folder `/dva-root`, the firmware files and file system images are included in the folder `/dva-firm`:
    ```
    root@buildroot:~# ls /dva-root/
    bin         dev.tar.gz  mnt         sbin        usr
    data        etc         proc        sys         var
    dev         lib         root        tmp         www
    root@buildroot:~# ls /dva-firm/
    DVA-5592_A1_WI_20180405.sig  root-fs.bin
    boot-fs.bin                  set-nandsim.sh
    ```
  * to exit from the Qemu virtual machine you can type `# halt` and then press `Ctrl-A` followed by the key `X`


# Building the emulation environment
The purpose of the emulation environment is to run, as much as possible, router executables in a Qemu virtual machine. This means not only that the machine must have an ARM v7 Cortex-A9 processor, but that the kernel and the libraries should be the same version, or compatible versions, used in the router.

## Emulation environment requirements
The emulated environment should have:
  * an ARM v7 Cortex A9 Processor
  * an emulated 256Mb Nand flash memory, emulated with the *nandsim* kernel flash emulator
  * a Linux Kernel version 3.4.11-rt19
  * a root file system using uClibc, version 0.9.33.2, as standard C library
  * a Gnu libgcrypt crypto library version 1.5 (with library file: `libgcrypt.so.11`)
  * other libraries with compatible versions with the router's binaries
These requirements basically means to use what was available in 2014, because the software used to build the router firmware seems coming from that year.

## Choosing the tool to build the Root File System
The root file system can be built with a cross compilation toolchain able to generate binaries for the ARM architecture on an Intel based Linux PC; but building the kernel, the libraries and the needed packages can be very challenging and time consuming because of the various version dependency that each package can have with other packages and standard libraries (the so called *dependency hell*). For this reason it is better to select a build tool able to manage this *dependency hell*, the most popular building tools for embedded devices are:
  * [The Yocto Project](https://www.yoctoproject.org/) is very powerful, not only builds a root file system, but is able to create a custom Linux distribution for the embedded device. It's main drawback is that it has a steep learning curve
  * [Buildroot](https://buildroot.org/) has a more limited scope: it builds the root file system and the kernel, it is quite easy and fast to learn and has a very good user manual, not too big, neither too small
  * [Openwrt/LEDE Build System](https://openwrt.org/docs/guide-user/additional-software/beginners-build-guide) is tailored mainly to build a replacement router firmware, his documentation is much more scattered in the web site and so requires more time to learn.

Buildroot has been the tool chosen for this reverse engineering project. It has been easy to learn ed effective in building the required root file system.

## Issues to overcome
Initial idea was using the latest Buildroot version available (*buildroot-2018-05*) on the last Ubuntu version (*18.04.1 LTS, Bionic Beaver*), but this buildroot version doesn't have the option to use uClibc, it has uClibc-ng that is not fully compatible with the router's binaries compiled with uClibc; the Gnu libgcrypt crypto library is a newer version, not fully compatible wth the router's binaries. It is practically impossible to downgrade these two libraries and others because of the *dependency hell*.

Another idea was to use an older Buildroot version (*buildroot-2014-02*) that has the same router's uClibc version, compatible version of Gnu libgcrypt crypto library and similar versions of other libraries. The problem is that this buildroot version, on Ubuntu 18.04, gives multiple compilation errors, almost impossible to fix; changing gcc version doesn't help to solve all the issues.

The solution has been to use a Docker image, based on *Debian Wheezy* released in 2013, to run *buildroot-2014-02*; this docker image is able to run this version of buildroot without any issues.

During the setup of this environment many other issues have arisen, described below in the description of various configurations.

## The Docker image
The main purpose of the Docker image is to have a Linux environment able to run *buildroot-214.02* without issues, for this reason the image is based on Debian Wheezy (released in 2013) with additional packages needed to run *buildroot-2014.02*, including packages and QT libraries to do a `make xconfig` with a GUI. The [Docekerfile](https://github.com/digiampietro/buildroot-armv7/blob/master/docker/Dockerfile) is quite simple and doesn't include Buildroot.

Buildroot is installed in the user's home directory because both the user and his home directory are mapped inside the Docker image using the following shell script, [`docker/dockrun.sh`](https://github.com/digiampietro/buildroot-armv7/blob/master/docker/dockrun.sh), to run the Docker image:
```shell
#!/bin/sh

export GDISPLAY=unix/$DISPLAY      # forward X11 display to the host machine
export GUSERNAME=`id -u -n`        # current user's username
export GUID=`id -u`                # current user's user id
export GGROUP=`id -g -n`           # current user's primary group name
export GGID=`id -g`                # current user's primary group id
export GHOME=$HOME                 # current user's home directory
export GSHELL=$SHELL               # current user's shell
export GRUNXTERM=0                 # flag start lxterminal, useful in windows
export GPWD=`pwd`                  # current working directory

docker run      -h BRHOST                         \
                --rm                              \
                -v /tmp/.X11-unix:/tmp/.X11-unix  \
                -v $HOME:$HOME                    \
                -e DISPLAY=$GDISPLAY              \
                -e GUSERNAME=$GUSERNAME           \
                -e GUID=$GUID                     \
                -e GGROUP=$GGROUP                 \
                -e GGID=$GGID                     \
                -e GHOME=$GHOME                   \
                -e GSHELL=$SHELL                  \
                -e GRUNXTERM=$GRUNXTERM           \
                -e GPWD=$GPWD                     \
                -it digiampietro/buildroot-armv7
```
In this script:
  * the user's home directory (*$HOME*) is mapped, with option `-v`, inside the running image at exactly the same path
  * the `-v /tmp/.X11-unix:/tmp/.X11-unix` option has the purpose do display, on the host, X11 applications running inside the Docker image
  * the `--rm` options terminate the Docker image process after exiting from the interactive shell; This is needed to prevent having a lot of unused stopped images
  * some environment variables (options `-v`) are passed from the host to the docker image with the purpose to create, on the fly, inside the image, the same user existing on the host with exact same attributes (username, uid, primary group, shell, home dir). This job is accomplished by the following **entrypoint** script `docekr/startup.sh`:

  ```shell
#!/bin/sh
#
# add current user and user's primary group
#
groupadd -g $GGID $GGROUP
useradd  -u $GUID -s $GSHELL -c $GUSERNAME -g $GGID -M -d $GHOME $GUSERNAME
usermod  -a -G sudo $GUSERNAME
echo $GUSERNAME:docker | chpasswd
if [ "$GRUNXTERM" = "1" ]
then
    # become the current user and start a shell
    su -l -c lxterminal $GUSERNAME
    # another root shel
    lxterminal
else
    # become the current user and start a shell
    su -l $GUSERNAME
    # another root shell
    /bin/bash
fi
  ```

This Docker usage pattern allows to transparently share the user's home directory between the host and the Docker image and can be used every time there is a need to use a Docker image to transparently run software that cannot be run on the host and that will use and/or modify files in user's home directory.

In this case the *Buildroot* folder is not installed inside the Docker image, but will be installed in user's home directory and, in this way, the Buildroot folder will remain persistent across Docker image invocations.

## Buildroot configuration

The Buildroot configuration is stored in an external tree in the folder `ext-tree`, Buildroot itself can be launched with the shell script `brmake` that, basically, change directory in the Buildroot directory and execute a `make BR2_EXTERNAL=<path to ext-tree>`.

The `ext-tree` folder has the following content:
```
ext-tree/
├── board
│   └── dvaemu
│       ├── kernel-defconfig
│       ├── overlay
│       │   └── etc
│       │       └── profile.d
│       │           └── set-prompt.sh
│       └── post-build.sh
├── Config.in
├── configs
│   ├── dvaemu-emu_arm_vexpress_defconfig
│   └── uClibc-0.9.33.config
├── external.desc
├── external.mk
├── package
│   └── klish
│       ├── 0001-klish-help-param-optional.patch
│       ├── Config.in
│       └── klish.mk
└── patches
    └── linux
        ├── 0002-module.h-remove-p2v8-from-module-id-string.patch
        ├── 0004-jffs2_make_lzma_available.patch
        ├── 0005-jffs2_eofdetect.patch
        └── 0006-jffs2_make_lzma_high_priority.patch
```

  * **ext-tree/board/dvaemu** contains files for the *fictitious* board called *dvaemu* (for DVA 5592 router emulation)

  * **ext-tree/board/dvaemu/kernel-defconfig** contains the kernel configuration, saved in a *defconfig* file; main differences, compared with the default kernel configuration, have been introduced to be more similar to the router's kernel and to run it in QEMU:
    - *General setup*
      - Choose SLAB allocator: SLAB, this is needed to run some binaries/Libraries
    - *System type*: Versatile Express platform type with Device Tree support
    - *Preemption Model*: Preemptible Kernel (low latency Desktop)
    - *Device Drivers*
      - NAND Device Support and Support for NAND Flash Simulator, this is very important to simulate the JFFS2 file system on the flash memory
      - OneNAND Device Support
      - Enable UBI
    - *File Systems*
      - Miscellaneous filesystems: JFFS2 support, Advanced Compression, JFFS2 LZMA compression supported
    - *Library routines*
      - CRC-CCITT functions
      - CRC16 functions
      - CRC calculations for the T10 Data Integrity Field
      - CRC ITU-T V.41 functions

  * **ext-tree/board/dvaemu/overlay** in this path's subfolder there is the `set-prompt.sh` script used to setup the prompt inside the QEMU emulated machine

  * **ext-tree/board/dvaemu/post-build.sh** this is the Buildroot post-build script, used mainly to copy router's root file system and firmware to the root image of the emulated machine

  * **ext-tree/Config.in, external.desc, external.mk** are files needed by Buildroot to use the external tree

  * **ext-tree/configs/dvaemu-emu_arm_vexpress_defconfig** contains the buildroot configuration, it is based on the *qemu_arm_vexpress_defconfig*, included in buildroot, to emulate a *Versatile Express ARM board* with an ARMv7 Cortex-A9 processor. The most important modified options are:
    - *Target Option: EABIhf*, because the router's CPU seems to support hardware floating point processing
    - *Build Options*, the selected options are needed to make easier the reverse engineering job:
        - *Build packages with debugging symbols*
        - *gcc debug level 2*
        - *strip binaries: no*
        - *gcc optimization level 0*
        - *global patch directories*, to point to the external tree patch directory
    - *Toolchain*, the selected options are needed to enable and facilitate debugging and to compile the 3.4.11-rt9 Kernel
      - Kernle Headers: 3.4.x
      - Enable large file support
      - Enable WCHAR support
      - Thread library debugging
      - Enable C++ support
      - Build cross GDB for the host
    - *Linux Kernel*, the selected options are needed to select the 3.4.11-rt9 kernel and to run it under QEMU:
      - Custom tarball location
      - Kernel configuration: using a custom config file
      - Device tree support
      - Install kernel image to /boot Target
    - *Compressor and Decompressor*, useful for the purpose of emulating the router environment
      - bzip2
      - xz-utils
    - *Debugging profiling and benchmark*, the selected options are useful for reverse engineering
      - gdb (gdbserver and full debugger)
      - ltrace
      - strace
    - *Development tools*
      - binutils, flex, libtools, make, pkgconf
      - mtd, jffs2 and ubi/ubifs tools; these are very important because are related to flash eeprom Emulation
    - *Libraries*, the selected options are needed to emulate binaries requiring the selected libraries
      - libgcrypt, expat, roxml, libxml2, Mini-XML
    - *Network Applications* are included to exchange files between the emulated machine and the external world
      - rsync, rsh-redone, socat, ncftp, iputils
    - *Shell and utilities*
      - file, sudo
    - *Host utilities*
      - host mtd, jffs2 and ubi/ubifs tools
    - *User provided options*
      - klish, to try to emulate the router's shell

  * **ext-tree/configs/uClibc-0.9.33.config** this is the uClibc configuration, the main differences, compared with the default, have been introduced to be compatible with the router's binaries and to include debugging symbols in the library files. The inclusion of debugging symbols has been problematic: uClibc don't obey to the general option included in the Buildroot configuration, has his own flag for this purpose; the problem is that enabling his own flag the compilation gives impossible to fix errors, for this reason a workaround, described below, has been used:
    - *Target Architecture Features and Options*
      - Build for EABI
      - Use BX in function return
      - Enable full C99 math library support
    - *General Library Settings*
      - Enable library loader preload file, not selected
      - Link LD Config statically, not selected
      - Thread support, native POSIX Threading
      - Build pthreads debugging support
      - Malloc returns live pointer for malloc(0)
      - Provide libutil library and functions
    - *String and Stdio support*
      - Wide character support
      - Support hexadecimal float notation
      - Support glibc's register_printf_function()
      - Some other glibc compatible settings
    - *Development/debugging options*
      - in Compiler Warnings add the string "-ggdb", this is the work around to compile the uClibc with debugging symbols

  * **ext-tree/package**, in this directory is included the *klish* package, but, unfortunately, it is not compatible with the router's *klish* configuration files, probably the *klish* application in the router has been modified in incompatible ways

  * **ext-tree/patches/linux**: linux patches to have the kernel more similar to the router's kernel, the patches are:
    - *0002-module.h-remove-p2v8-from-module-id-string.patch* to make the kernel identifying string identical to the router's kernel modules, but, unfortunately, in this way it is possible to load router's module in the emulated machine, but the kernel crashes
    - *0004-jffs2_make_lzma_available.patch* this patch implements the LZMA compression for the JFFS2 file system, it has been borrowed and adapted from the OpenWRT project
    - *0005-jffs2_eofdetect.patch* this patch implements the *end of partition detection* for JFFS2 filesystems, this patch is included in the router's kernel and automatically detect the end of a JFFS2 partition, thanks to a magic number
    - *0006-jffs2_make_lzma_high_priority.patch* this patch makes LZMA compression the preferred compression method for the JFFS2 partition, similar to what the router's kernel does.

## Running Buildroot

The [Buildroot User's Manual](https://buildroot.org/downloads/manual/manual.html) is a very good guide on how to configure and run Buildroot; in this environment Buildroot make commands should be executed using the *brmake* script inside the *buildroot-armv7* folder, the most useful commands are:

  * `./brmake xconfig` (or `./brmake menu-config`) to configure Buildroot options;
  * `./brmake linux-xconfig` (or `./brmake linux-menuconfig`) to configure the Linux Kernel
  * `./brmake uclibc-menuconfig` (the *xconfig* version is not available for *uClibc*) to configure the *uClibc* library
  * `./brmake savedefconfig` to save the Buildroot configuration in the external tree, on the file `ext-tree/configs/dvaemu-emu_arm_vexpress_defconfig`
  * `./brmake linux-update-defconfig` to save the Linux Kernel configuration in the external tree, on the file `ext-tree/board/dvaemu/kernel-defconfig`
  * `./brmake uclibc-update-defconfig` to save the uClibc configuration in the external tree, on the file `ext-tree/configs/uClibc-0.9.33.config`
  * `./brmake clean` to delete all build products (including build directories, host, staging and target trees, the images and the toolchain)
  * `./brmake distclean` to delete everything, including configuration files; needed to build for a new target, should not be needed with this environment;
  * `./brmake linux-dirclean` removes the whole kernel build directory, to be used when kernel configuration changes are made;
  * `./brmake -s printvars` to dump all the variables known to make;
	* `./brmake` to build the kernel and the root file system.

	## Running QEMU

	To run QEMU there is the `qr` script inside the `qemu-run` folder, this script runs QEMU using the root file system built by Buildroot. The script is the following:
	```sh
	#!/bin/bash
	MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	. $MYDIR/../set-env.sh
	cd $MYDIR
	export QEMU_AUDIO_DRV="none"
	qemu-system-arm -M        vexpress-a9                                                    \
	                -cpu      cortex-a9                                                      \
	                -m        1024                                                           \
	                -nographic                                                               \
	                -kernel   $BRIMAGES/zImage                                               \
	                -drive    file=$BRIMAGES/rootfs.ext2,index=0,media=disk,format=raw,if=sd \
	                -dtb      $BRIMAGES/vexpress-v2p-ca9.dtb                                 \
	                -net      nic                                                            \
	                -net      user,hostfwd=tcp::2222-:22,hostfwd=tcp::9000-:9000             \
	                -append   "rw console=ttyAMA0 console=tty root=/dev/mmcblk0"
	```  
	The first three lines set environment variables and change directory to that of the script, the fourth line disables the audio driver (the emulated board doesn't emulate audio hardware), the `qemu-system-arm` options select:
	  * board *vexpress-a9* with processor *cortex-a9* and 1Gb of RAM
	  * the *-nographic* option prevents the opening of another window: the console input/output go to the terminal
	  * the *-kernel* option selects the kernel generated by Buildroot
	  * the *-drive* option selects the root file system image generated by Buildroot emulated as an SD disk
	  * the *-dtb* option selects the *Device Tree Blob* generated by Buildroot and describing the board devices to the kernel
	  * the *-net* options associate an ethernet card to the emulated board and does port forwarding from the host to the qemu machine, the forwarded ports are host port 2222 to qemu machine port 22 (to do *ssh* from the host to the qemu machine) and port 9000 from the host to same port on the qemu machine (it will be used by *gdb/gdbserver*).
	To stop the emulated machine there is the command **`halt`** and to exit from the emulator there is the key command sequence: **`Ctrl-A`** **`X`**.

# Reverse Engineering Router's Binaries

The main purpose of this reverse engineering project is to modify the router firmware to be able to modify configurations, add additional software and to be able to login and become *root* on the router.

To achieve this goal three main activities are needed:
  * **file system analysis** to analyze interesting router's script especially initial boot sequence and firmware upgrade scripts;
  * **console output analysis**: re-populate the serial interface on the router, attach a serial console and capture router's output during boot and during upgrade;
  * **reverse engineer**: select and reverse engineer interesting binaries.

## File system and console output analysis

Some areas of interest in doing these analysis are:

  * **upgrade procedure**: looking at the console output during the upgrade process (see the file [``misc/router-console-upgrade.log``](misc/router-console-upgrade.log)) and at the related router's scripts (`/usr/sbin/upgrade-prepare.sh` and `/usr/sbin/upgrade.sh`) it is possible to understand the firmware file layout (may be not every details), where the file system root and boot images are, how these images are written to the NAND flash eeprom. It is also possible to understand that the firmware image is digitally signed and that the router's binary `/usr/sbin/sig_verify` is used to check the signature authenticity; for this reason the first interesting binary to reverse engineer is `sig_verify` to understand if it is possible to modify the firmware and make a valid fake signature; unfortunately this is not possible, but the analysis has been anyway interesting.

	* **klish configuration file**: it is possible to telnet or ssh to the router to get a restricted shell based on the open source [*klish*](http://libcode.org/projects/klish/) project. Looking at the `bin/clish` script and at the startup script it is possible to find that the *clish* configuration file is `/etc/clish/startup.xml`. Analyzing this configuration file it is possible to find that it is possible to enter *factory mode* and get a normal, unprivileged Linux busybox shell. (details on the [*adbtools2*](https://github.com/digiampietro/adbtools2) project).

	* **interesting binaries**: not being able to modify the firmware using the normal firmware upgrade process, because of the firmware signature, it is needed to find some other way to get a root shell on the router to reach the project target. The idea is to use the unprivileged access to exploit some router binary, running as root, to force it to run a specially crafted shell script to get a root shell. So the interesting binaries are those running as root in the router. Using the unprivileged access to get a list of running processes on the router:
	```
	/root $ ps -ef
  PID USER       VSZ STAT COMMAND
    1 0         1184 S    init
    2 0            0 SW   [kthreadd]
    3 0            0 SW   [ksoftirqd/0]
    4 0            0 SW   [kworker/0:0]
    5 0            0 SW   [kworker/u:0]
    6 0            0 SW   [migration/0]
    7 0            0 SW   [migration/1]
    8 0            0 SW   [kworker/1:0]
    9 0            0 SW   [ksoftirqd/1]
   10 0            0 SW<  [cpuset]
   11 0            0 SW<  [khelper]
   12 0            0 SW<  [netns]
   13 0            0 SW   [kworker/u:1]
   69 0            0 SW   [sync_supers]
   71 0            0 SW   [bdi-default]
   73 0            0 SW<  [kblockd]
   78 0            0 SW   [khubd]
   87 0            0 SW   [skb_free_task]
   88 0            0 SW   [bcmFapDrv]
  105 0            0 SWN  [kswapd0]
  106 0            0 SW   [fsnotify_mark]
  107 0            0 SW<  [crypto]
  177 0            0 SW   [kworker/1:1]
  178 0            0 SW   [kworker/0:1]
  185 0            0 SW   [mtdblock0]
  190 0            0 SW   [mtdblock1]
  195 0            0 SW   [mtdblock2]
  200 0            0 SW   [mtdblock3]
  205 0            0 SW   [mtdblock4]
  210 0            0 SW   [mtdblock5]
  215 0            0 SW   [mtdblock6]
  220 0            0 SW   [mtdblock7]
  226 0            0 SW   [cfinteractive]
  229 0            0 SW<  [linkwatch]
  233 0            0 SW<  [deferwq]
  234 0            0 SWN  [jffs2_gcd_mtd2]
  261 0          724 S <  /sbin/udevd --daemon
  274 1001      1328 S    /bin/clish.elf -l -x /tmp/clish
  326 0         2332 S    cm
  365 0         1800 S    logd
  368 0          704 S    ec
  405 0            0 SW   [bcmxtm_rx]
  439 0            0 SW   [bcmFlwStatsTask]
  830 0            0 SW   [bcmsw_rx]
  903 0            0 SW   [bcmsw]
  924 0            0 SW   [flush-mtd-unmap]
 1032 0            0 SW   [dhd_watchdog_th]
 1033 0            0 SW   [dhd0_dpc]
 1034 0            0 SW   [wfd0-thrd]
 1235 0            0 SW   [spu_rx]
 1715 0            0 SW   [wl1-kthrd]
 1783 0            0 SW   [wfd1-thrd]
 1997 0            0 SW   [dsl0]
 2383 0          820 S    dns
 2605 0            0 SW   [flush-254:0]
 2630 0         2480 S    cwmp
 2631 0         1204 S    inetd -f
 2633 0          736 S    yamp -c /tmp/yamp.conf -p /tmp/yamp.pid
 2658 0          664 S    wpspbc
 3075 0            0 SW   [kworker/0:2]
 3089 0         2316 S    hostapd -B /tmp/wlan/config/hostapd.conf.wl1 -P /var
 3090 65534     3560 S    httpd -u nobody
 3638 0         2316 S    hostapd -B /tmp/wlan/config/hostapd.conf.wl0 -P /var
 3647 0         1068 S    chronyd -n -f /tmp/chrony.conf
 4191 0          696 S    /sbin/rngd -r /dev/urandom -W 4000
 4211 0         7136 S    voip
 4225 0            0 SW   [voice-aoRT]
 4232 0            0 SW   [voice-HTSK]
 4239 0            0 SW   [voice-HRTBEAT]
 4240 0            0 SW   [voice-VRGDISP]
 4241 0            0 SW   [voice-HCAS]
 4242 0            0 SW   [voice-ISTW]
 4243 0            0 SW   [YAPS_Dsp_Event_]
 4244 0            0 SW   [YAPS_Dsp_Data_R]
 4402 1001         0 Z    [clish.elf]
 4403 1001      1176 S    /bin/sh -c /bin/sh /tmp/klish.fifo.5nMkcg
 4404 1001      1176 S    /bin/ash
 4405 1001      1176 R    ps -ef
/root $
	```   

A first list of interesting binaries includes: init, udevd, cm, logd, ec, dns, cwmp, inetd, yamp, wpspbc, hostapd, chronyd, rngd, voip.

It is better to exclude operating systems binaries: init, udevd, logd, inetd, chronyd, rngd unless there are known vulnerabilities exploitable in the specific router usage, version and configuration.

The remaining executables:
* **dns**: looking at the message string in the `/etc/init.d/services.sh` it is labeled as *Start Networking*, could be interesting, but usually low level stuff are more difficult to hack, for this reason assign it a lower priority in reverse engineering;
* **ec**: looking at the message string in the `/etc/init.d/services.sh` it is an *Event Controller*, could be interesting so normal priority in reverse engineering it;
* **cwmp**: probably implements the *cwmp* protocol used by the remote management system based on *TR-069*; it is the system that allows the telco company to remotely manage the router. It should be a quite complicated piece of software, probably difficult to hack. So lower priority in selecting it for reverse engineering;
* **yamp**: it is executed by the script `/etc/ah/IGMPProxy.sh`, so it has to do with the IGMP protocol, again low level stuff, usually difficult to hack, lower priority in reverse engineering;
* **wpspbc**: seems to have to do with Wifi Protected Setup stuff, again, low level stuff difficult to hack, lower priority in reverse engineering;
* **voip**: manages the voip telephone, again low level stuff difficult to hack, lower priority in reverse engineering;
* **cm**: looking at the message string in the `/etc/init.d/services.sh` it is labeled as *Configuration Manager (B)* and in many many scripts there is the command *cmclient* executed many times to get information from the system and to configure parameters in the router. In the klish configuration file many tasks are carried out by a *cmclient* command, this probably means that an unprivileged *cmclient* process talks to the *cm* process to get privileged job done (as changing IP address or adding new users), for this reason this seems the most interesting binary to reverse engineer.

## Reverse Engineering `sig_verify`

The arm executable `sig_verify` has no debugging information and has been stripped but, as almost all executables, it makes a lot of library calls. The "emulated" execution environment has been set up with debugging information on all executable and all library files, this means that to reverse engineer the `sig_verify` executable it is needed to follow the library calls it does.

### Listing `sig_verify` library calls

Because the executable is stripped, the typical `readelf` command gives little information:
```
valerio@ubuntu-hp:~/br/buildroot-armv7/qemu-run$ source set-aliases
valerio@ubuntu-hp:~/br/buildroot-armv7/qemu-run$ arm-linux-readelf -a $DVAROOT/usr/sbin/sig_verify
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF32
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           ARM
  Version:                           0x1
  Entry point address:               0x8a18
  Start of program headers:          52 (bytes into file)
  Start of section headers:          0 (bytes into file)
  Flags:                             0x5000002, has entry point, Version5 EABI
  Size of this header:               52 (bytes)
  Size of program headers:           32 (bytes)
  Number of program headers:         6
  Size of section headers:           0 (bytes)
  Number of section headers:         0
  Section header string table index: 0

There are no sections in this file.

There are no sections to group in this file.

Program Headers:
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  PHDR           0x000034 0x00008034 0x00008034 0x000c0 0x000c0 R E 0x4
  INTERP         0x0000f4 0x000080f4 0x000080f4 0x00014 0x00014 R   0x1
      [Requesting program interpreter: /lib/ld-uClibc.so.0]
  LOAD           0x000000 0x00008000 0x00008000 0x0171b 0x0171b R E 0x8000
  LOAD           0x00171c 0x0001171c 0x0001171c 0x001f1 0x00204 RW  0x8000
  DYNAMIC        0x001728 0x00011728 0x00011728 0x00100 0x00100 RW  0x4
  GNU_STACK      0x000000 0x00000000 0x00000000 0x00000 0x00000 RW  0x4

Dynamic section at offset 0x1728 contains 27 entries:
  Tag        Type                         Name/Value
 0x00000001 (NEEDED)                     Shared library: [libgcrypt.so.11]
 0x00000001 (NEEDED)                     Shared library: [libgpg-error.so.0]
 0x00000001 (NEEDED)                     Shared library: [libgcc_s.so.1]
 0x00000001 (NEEDED)                     Shared library: [libc.so.0]
 0x0000000c (INIT)                       0x8874
 0x0000000d (FINI)                       0x936c
 0x00000019 (INIT_ARRAY)                 0x1171c
 0x0000001b (INIT_ARRAYSZ)               4 (bytes)
 0x0000001a (FINI_ARRAY)                 0x11720
 0x0000001c (FINI_ARRAYSZ)               4 (bytes)
 0x00000004 (HASH)                       0x8108
 0x00000005 (STRTAB)                     0x8528
 0x00000006 (SYMTAB)                     0x8258
 0x0000000a (STRSZ)                      455 (bytes)
 0x0000000b (SYMENT)                     16 (bytes)
 0x00000015 (DEBUG)                      0x0
 0x00000003 (PLTGOT)                     0x11828
 0x00000002 (PLTRELSZ)                   256 (bytes)
 0x00000014 (PLTREL)                     REL
 0x00000017 (JMPREL)                     0x8774
 0x00000011 (REL)                        0x876c
 0x00000012 (RELSZ)                      8 (bytes)
 0x00000013 (RELENT)                     8 (bytes)
 0x6ffffffe (VERNEED)                    0x874c
 0x6fffffff (VERNEEDNUM)                 1
 0x6ffffff0 (VERSYM)                     0x86f0
 0x00000000 (NULL)                       0x0

There are no relocations in this file.

Histogram for bucket list length (total of 37 buckets):
 Length  Number     % of total  Coverage
      0  13         ( 35.1%)
      1  11         ( 29.7%)     25.0%
      2  8          ( 21.6%)     61.4%
      3  4          ( 10.8%)     88.6%
      4  0          (  0.0%)     88.6%
      5  1          (  2.7%)    100.0%

No version information found in this file.

```
Anyway this command shows that it uses `libgcrypt`, `libgpg-error`, `libgcc_s` and `libc` (the last two provided by *uClibc*).

The following `readelf` command (display symbols in the dynamic section) lists the library function calls and external symbols used by the executable:
```
valerio@ubuntu-hp:~/br-dva-emu/dvaemu/qemu-run$ arm-linux-readelf --sym -D $DVAROOT/usr/sbin/sig_verify

Symbol table for image:
  Num Buc:    Value  Size   Type   Bind Vis      Ndx Name
   28   0: 00011920     0 NOTYPE  GLOBAL DEFAULT ABS __end__
   20   0: 00008940     0 FUNC    GLOBAL DEFAULT UND strncmp
   16   0: 00008928     0 FUNC    GLOBAL DEFAULT UND fseek
   39   1: 00000000     0 NOTYPE  WEAK   DEFAULT UND _Jv_RegisterClasses
   29   1: 00008994     0 FUNC    GLOBAL DEFAULT UND strcmp
   40   3: 000089dc     0 FUNC    GLOBAL DEFAULT UND gcry_md_ctl
   10   5: 000088ec     0 FUNC    GLOBAL DEFAULT UND __fgetc_unlocked
   32   9: 00011910     4 OBJECT  GLOBAL DEFAULT bad stderr
   38  11: 000089d0     0 FUNC    GLOBAL DEFAULT UND fputs
   23  14: 00008964     0 FUNC    GLOBAL DEFAULT UND fread
    2  14: 00011920     0 NOTYPE  GLOBAL DEFAULT ABS _bss_end__
    1  15: 00008898     0 FUNC    GLOBAL DEFAULT UND printf
   44  16: 00008a0c     0 FUNC    GLOBAL DEFAULT UND gcry_md_get_algo_dlen
   41  16: 000089e8     0 FUNC    GLOBAL DEFAULT UND close
    9  17: 000088e0     0 FUNC    GLOBAL DEFAULT UND lseek
   33  18: 00011910     0 NOTYPE  GLOBAL DEFAULT ABS _edata
   13  19: 00008874     0 FUNC    GLOBAL DEFAULT bad _init
    7  19: 000088c8     0 FUNC    GLOBAL DEFAULT UND gcry_md_open
    6  19: 000088bc     0 FUNC    GLOBAL DEFAULT UND gcry_md_write
    3  20: 000088a4     0 FUNC    GLOBAL DEFAULT UND gcry_check_version
   37  21: 000089c4     0 FUNC    GLOBAL DEFAULT UND open
   22  21: 00008958     0 FUNC    GLOBAL DEFAULT UND sscanf
   19  21: 00008934     0 FUNC    GLOBAL DEFAULT UND read
   12  23: 00008904     0 FUNC    GLOBAL DEFAULT UND gcry_mpi_scan
    4  23: 000088b0     0 FUNC    GLOBAL DEFAULT UND malloc
   27  24: 00008988     0 FUNC    GLOBAL DEFAULT UND gcry_md_read
   42  25: 000089f4     0 FUNC    GLOBAL DEFAULT UND gcry_pk_verify
   30  25: 0000936c     0 FUNC    GLOBAL DEFAULT bad _fini
   26  28: 0000897c     0 FUNC    GLOBAL DEFAULT UND ftell
   36  29: 000089b8     0 FUNC    GLOBAL DEFAULT UND strlen
   35  29: 000089ac     0 FUNC    GLOBAL DEFAULT UND exit
   18  29: 00008a18    80 FUNC    GLOBAL DEFAULT bad _start
   14  30: 00008910     0 FUNC    GLOBAL DEFAULT UND gcry_sexp_build
    8  30: 000088d4     0 FUNC    GLOBAL DEFAULT UND ftruncate
   43  31: 00008a00     0 FUNC    GLOBAL DEFAULT UND free
   34  31: 00011920     0 NOTYPE  GLOBAL DEFAULT ABS _end
   31  31: 000089a0     0 FUNC    GLOBAL DEFAULT UND fgetc
   17  31: 00011920     0 NOTYPE  GLOBAL DEFAULT ABS __bss_end__
    5  31: 00011910     0 NOTYPE  GLOBAL DEFAULT ABS __bss_start__
   21  32: 0000894c     0 FUNC    GLOBAL DEFAULT UND fdo pen
   15  33: 0000891c     0 FUNC    GLOBAL DEFAULT UND fprintf
   11  33: 000088f8     0 FUNC    GLOBAL DEFAULT UND abort
   25  35: 00011910     0 NOTYPE  GLOBAL DEFAULT ABS __bss_start
   24  35: 00008970     0 FUNC    GLOBAL DEFAULT UND __uClibc_main
```

To generate an initial gdb (Gnu Debugger) script that puts a breakpoint on each library call it is possible to use the script  `dvaemu/qemu-run/gen-breakpoints.sh`; this script get information from the previous command.

The generated gdb script has been refined with some macros and commands to run when certain breakpoints are hit and is available in `dvaemu/qemu-run/sv.gdb`; this script will be used in the debugging session.

### Starting the emulated Machine

The guest emulated machine is started with the script `qr` in the `qemu-run` folder, this script launches `qemu-system-arm` with:

  * the emulated board *vexpress-a9*
  * the cpu *ARM cortex A9*
  * 1Gb of RAM
  * the file system generated by *buildroot* in an emulated *SD card*
  * port forwarding from host to the guest on port 22 (to be used by `ssh`) and on port 9000 (to be used by `gdb` on the host and `gdbserver` on the guest)

```
valerio@ubuntu-hp:~/br/buildroot-armv7/qemu-run$ ./qr
...
Uncompressing Linux... done, booting the kernel.
Booting Linux on physical CPU 0
Initializing cgroup subsys cpuset
Linux version 3.4.11-rt19 (valerio@BRHOST) (gcc version 4.8.2 (Buildroot 2014.02) ) #1 SMP PREEMPT Sat Sep 15 18:21:45 UTC 2018
CPU: ARMv7 Processor [410fc090] revision 0 (ARMv7), cr=10c53c7d

...

input: ImExPS/2 Generic Explorer Mouse as /devices/motherboard.1/iofpga.2/10007000.kmi/serio1/input/input1
VFS: Mounted root (ext2 filesystem) on device 179:0.
devtmpfs: mounted
Freeing init memory: 160K
smsc911x 4e000000.ethernet: eth0: SMSC911x/921x identified at 0xc0880000, IRQ: 47

Welcome to Buildroot
buildroot login: root
root@buildroot:~#
```

### Starting `gdbserver` on the emulated Machine

The `post-build.sh` script has copied:
  * the DVA 5592 root file system in the folder `/dva-root` in the emulated machine
  * the firmware file `DVA-5592_A1_WI_20180405.sig` and jffs file system images in the folder `/dva-firm`
So the `sig_verify` executable is located in `/dva-root/usr/sbin/sig_verify`. The `gdbserver` is launched with the following commands in the qemu virtual machine, the option `--readonly` is used to disallow trimming the last 256 bytes off the firmware file:

```
root@buildroot:/# cd /dva-root/usr/sbin/
root@buildroot:/dva-root/usr/sbin# gdbserver :9000 sig_verify --readonly /dva-fir
m/DVA-5592_A1_WI_20180405.sig
Process sig_verify created; pid = 511
Listening on port 9000
```

### Starting `gdb` in the host machine

The `gdb` in the host machine is started with the script `gdbrun.sh` in the `qemu-run` folder, this script:
  * sets some environment variables
  * sets the gdb SYSROOT directory (to locate, unstripped binaries generated by buildroot)
  * add the current directory (`dvaemu/qemu-run`) and the host tools directory (where `arm-linux-gdb` is located) to the list of directories where to search sources and gdb scripts
  * set the remote target address/port and starts `gdb` with the arguments given to the script.

```
valerio@ubuntu-hp:~/br/buildroot-armv7/qemu-run$ ./gdbrun.sh -x sv.gdb
GNU gdb (GDB) 7.5.1
Copyright (C) 2012 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "--host=x86_64-unknown-linux-gnu --target=arm-buildroot-linux-uclibcgnueabihf".
For bug reporting instructions, please see:
<http://www.gnu.org/software/gdb/bugs/>.
Remote debugging using :9000
0x76ff1e3c in ?? ()
Reading symbols from /home/valerio/dva-5592/mirror-nas-dva/br-dva-emu/buildroot-2014.02/output/target/lib/ld-uClibc.so.0...done.
Loaded symbols for /home/valerio/dva-5592/mirror-nas-dva/br-dva-emu/buildroot-2014.02/output/target/lib/ld-uClibc.so.0
Source directories searched: /home/valerio/br/buildroot-armv7/qemu-run:$cdir:$cwd
Function "__fgetc_unlocked" not defined.
Breakpoint 1 (__fgetc_unlocked) pending.

...

warning: Could not load shared library symbols for sig_verify.
Do you need "set solib-search-path" or "set sysroot"?

Breakpoint 2, __uClibc_main (main=0x8fac, argc=3, argv=0x7efffd64, app_init=0x8874, app_fini=0x936c, rtld_fini=0x76ff1dd0 <_dl_fini>, stack_end=0x7efffd64)
    at libc/misc/internals/__uClibc_main.c:325
325	{
$1 = "----->Arguments<-----"
$2 = 0x7efffe61 "sig_verify"
$3 = 0x7efffe6c "--readonly"
$4 = 0x7efffe77 "/dva-firm/DVA-5592_A1_WI_20180405.sig"
Breakpoint 32 at 0x76ff26d0: file ldso/ldso/dl-hash.c, line 276.
```

The `sv.gdb` script is executed, it puts breakpoints on external library functions and start the debugging session issuing a `continue` gdb command.

The remote executable stops at the `__uClibc_main` library function and gdb executes the related breakpoint commands printing the 3 arguments of this function that are the option *--readonly*, the name of the executable and the name of the firmware file to check that it has a valid signature.

The `continue` command executes the program till the next breakpoint:

```
Breakpoint 32, _dl_find_hash (name=name@entry=0x85c6 "open", scope=0x76ffd06c, mytpnt=0x76ffd030, type_class=type_class@entry=1, sym_ref=sym_ref@entry=0x0)
    at ldso/ldso/dl-hash.c:276
276	{
_dl_linux_resolver (tpnt=<optimized out>, reloc_entry=<optimized out>) at ldso/ldso/arm/elfinterp.c:74
74		if (unlikely(!new_addr)) {
Value returned is $5 = 0x76eef630 <open> "(\300\037\345\f\300\237", <incomplete sequence \347>
Breakpoint 33 at 0x76eef630: file libpthread/nptl/sysdeps/unix/sysv/linux/open.S, line 8.
```

In the `gv.gdb` file there are breakpoints on  *open* and *read* functions, but, unfortunately, these breakpoints are never hit; this is due to the way *uClibc* manage calls to these functions. For this reason a breakpoint has been put on the *_dl_find_hash* function, with a condition to pause only when the name to lookup is *open* or *read*; when this happens, the associated commands, give a `finish` gdb command and then put a breakpoint on the return value of this function to put a breakpoint on the real *open* function. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 33, 0x76eef630 in open () at libpthread/nptl/sysdeps/unix/sysv/linux/open.S:8
8	PSEUDO (__libc_open, open, 3)
----->filename: /dva-firm/DVA-5592_A1_WI_20180405.sig
----->filemode: 2
```

The program opens the firmware file. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 23, __GI_lseek (fildes=4, offset=0, whence=2) at libc/sysdeps/linux/common/lseek.c:14
14	_syscall3(__off_t, lseek, int, fildes, __off_t, offset, int, whence)
$6 = "----->whence=2:  SEEK_END The offset is set to the size of the file plus offset bytes"
(gdb) finish
Run till exit from #0  __GI_lseek (fildes=4, offset=0, whence=2) at libc/sysdeps/linux/common/lseek.c:14
Cannot access memory at address 0x0
Cannot access memory at address 0x0
0x0000905c in ?? ()
Value returned is $7 = 24388793
```

The program execute an *lseek* library function to position the file offset pointer to the end of the firmware file, this is done to get the return value, that points to the last byte of this file and gives the length of the file: 24,388,793 is exactly the length of `DVA-5592_A1_WI_20180405.sig`. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 23, __GI_lseek (fildes=4, offset=24388537, whence=0) at libc/sysdeps/linux/common/lseek.c:14
14	_syscall3(__off_t, lseek, int, fildes, __off_t, offset, int, whence)
$8 = "----->whence=0:  SEEK_SET The offset is set to offset bytes"
```

This time the *lseek* library function positions the file offset pointer to the end of the file minus 256 bytes. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 32, _dl_find_hash (name=name@entry=0x8603 "read", scope=0x76ffd06c, mytpnt=0x76ffd030, type_class=type_class@entry=1, sym_ref=sym_ref@entry=0x0)
    at ldso/ldso/dl-hash.c:276
276	{
_dl_linux_resolver (tpnt=<optimized out>, reloc_entry=<optimized out>) at ldso/ldso/arm/elfinterp.c:74
74		if (unlikely(!new_addr)) {
Value returned is $9 = 0x76eef750 <read> "(\300\037\345\f\300\237", <incomplete sequence \347>
Breakpoint 34 at 0x76eef750: file libpthread/nptl/sysdeps/unix/sysv/linux/read.S, line 8.
```

This breakpoint at `dl_find_hash`, whit *read* as name parameter, and the associated commands has the purpose to put a breakpoint at the return value of the function that points to the real address of the *read* library function. This brakpoint is no more needed and can be remove with `delete 32`. The `continue` command executes the program till the next breakpoint:

```
(gdb) delete 32
(gdb) continue
Continuing.

Breakpoint 34, 0x76eef750 in read () at libpthread/nptl/sysdeps/unix/sysv/linux/read.S:8
8	PSEUDO (__libc_read, read, 3)
----->filedesc: 4
----->buf:    0x12008
----->len:      256
$10 = "----->Bytes read and stored in buf (truncated at 256 bytes max)<-----"
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x00008dc8 in ?? ()
00000000: 9f4a 8277 8e5f 763b 3e34 6e21 6c13 d4af  .J.w._v;>4n!l...
00000010: 076d 073f 5e34 5fc1 3824 5c4b 9f28 5481  .m.?^4_.8$\K.(T.
00000020: 0a1b 5fdc 5333 ddd2 0fb9 0bdb 5c9f 7ea0  .._.S3......\.~.
00000030: 0114 831a ed51 a0a1 0bdc b130 f6ff cc42  .....Q.....0...B
00000040: 15b9 da23 5b7c 3ef7 5243 3cf2 4ca5 f8da  ...#[|>.RC<.L...
00000050: 9dbe fbd1 10d9 1551 412b d22e bfd3 c338  .......QA+.....8
00000060: a035 b9c6 11e1 7ec3 d19f 8c23 136f 0038  .5....~....#.o.8
00000070: 537d cb42 75ad c8b2 5ea4 ad18 d474 0646  S}.Bu...^....t.F
00000080: d273 9cbe 0182 7cb4 fb47 3044 7a3f 64e1  .s....|..G0Dz?d.
00000090: bb31 1142 6f47 b57b 7e72 0bb3 78ab d728  .1.BoG.{~r..x..(
000000a0: f226 83aa e849 7c81 736e 80f4 94ee 8b83  .&...I|.sn......
000000b0: fe50 9071 a29d e9de b7d4 b27d 8f2d 08fc  .P.q.......}.-..
000000c0: 0b26 853b 1629 9257 f3ff 7f8d ae10 3440  .&.;.).W......4@
000000d0: 1cd4 5d41 4b7c 45b2 54e2 2958 9474 2ff9  ..]AK|E.T.)X.t/.
000000e0: 8d1d 20cf 7e5e ea17 973d a8b0 64ed 8b67  .. .~^...=..d..g
000000f0: b1cd 67dc 48a2 08bf 5b79 a3e4 e51f e1a7  ..g.H...[y......
```

The program stops at the *read* function and, as expected after the *lseek* function, it reads the last 256 bytes of the firmware file. It is easy to verify that these are exactly the last 256 bytes of the file with the command  on the host `xxd -s 24388537 DVA-5592_A1_WI_20180405.sig`.

Why the program reads the last 256 bytes first? Probably because these 256 bytes are the signature to verify. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 23, __GI_lseek (fildes=4, offset=0, whence=0) at libc/sysdeps/linux/common/lseek.c:14
14	_syscall3(__off_t, lseek, int, fildes, __off_t, offset, int, whence)
$11 = "----->whence=0:  SEEK_SET The offset is set to offset bytes"
```

The program calls *lseek* to position the file offset pointer at the beginning of the file. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 17, gcry_md_open (h=0x7efffb24, algo=2, flags=0) at visibility.c:771
771	  if (!fips_is_operational ())
$12 = "----->algo=2: GCRY_MD_SHA1"
```

The program stops at the *libgcrypt* function *gcry_md_open*, *md* is for *Message Digest* and it is the first function to be called to start the *message digest* computation. The parameter *algo*, equal to 2, select SHA1 message digest, *flags* zero, means no special processing and *h* in an handle to this processing.
The *libgcrypt* is documented in [The Libgcrypt Reference Manual](https://www.gnupg.org/documentation/manuals/gcrypt/). The `continue` command executes the program till the next breakpoint:

```
Breakpoint 33, 0x76eef630 in open () at libpthread/nptl/sysdeps/unix/sysv/linux/open.S:8
8	PSEUDO (__libc_open, open, 3)
----->filename: /etc/TZ
----->filemode: 0
(gdb) cont
Continuing.

Breakpoint 33, 0x76eef630 in open () at libpthread/nptl/sysdeps/unix/sysv/linux/open.S:8
8	PSEUDO (__libc_open, open, 3)
----->filename: /etc/localtime
----->filemode: 0
(gdb) cont
Continuing.

Breakpoint 31, _stdio_fopen (fname_or_mode=1996318136, mode=0x76fd617c "r", stream=0x0, filedes=-2) at libc/stdio/_fopen.c:34
34	{
----->fname_or_mode: /proc/sys/crypto/fips_enabled
(gdb) cont
Continuing.

Breakpoint 33, 0x76eef630 in open () at libpthread/nptl/sysdeps/unix/sysv/linux/open.S:8
8	PSEUDO (__libc_open, open, 3)
----->filename: /proc/sys/crypto/fips_enabled
----->filemode: 131072
(gdb) cont
Continuing.

Breakpoint 16, gcry_md_get_algo_dlen (algo=2) at visibility.c:863
863	  return _gcry_md_get_algo_dlen (algo);
(gdb) finish
Run till exit from #0  gcry_md_get_algo_dlen (algo=2) at visibility.c:863
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x00009180 in ?? ()
Value returned is $13 = 20
```

Some files are opened, presumably by *cgry_md_open*, till the breakpoint 16 where there is a call to  *gcry_md_get_algo_dlen*, this function returns the number of bytes of the digest yielded by the algorithm *algo* (SHA1 in our case), the returned value is 20 bytes, as expected. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 34, 0x76eef750 in read () at libpthread/nptl/sysdeps/unix/sysv/linux/read.S:8
8	PSEUDO (__libc_read, read, 3)
----->filedesc: 4
----->buf:    0x7effdb24
----->len:      8192
$14 = "----->Bytes read and stored in buf (truncated at 256 bytes max)<-----"
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x000091b8 in ?? ()
00000000: 7949 4d47 3100 4d55 4c54 495f 424f 4152  yIMG1.MULTI_BOAR
00000010: 4453 5f49 4400 0000 646c 696e 6b00 0000  DS_ID...dlink...
00000020: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000030: 4456 412d 3535 3932 5f41 315f 5749 5f32  DVA-5592_A1_WI_2
00000040: 3230 3138 2d30 342d 3131 2031 323a 3432  2018-04-11 12:42
00000050: 4d00 0000 3235 3600 0000 0000 0000 3234  M...256.......24
00000060: 3337 3936 3438 0000 0000 0000 0000 0000  379648..........
00000070: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000080: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000090: 4200 0000 3234 3337 3939 3034 0000 3838  B...24379904..88
000000a0: 0000 0000 0000 0000 5000 0000 3234 3337  ........P...2437
000000b0: 3939 3932 0000 3835 3435 0000 0000 0000  9992..8545......
000000c0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000d0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000e0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000f0: c77e 2e79 9194 2f6f 8c88 3b67 7d26 2874  .~.y../o..;g}&(t
```

The first 8192 bytes are read from the firmware file starting at the beginning, as expected based on last *lseek* function call. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 19, gcry_md_write (hd=0x12610, buffer=0x7effdb24, length=8192) at visibility.c:822
822	  if (!fips_is_operational ())
$15 = "----->buffer content (truncated to first 256 bytes)<-----"
00000000: 7949 4d47 3100 4d55 4c54 495f 424f 4152  yIMG1.MULTI_BOAR
00000010: 4453 5f49 4400 0000 646c 696e 6b00 0000  DS_ID...dlink...
00000020: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000030: 4456 412d 3535 3932 5f41 315f 5749 5f32  DVA-5592_A1_WI_2
00000040: 3230 3138 2d30 342d 3131 2031 323a 3432  2018-04-11 12:42
00000050: 4d00 0000 3235 3600 0000 0000 0000 3234  M...256.......24
00000060: 3337 3936 3438 0000 0000 0000 0000 0000  379648..........
00000070: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000080: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000090: 4200 0000 3234 3337 3939 3034 0000 3838  B...24379904..88
000000a0: 0000 0000 0000 0000 5000 0000 3234 3337  ........P...2437
000000b0: 3939 3932 0000 3835 3435 0000 0000 0000  9992..8545......
000000c0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000d0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000e0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000f0: c77e 2e79 9194 2f6f 8c88 3b67 7d26 2874  .~.y../o..;g}&(t
```

The pointer to the read buffer and his length is passed to the *gcry_md_write* function to update the digest value. These file reads and call to *gcry_md_write* function will continue till the end of the firmware file minus the 256 bytes of the signature. So we can expect (file size - 256)/length calls to *open* and to *gcry_md_write*: `(24,388,793 - 256) / 8,192 = 2,977.116333` this means 2,977 reads of 8,192 bytes plus one read of 953 bytes. To move forward to the end of the file reads disable the breakpoint 34 (on *read* function) and stop at the 2,977nth read (one read already done):

```
(gdb) disable 34
(gdb) continue 2976
Will ignore next 2975 crossings of breakpoint 19.  Continuing.

Breakpoint 19, gcry_md_write (hd=0x12610, buffer=0x7effdb24, length=8192) at visibility.c:822
822	  if (!fips_is_operational ())
$16 = "----->buffer content (truncated to first 256 bytes)<-----"
00000000: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000010: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000020: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000030: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000040: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000050: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000060: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000070: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000080: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000090: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000a0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000b0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000c0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000d0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000e0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000f0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
(gdb) cont
Continuing.

Breakpoint 19, gcry_md_write (hd=0x12610, buffer=0x7effdb24, length=953) at visibility.c:822
822	  if (!fips_is_operational ())
$17 = "----->buffer content (truncated to first 256 bytes)<-----"
00000000: 6262 f6da c21f a25d 47e5 9c3d 556c 1243  bb.....]G..=Ul.C
00000010: 6f2a c659 9804 e958 d868 7ae9 db8b 8bfb  o*.Y...X.hz.....
00000020: 44f3 aa1c 81c8 db5e 27e6 e0c0 e55a ac69  D......^'....Z.i
00000030: 4899 46c7 b486 47f8 79fb 477e e03a e0b6  H.F...G.y.G~.:..
00000040: 1df1 994c c9f3 5c67 3264 e4af 057b 437f  ...L..\g2d...{C.
00000050: 5c68 d1df 5b18 eaa0 3c38 72a3 c145 cdc6  \h..[...<8r..E..
00000060: 34d6 ba4b 1156 dfff 069b 0cec 2e5b 82ec  4..K.V.......[..
00000070: 2c8a c7be 89b5 4c16 2414 937a 454b 9469  ,.....L.$..zEK.i
00000080: fe85 ae1c 05db ca4f b5d9 a982 49a8 e9d1  .......O....I...
00000090: 88c2 3176 4195 8653 5e17 ab43 cdb4 0a0f  ..1vA..S^..C....
000000a0: 4454 9d2b 1983 7db5 ae59 5d21 60e3 cdba  DT.+..}..Y]!`...
000000b0: d2b4 94c2 f88f 1ee2 484b 6b1d e88a d3fe  ........HKk.....
000000c0: fd61 e1fd afcd b927 f02b d845 8f85 eb7c  .a.....'.+.E...|
000000d0: 8ab7 bebd 07c3 881a a847 1a23 8929 0f82  .........G.#.)..
000000e0: 67f6 b777 0841 d2db 4e1d cc26 83db d772  g..w.A..N..&...r
000000f0: 7d9d ae52 4af6 056a 74ce 620a d3f6 fc9a  }..RJ..jt.b.....
```

As expected the last read is of the last 953 bytes of the firmware file, before the 256 bytes of signature. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 15, gcry_md_ctl (hd=0x12610, cmd=5, buffer=0x0, buflen=0) at visibility.c:814
814	  if (!fips_is_operational ())
$18 = "----->cmd=5: GCRYCTL_FINALIZE"
```

The program stops at the *gcry_md_ctl* function to finalize the message digest computation. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 18, gcry_md_read (hd=0x12610, algo=2) at visibility.c:833
833	  return _gcry_md_read (hd, algo);
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x0000920c in ?? ()
Value returned is $19 = (unsigned char *) 0x12a70 "&\372\344|\200\264\035kk\274lM2\213v\366O\365\345+"
$20 = "-----> Message Digest <-----"
0x12a70:	0x26	0xfa	0xe4	0x7c	0x80	0xb4	0x1d	0x6b
0x12a78:	0x6b	0xbc	0x6c	0x4d	0x32	0x8b	0x76	0xf6
0x12a80:	0x4f	0xf5	0xe5	0x2b
```

The program calls *gcry_md_read* to read the 20 bytes of the SHA1 message digest, the returned value is exactly the SHA1 message digest of the firmware file minus the last 256 bytes. It is easy to verify that this is exactly the SHA1 of the firmware file, minus the 256 bytes, with the command in the host (takes some time):

```
valerio@ubuntu-hp:~/$ dd if=DVA-5592_A1_WI_20180405.sig  bs=1 count=24388537 | sha1sum -
24388537+0 records in
24388537+0 records out
24388537 bytes (24 MB, 23 MiB) copied, 39,1201 s, 623 kB/s
26fae47c80b41d6b6bbc6c4d328b76f64ff5e52b  -
```
The `continue` command, in the debugging session, executes the program till the next breakpoint:

```
Breakpoint 14, gcry_check_version (req_version=0x0) at visibility.c:68
68	  return _gcry_check_version (req_version);
```

The *gcry_check_version* initialize some subsystems used by Libgcrypt and must be invoked before any other crypto functions. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 22, gcry_sexp_build (retsexp=0x7efffb24, erroff=0x0, format=0x9634 "(data (flags pkcs1) (hash sha1 %b))") at visibility.c:114
114	  va_start (arg_ptr, format);
115	  err = _gcry_sexp_vbuild (retsexp, erroff, format, arg_ptr);
(gdb) bprint
----->arg_ptr: 0x7efffb04
$21 = "----->%b variable<-----"
----->   len: 14
----->   buf: 12a70
$22 = "----->buffer<-----"
00000000: 26fa e47c 80b4 1d6b 6bbc 6c4d 328b 76f6  &..|...kk.lM2.v.
00000010: 4ff5 e52b                                O..+
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x00009270 in ?? ()
Value returned is $22 = 0
-----> *retsexp: 0x12ab8
```

The program stops at the *gcry_sexp_build* used to build an internal representation of an s-expression used in public/private key computations. In the `sv.gdb` there is the macro `bprint` to print the `%b` argument, based on Libgcrypt documentation. It is easy to spot that this s-expression is the SHA1 message digest of the file, minus the last 256 bytes. The handle (`*retsexp`) of this s-expression is **0x12ab8**. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 22, gcry_sexp_build (retsexp=0x7efffb20, erroff=0x0, format=0x967b "(sig-val (rsa (s %b)))") at visibility.c:114
114	  va_start (arg_ptr, format);
115	  err = _gcry_sexp_vbuild (retsexp, erroff, format, arg_ptr);
(gdb) bprint
----->arg_ptr: 0x7efffb04
$24 = "----->%b variable<-----"
----->   len: 100
----->   buf: 12008
$25 = "----->buffer<-----"
00000000: 9f4a 8277 8e5f 763b 3e34 6e21 6c13 d4af  .J.w._v;>4n!l...
00000010: 076d 073f 5e34 5fc1 3824 5c4b 9f28 5481  .m.?^4_.8$\K.(T.
00000020: 0a1b 5fdc 5333 ddd2 0fb9 0bdb 5c9f 7ea0  .._.S3......\.~.
00000030: 0114 831a ed51 a0a1 0bdc b130 f6ff cc42  .....Q.....0...B
00000040: 15b9 da23 5b7c 3ef7 5243 3cf2 4ca5 f8da  ...#[|>.RC<.L...
00000050: 9dbe fbd1 10d9 1551 412b d22e bfd3 c338  .......QA+.....8
00000060: a035 b9c6 11e1 7ec3 d19f 8c23 136f 0038  .5....~....#.o.8
00000070: 537d cb42 75ad c8b2 5ea4 ad18 d474 0646  S}.Bu...^....t.F
00000080: d273 9cbe 0182 7cb4 fb47 3044 7a3f 64e1  .s....|..G0Dz?d.
00000090: bb31 1142 6f47 b57b 7e72 0bb3 78ab d728  .1.BoG.{~r..x..(
000000a0: f226 83aa e849 7c81 736e 80f4 94ee 8b83  .&...I|.sn......
000000b0: fe50 9071 a29d e9de b7d4 b27d 8f2d 08fc  .P.q.......}.-..
000000c0: 0b26 853b 1629 9257 f3ff 7f8d ae10 3440  .&.;.).W......4@
000000d0: 1cd4 5d41 4b7c 45b2 54e2 2958 9474 2ff9  ..]AK|E.T.)X.t/.
000000e0: 8d1d 20cf 7e5e ea17 973d a8b0 64ed 8b67  .. .~^...=..d..g
000000f0: b1cd 67dc 48a2 08bf 5b79 a3e4 e51f e1a7  ..g.H...[y......
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x00009294 in ?? ()
Value returned is $25 = 0
-----> *retsexp: 0x12b20
```

The program stops again at the *gcry_sexp_build*, but this time the s-expression is the signature (last 256 bytes of the firmware file). The handle of this s-expression is **0x12b20**.  The `continue` command executes the program till the next breakpoint:

```
Breakpoint 20, gcry_mpi_scan (ret_mpi=0x7efffb18, format=GCRYMPI_FMT_USG, buffer=0x937c, buflen=3, nscanned=0x0) at visibility.c:299
299	  return _gcry_mpi_scan (ret_mpi, format, buffer, buflen, nscanned);
$26 = "----->buffer content<-----"
00000000: 0100 01                                  ...
(gdb) dump binary memory exponent.bin buffer buffer+buflen
```

The program stops at the *gcry_mpi_scan* function that is used to store an internal representation of an MPI (Multi Precision Integer) passed as parameter. In this case the MPI is a not so big integer, probably it is the *exponent* (the public key contains two MPIs: the exponent and the modulus). For later use this MPI is saved in the file `exponent.bin`. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 20, gcry_mpi_scan (ret_mpi=0x7efffb14, format=GCRYMPI_FMT_USG, buffer=0x94d3, buflen=256, nscanned=0x0) at visibility.c:299
299	  return _gcry_mpi_scan (ret_mpi, format, buffer, buflen, nscanned);
$27 = "----->buffer content<-----"
00000000: cd95 2148 7977 6b6d 68ce ae09 7148 e9d5  ..!Hywkmh...qH..
00000010: 38b9 9f74 e7cf 7b25 ea48 7e74 af5a 28b2  8..t..{%.H~t.Z(.
00000020: 6162 c9e0 f35d 3dfe 6a41 20b5 7f13 e9db  ab...]=.jA .....
00000030: 3972 eaac 6af6 2492 abaf 38c0 6756 e0f7  9r..j.$...8.gV..
00000040: 86e9 5d01 30c9 5098 09e4 457a 8eb5 7ef1  ..].0.P...Ez..~.
00000050: 7dda 782b ea9a a927 d3f0 d954 52cb 61cf  }.x+...'...TR.a.
00000060: 5cb8 c0e5 214c 21ec ea01 da43 3b76 6813  \...!L!....C;vh.
00000070: 6612 6eba cc5a e680 3ea6 0460 bb4b f5d4  f.n..Z..>..`.K..
00000080: 300c c6cb 7ad6 5f10 bddd ff71 868b 3c8e  0...z._....q..<.
00000090: 6b1e f3fd 0c76 c040 af47 aac1 a0a5 e899  k....v.@.G......
000000a0: 3131 12d1 f658 4264 2e48 0fba 0b65 ba1a  11...XBd.H...e..
000000b0: eace 42a7 2789 e8c7 b968 4c86 7c86 0f93  ..B.'....hL.|...
000000c0: dcbf 3e88 9581 bcc1 ad5b 26bf 0d4c d3e0  ..>......[&..L..
000000d0: eb14 0849 4947 4002 6944 b0c9 014f ab4a  ...IIG@.iD...O.J
000000e0: e9d1 b14a 0185 b665 4b54 6545 72ea e898  ...J...eKTeEr...
000000f0: b020 1bee 011c ea31 5f5f 9919 9b2a bf9f  . .....1__...*..
(gdb) dump binary memory modulus.bin buffer buffer+buflen
```

The program stops again at the *gcry_mpi_scan* function, but this time to store the *modulus*, the second, and last, MPI associated to the public key.  For later use this MPI is saved in the file `modulus.bin`. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 22, gcry_sexp_build (retsexp=0x7efffb1c, erroff=0x0, format=0x96d8 "(public-key (rsa (n %m) (e %m)))") at visibility.c:114
114	  va_start (arg_ptr, format);
115	  err = _gcry_sexp_vbuild (retsexp, erroff, format, arg_ptr);
(gdb) mpiprint
----->arg_ptr: 0x7efffb04
$28 = "----->gcry_mpi_t variable nr. 1<-----"
$29 = {alloced = 0x40, nlimbs = 0x40, sign = 0x0, flags = 0x0, d = 0x12d88}
$30 = "----->MPI Multi Precision Integer"
00000000: 9fbf 2a9b 1999 5f5f 31ea 1c01 ee1b 20b0  ..*...__1..... .
00000010: 98e8 ea72 4565 544b 65b6 8501 4ab1 d1e9  ...rEeTKe...J...
00000020: 4aab 4f01 c9b0 4469 0240 4749 4908 14eb  J.O...Di.@GII...
00000030: e0d3 4c0d bf26 5bad c1bc 8195 883e bfdc  ..L..&[......>..
00000040: 930f 867c 864c 68b9 c7e8 8927 a742 ceea  ...|.Lh....'.B..
00000050: 1aba 650b ba0f 482e 6442 58f6 d112 3131  ..e...H.dBX...11
00000060: 99e8 a5a0 c1aa 47af 40c0 760c fdf3 1e6b  ......G.@.v....k
00000070: 8e3c 8b86 71ff ddbd 105f d67a cbc6 0c30  .<..q...._.z...0
00000080: d4f5 4bbb 6004 a63e 80e6 5acc ba6e 1266  ..K.`..>..Z..n.f
00000090: 1368 763b 43da 01ea ec21 4c21 e5c0 b85c  .hv;C....!L!...\
000000a0: cf61 cb52 54d9 f0d3 27a9 9aea 2b78 da7d  .a.RT...'...+x.}
000000b0: f17e b58e 7a45 e409 9850 c930 015d e986  .~..zE...P.0.]..
000000c0: f7e0 5667 c038 afab 9224 f66a acea 7239  ..Vg.8...$.j..r9
000000d0: dbe9 137f b520 416a fe3d 5df3 e0c9 6261  ..... Aj.=]...ba
000000e0: b228 5aaf 747e 48ea 257b cfe7 749f b938  .(Z.t~H.%{..t..8
000000f0: d5e9 4871 09ae ce68 6d6b 7779 4821 95cd  ..Hq...hmkwyH!..
$31 = "----->", '-' <repeats 25 times>, "<-----"
$32 = "----->gcry_mpi_t variable nr. 2<-----"
$33 = {alloced = 0x1, nlimbs = 0x1, sign = 0x0, flags = 0x0, d = 0x12d60}
$34 = "----->MPI Multi Precision Integer"
00000000: 0100 0100                                ....
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x00009314 in ?? ()
Value returned is $35 = 0
-----> *retsexp: 0x12e90
```

The programs stops at the *gcry_sexp_build* to build the third, and last, s-expression. This s-expression is the *Public Key* s-expression. The macro `mpiprint` prints the two mpi in `%m` format and it is easy to spot that this are the modulus and the exponent, but written in reverse byte order because the internal representation put most significant bytes first. The handle of this s-expression is **0x12e90***. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 21, gcry_pk_verify (sigval=0x12b20, data=0x12ab8, pkey=0x12e90) at visibility.c:666
666	  if (!fips_is_operational ())
(gdb) finish
Run till exit from #0  gcry_pk_verify (sigval=0x12b20, data=0x12ab8, pkey=0x12e90) at visibility.c:666
Cannot access memory at address 0x17424b9
Cannot access memory at address 0x17424b9
0x00009330 in ?? ()
Value returned is $35 = 0
```

The program call the *gcry_pk_verify* function that take as parameters:
 * sigval, the signature s-expression (**0x12b20**)
 * data, the SHA1 message digest s-expression (**0x12ab8**)
 * pkey, the Public Key s-expression (**0x12e90**)
This function verify if the signature is valid, it returns `0` that means that the signature is valid. The `continue` command executes the program till the next breakpoint:

```
Breakpoint 5, __GI_exit (rv=0) at libc/stdlib/_atexit.c:338
338	{
(gdb) continue
Continuing.
[Inferior 1 (process 511) exited normally]
```

The program stops at the *exit* library calls and exits with `0` as error level meaning that the file signature has been successfully verified.

### Generate a Public Key file in *pem* format with the MPIs in `sig_verify`

At breakpoint 20, hit two times, the MPIs (Multi Precision Integers) of the Public Key have been saved on file `exponent.bin` and `modulus.bin`; using these MPIs it is possible to generate a Public Key in a standard PEM or DER format; to do so there is the script `pub-key/pubkey-gen.sh` that, using openssl and an ASN1 template, generate the Public Key files `pub-key/pubkey.der` and `pub-key/pubkey.pem` with the following commands:

```
valerio@ubuntu-hp:~/dva-5592/mirror-nas-dva/br-dva-emu/dvaemu$ cd pub-key/
valerio@ubuntu-hp:~/br/buildroot-armv7/pub-key$ ./pubkey-gen.sh pubkey-def.asn1 ../qemu-run/modulus.bin ../qemu-run/exponent.bin
modsize: 256
expsize: 3
writing RSA key
valerio@ubuntu-hp:~/br/buildroot-armv7/pub-key$ ls -l pubkey.der pubkey.pem
-rwxr-xr-x 1 valerio valerio 294 set 21 22:41 pubkey.der
-rwxr-xr-x 1 valerio valerio 451 set 21 22:41 pubkey.pem
```

### `mysig_verify`: a script that does the same job as `sig_verify`

The script `pub-key/mysig_verify`, using *openssl* and the Public Key in *pem* format, generated in the previous paragraph, does exactly the same job of `sig_verify`: it checks if the file, passed as argument, has a valid signature:

```
valerio@ubuntu-hp:~/dva-5592/mirror-nas-dva/br-dva-emu/dvaemu$ cd pub-key/
valerio@ubuntu-hp:~/br/buildroot-armv7/pub-key$ ./mysig_verify.sh ~/mod-kit/input/DVA
DVA-5592_A1_WI_20180405.sig  DVA.con                      DVA.sig                      
valerio@ubuntu-hp:~/br/buildroot-armv7/pub-key$ ./mysig_verify.sh ~/mod-kit/input/DVA-5592_A1_WI_20180405.sig
Verified OK
valerio@ubuntu-hp:~/br/buildroot-armv7/pub-key$
```

### Conclusion on reverse engineering `sig_verify`

The executable `sig_verify` has no debugging information and is stripped, but following many of the library calls it makes, it has been possible to completely understand what it is doing and it has been possible to make a script, using *openssl* that does exactly the same job. The reverse engineering process has been successfully completed.

Unfortunately this success has not given a solution to the problem of creating a firmware file that can be successfully loaded into the router because, without the Private Key, it is not possible to successfully sign an unofficial firmware.

In the folder `/etc/certs/` of the router there are some Private Key files but none of them correspond to the Public Key embedded in the `sig_verify` executable.

Checking all the files, in the router root file system, to find the binary sequence of the MPI modulus it is possible to find the these MPIs are embedded in the boot loader and in the package manager `opkg`; this package manager is used, locally, in the last phase of the firmware update. This probably means that both the kernel and the packages added at the end of the firmware upgrade process are signed with the supplier's private key.
