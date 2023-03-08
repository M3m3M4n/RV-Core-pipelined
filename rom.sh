#!/bin/bash

set -e # exit if any cmd returns error
scriptpath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
scriptdirectory="$(dirname "$scriptpath")"

if [ $# -eq 1 ] || [ $# -eq 2 ]
then
    targetpath="$(cd "$(dirname "${1}")" && pwd)/$(basename "${1}")"
    targetdirectory="$(dirname "$targetpath")"
    targetfilename="$(basename "$targetpath")"
    targetcfiles="$(find $targetdirectory -maxdepth 1 -type f -name '*.c')"
    targetextension="${targetfilename##*.}"
    targetfilename="${targetfilename%.*}"
    includedirectory="${targetdirectory}/../include"
    includecfiles="$(find $includedirectory -type f -name '*.c')"
    linkerfile="${targetdirectory}/../linker.ld"
    # Allow some functions from libgcc like udiv and umul, stills, do not call printf or smth
    # riscv32-unknown-elf-gcc "$targetcfiles" "$includecfiles" -I "$includedirectory" -T "$linkerfile" -nostdlib -nodefaultlibs -fno-exceptions -nostartfiles -o "$targetdirectory/$targetfilename.o"
    riscv32-unknown-elf-gcc "$targetcfiles" "$includecfiles" -I "$includedirectory" -T "$linkerfile" -fno-exceptions -nostartfiles -o "$targetdirectory/$targetfilename.o"
    # riscv32-unknown-elf-objcopy -I elf32-little -O binary -j .text "$targetdirectory/$targetfilename.o" "$targetdirectory/$targetfilename.tmp"
    riscv32-unknown-elf-objcopy -I elf32-little -O binary "$targetdirectory/$targetfilename.o" "$targetdirectory/$targetfilename.tmp"
    od -v --endian=little -tx4 -An -w4 "$targetdirectory/$targetfilename.tmp" > "$targetdirectory/$targetfilename.txt"
    echo "ROM assembly dumped: $targetdirectory/$targetfilename.txt"
    # rm "$targetdirectory/$targetfilename.o"
    # rm "$targetdirectory/$targetfilename.tmp"
    if [ ! -z "$2" ]
    then
        if [ ! -d "${2}" ]
        then
            echo "ROM target directory ${2} does not exist!"
            exit 1
        else
            cp "$targetdirectory/$targetfilename.txt" "${2}/rom.txt"
            echo "ROM assembly copied: ${2}/rom.txt"
        fi
    fi
else
    echo "Usage: $scriptpath <source> <optional-copy-here-as-rom.txt>"
    exit 1
fi
 
