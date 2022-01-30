#include "Vs1c88.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstring>
#include <cstdint>

enum
{
    BUS_IDLE      = 0x0,
    BUS_IRQ_READ  = 0x1,
    BUS_MEM_WRITE = 0x2,
    BUS_MEM_READ  = 0x3
};

uint32_t second_counter = 0;

uint8_t read_hardware_register(uint32_t address)
{
    uint8_t data = 0;
    switch(address)
    {
        case 0x8:
        {
        }
        break;

        default:
        break;
    }
    return data;
}

int main(int argc, char** argv, char** env)
{
    FILE* fp = fopen("data/bios.min", "rb");
    fseek(fp, 0, SEEK_END);
    size_t file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */

    uint8_t* bios = (uint8_t*) malloc(file_size);
    fread(bios, 1, file_size, fp);
    fclose(fp);

    uint8_t* memory = (uint8_t*) malloc(4*1024);

    Verilated::commandArgs(argc, argv);

    Vs1c88* s1c88 = new Vs1c88;
    s1c88->clk = 0;
    s1c88->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    s1c88->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    int mem_counter = 0;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 200 && !Verilated::gotFinish())
    {
        s1c88->clk = 1;
        s1c88->eval();
        tfp->dump(timestamp++);

        s1c88->clk = 0;
        s1c88->eval();
        tfp->dump(timestamp++);

        if(timestamp >= 8)
            s1c88->reset = 0;

        // At rising edge of clock
        if(data_sent)
            data_sent = false;

        //s1c88->eval();
        //tfp->dump(timestamp++);

        if(s1c88->bus_status == BUS_MEM_READ)
        {
            // memory read
            if(s1c88->address_out < 0x1000)
            {
                // read from bios
                s1c88->data_in = *(bios + (s1c88->address_out & (file_size - 1)));
            }
            else if(s1c88->address_out < 0x2000)
            {
                // read from ram
                uint32_t address = s1c88->address_out & 0xFFF;
                s1c88->data_in = *(uint8_t*)(memory + address);
            }
            else if(s1c88->address_out < 0x2100)
            {
                // read from hardware registers
                s1c88->data_in = read_hardware_register(s1c88->address_out & 0x1FFF);
            }
            else
            {
                // read from cartridge
                s1c88->data_in = 0xFA;//*(memory + (s1c88->address_out & 0x003FFF));
            }

            data_sent = true;
        }
        else if(s1c88->bus_status == BUS_MEM_WRITE)
        {
            // memory write
            if(s1c88->address_out < 0x1000)
            {
                printf("Program trying to write to bios!");
            }
            else if(s1c88->address_out < 0x2000)
            {
                // write to ram
                uint32_t address = s1c88->address_out & 0xFFF;
                *(uint8_t*)(memory + address) = s1c88->data_out;
            }
            else if(s1c88->address_out < 0x2100)
            {
                // write to hardware registers
            }
            else
            {
                printf("Program trying to write to cartridge!");
            }

            data_sent = true;
        }
        s1c88->eval();
    }

    tfp->close();
    delete s1c88;

    return 0;
}
