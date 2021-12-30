#!/bin/bash
./build.sh
make -C obj_dir/ -f Vs1c88.mk
./obj_dir/Vs1c88
