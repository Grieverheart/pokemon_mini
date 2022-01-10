#!/bin/bash
$VERILATOR_ROOT/bin/verilator -O3 -Wno-fatal -trace --top-module 's1c88' -I.. --cc ../rtl/s1c88.sv --exe s1c88_sim.cpp
#verilator -O3 -Wno-fatal -trace --top-module 's1c88' -I.. --cc ../s1c88.sv --exe s1c88_sim.cpp
