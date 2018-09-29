#!/bin/sh
#
# the following line simulate a NAND Flash with 256MBbytes, 2048 bytes per page, 128Kb erasesize
# 7 partitions are created, as in the DVA 5592 router, with the size described below
#
modprobe nandsim first_id_byte=0x20 second_id_byte=0xaa third_id_byte=0x00 fourth_id_byte=0x15 parts=1,16,982,998,16,2,16
#
flash_erase /dev/mtd1 0   1   # 128K CFE
flash_erase /dev/mtd2 0  16   #   2M bootfs_1
flash_erase /dev/mtd3 0 982   # 122M rootfs_1
flash_erase /dev/mtd4 0 998   # 124M upgrade
flash_erase /dev/mtd5 0  16   #   2M conf_fs
flash_erase /dev/mtd6 0   2   # 256K conf_factory
flash_erase /dev/mtd7 0  16   #   2M bbt
