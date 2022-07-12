#!/bin/bash
python3 ../scripts/generate_microrom.py
#$VERILATOR_ROOT/bin/verilator -O3 -Wno-fatal -trace --top-module minx -I../rtl --cc ../rtl/minx.sv --exe minx_sdl2_sim.cpp -LDFLAGS "-framework OpenGL `sdl2-config  --libs` -lglew"
$VERILATOR_ROOT/bin/verilator -O3 -Wno-fatal -trace --top-module minx -I../rtl --cc ../rtl/minx.sv --exe minx_sdl2_sim.cpp -LDFLAGS "-lGL `sdl2-config  --libs` -lGLEW"
make -C obj_dir/ -f Vminx.mk
