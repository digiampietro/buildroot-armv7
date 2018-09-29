
# disable pagination
set height 0

# xxd to do a memory dump similar to xxd shell command
define xxd
  dump binary memory dump.bin $arg0 $arg0+$arg1
  shell xxd dump.bin
end

# print info for the open function
define cmdopen
  printf "----->filename: %s\n",$r0
  printf "----->filemode: %d\n",$r1
end

# print info for the read function
define cmdread
  printf "----->filedesc: %d\n",$r0
  printf "----->buf:    0x%x\n",$r1
  printf "----->len:      %d\n",$r2
  set variable $rbuf=$r1
  set variable $rlen=$r2
  print  "----->Bytes read and stored in buf (truncated at 256 bytes max)<-----"
  if $rlen > 256
    set variable $rlen = 256
  end
  finish
  shell sleep 2
  xxd $rbuf $rlen
end

# print the gcrypt_mpi_t number pointed by arg_ptr in the gcry_sexp_build function (%m)
define mpiprint
  set variable $myp=*(long int *)arg_ptr
  printf "----->arg_ptr: 0x%x\n",(int *)arg_ptr
  print  "----->gcry_mpi_t variable nr. 1<-----"
  print/x *(gcry_mpi_t)$myp
  set variable $mypd=(*(gcry_mpi_t)$myp).d
  set variable $mynd=(*(gcry_mpi_t)$myp).alloced
  print "----->MPI Multi Precision Integer"
  xxd $mypd $mynd
  print  "----->-----.-----.-----.-----.-<-----"
  print  "----->gcry_mpi_t variable nr. 2<-----"
  set variable $myp=*((long int *)arg_ptr + 1)
  print/x *(gcry_mpi_t)$myp
  set variable $mypd=(*(gcry_mpi_t)$myp).d
  set variable $mynd=(*(gcry_mpi_t)$myp).alloced
  print "----->MPI Multi Precision Integer"
  xxd $mypd $mynd
end

# print the %b number pointed by arg_ptr in the gcry_sexp_build function (%b)
define bprint
  set variable $myl=*(long int *)arg_ptr
  printf "----->arg_ptr: 0x%x\n",(int *)arg_ptr
  print  "----->%b variable<-----"
  printf "----->   len: 0x%x\n",*(long int *)arg_ptr
  printf "----->   buf: 0x%x\n",*((long int *)arg_ptr + 1)
  print  "----->buffer<-----"
  set variable $myp=*((long int *)arg_ptr + 1)
  xxd $myp $myl
end

# set breakpoint for the open function in _dl_find_hash
define setbopen
  finish
  break *$r0
  commands
    cmdopen
  end
end

# set breakpoint for the read function in _dl_find_hash
define setbread
  finish
  break *$r0
  commands
    cmdread
  end
  # the breakpoint on _dl_find_hash is no more needed
  print "-----> removing breakpoint on _dl_find_hash"
  clear _dl_find_hash
end

#print the gcrypt_md_read data
define pmdread
  finish
  print "-----> Message Digest <-----"
  x/20bx $r0
end

#save mpi Multi Precision Integer
define savempi
  dump binary memory $arg0 buffer buffer+buflen
end

#print sexp_build related data
define sexpprint
  next
  if format[32] == 'b'
    bprint
  end
  if format[18] == 'b'
    bprint
  end
  if format[21] == 'm'
    mpiprint
  end
  set variable $myretsexp=retsexp
  finish
  printf "-----> *retsexp: 0x%x\n",*$myretsexp
end

set breakpoint pending on

break __fgetc_unlocked

break __uClibc_main
commands
  print "----->Arguments<-----"
  set $i=0
  while $i < argc
    print argv[$i]
    set $i = $i + 1
  end
end

break abort
break close
break exit
break fdopen
break fgetc
break fprintf
break fputs
break fread

#break free

break fseek
break ftell
break ftruncate
break gcry_check_version

break gcry_md_ctl
commands
  print "----->cmd=5: GCRYCTL_FINALIZE"
end

break gcry_md_get_algo_dlen
commands
  finish
end

break gcry_md_open
commands
  if algo == 2
     print "----->algo=2: GCRY_MD_SHA1"
  end
  if algo == 0
     print "----->flag=0: none"
  end
end

break gcry_md_read
commands
  pmdread
end
  

break gcry_md_write
commands
  set variable $rbuf=buffer
  set variable $rlen=length
  if $rlen > 256
    set variable $rlen = 256
  end
  print "----->buffer content (truncated to first 256 bytes)<-----"
  xxd $rbuf $rlen
end

break gcry_mpi_scan
commands
  print "----->buffer content<-----"
  xxd buffer buflen
end

break gcry_pk_verify

break gcry_sexp_build
commands
  sexpprint
end

break lseek
commands
  if whence == 0
     print "----->whence=0:  SEEK_SET The offset is set to offset bytes"
  end
  if whence == 2
     print "----->whence=2:  SEEK_END The offset is set to the size of the file plus offset bytes"
  end
end

#break malloc

break open
break printf
break read
break sscanf

# break strcmp

#break strlen

#break strncmp

break fopen
commands
  x/s fname_or_mode
end


break __GI_open
break __GI_read

#break fcntl
break _stdio_fopen
commands
  printf "----->fname_or_mode: %s\n",fname_or_mode
end
  
continue

break _dl_find_hash if ((char)*name) == 'o' || ((char)*name) == 'r'
commands
  if ((char)*name) == 'o'
    setbopen
  end
  if ((char)*name) == 'r'
    setbread
  end  
end
