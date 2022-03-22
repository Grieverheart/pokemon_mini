#include "Vs1c88.h"
#include "Vs1c88___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstring>
#include <cstdint>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

enum
{
    BUS_IDLE      = 0x0,
    BUS_IRQ_READ  = 0x1,
    BUS_MEM_WRITE = 0x2,
    BUS_MEM_READ  = 0x3
};

uint32_t sec_cnt = 0;
uint8_t sec_ctrl = 0;
uint32_t prc_map = 0;
uint8_t prc_mode = 0;
uint8_t prc_rate = 0;
uint8_t prc_cnt  = 1;
uint8_t prc_rate_match = 0;

uint8_t registers[256] = {};

void write_hardware_register(uint32_t address, uint8_t data)
{
    switch(address)
    {
        case 0x0:
        case 0x1:
        case 0x2:
        {
            printf("Writing hardware register SYS_CTRL%d=", address+1);
        }
        break;

        case 0x8:
        {
            printf("Writing hardware register SEC_CTRL=");
            sec_ctrl = data & 3;
        }
        break;

        case 0x10:
        {
            printf("Writing hardware register SYS_BATT=");
        }
        break;

        case 0x19:
        {
            printf("Writing hardware register TMR1_ENA_OSC/TMR1_OSC=");
        }
        break;

        case 0x20:
        case 0x21:
        case 0x22:
        {
            printf("Writing hardware register IRQ_PRI%d=", address - 0x1F);
        }
        break;

        case 0x23:
        case 0x24:
        case 0x25:
        case 0x26:
        {
            printf("Writing hardware register IRQ_ENA%d=", address - 0x22);
        }
        break;

        case 0x27:
        case 0x28:
        case 0x29:
        case 0x2A:
        {
            printf("Writing hardware register IRQ_ACT%d=", address - 0x26);
            data = registers[address] & ~data;
        }
        break;

        case 0x40:
        {
            printf("Writing hardware register TMR256_CTRL=");
        }
        break;

        case 0x60:
        {
            printf("Writing hardware register IO_DIR=");
        }
        break;

        case 0x61:
        {
            printf("Writing hardware register IO_DATA=");
        }
        break;

        case 0x70:
        {
            printf("Writing hardware register AUD_CTRL=");
        }
        break;

        case 0x71:
        {
            printf("Writing hardware register AUD_VOL=");
        }
        break;

        case 0x80:
        {
            printf("Writing hardware register PRC_MODE=");
            prc_mode = data & 0x3F;
        }
        break;

        case 0x81:
        {
            printf("Writing hardware register PRC_RATE=");
            if((data & 0xE) != (prc_rate & 0xE)) prc_rate = data & 0xF;
            else prc_rate = (prc_rate & 0xF0) | (data & 0x0F);
			switch (prc_rate & 0x0E) {
				case 0x00: prc_rate_match = 0x20; break;	// Rate /3
				case 0x02: prc_rate_match = 0x50; break;	// Rate /6
				case 0x04: prc_rate_match = 0x80; break;	// Rate /9
				case 0x06: prc_rate_match = 0xB0; break;	// Rate /12
				case 0x08: prc_rate_match = 0x10; break;	// Rate /2
				case 0x0A: prc_rate_match = 0x30; break;	// Rate /4
				case 0x0C: prc_rate_match = 0x50; break;	// Rate /6
				case 0x0E: prc_rate_match = 0x70; break;	// Rate /8
            }
            
        }
        break;

        case 0x82:
        {
            printf("Writing hardware register PRC_MAP_LO=");
            prc_map = (prc_map & 0xFFFFF00) | (data & 0xFF);
        }
        break;

        case 0x83:
        {
            printf("Writing hardware register PRC_MAP_MID=");
            prc_map = (prc_map & 0xFFF00FF) | ((data & 0xFF) << 8);
        }
        break;

        case 0x84:
        {
            printf("Writing hardware register PRC_MAP_HI=");
            prc_map = (prc_map & 0xF00FFFF) | ((data & 0xFF) << 16);
        }
        break;

        case 0x85:
        {
            printf("Writing hardware register PRC_SCROLL_Y=");
        }
        break;

        case 0x86:
        {
            printf("Writing hardware register PRC_SCROLL_X=");
        }
        break;

        case 0x87:
        {
            printf("Writing hardware register PRC_SPR_LO=");
        }
        break;

        case 0x88:
        {
            printf("Writing hardware register PRC_SPR_MID=");
        }
        break;

        case 0x89:
        {
            printf("Writing hardware register PRC_SPR_HI=");
        }
        break;

        case 0xFE:
        {
            printf("Writing hardware register LCD_CTRL=");
        }
        break;

        case 0xFF:
        {
            printf("Writing hardware register LCD_DATA=");
        }
        break;

        case 0x44:
        case 0x45:
        case 0x46:
        case 0x47:
        case 0x50:
        case 0x51:
        case 0x54:
        case 0x55:
        case 0x62:
        {
            printf("Writing hardware register Unknown=");
        }
        break;

        default:
        {
            printf("Writing to hardware register 0x%x\n", address);
            return;
        }
    }
    registers[address] = data;
    printf("0x%x\n", data);
}

uint8_t read_hardware_register(uint32_t address)
{
    uint8_t data = registers[address];
    switch(address)
    {
        case 0x0:
        case 0x1:
        case 0x2:
        {
            printf("Reading hardware register SYS_CTRL%d=", address+1);
        }
        break;

        case 0x8:
        {
            printf("Reading hardware register SEC_CTRL=");
            data = sec_ctrl;
        }
        break;

        case 0x9:
        {
            printf("Reading hardware register SEC_CNT_LO=");
            data = sec_cnt & 0xFF;
        }
        break;

        case 0xA:
        {
            printf("Reading hardware register SEC_CNT_MID=");
            data = (sec_cnt >> 8) & 0xFF;
        }
        break;

        case 0xB:
        {
            printf("Reading hardware register SEC_CNT_MID=");
            data = (sec_cnt >> 16) & 0xFF;
        }
        break;

        case 0x10:
        {
            printf("Reading hardware register SYS_BATT=");
        }
        break;

        case 0x52:
        {
            printf("Reading hardware register KEY_PAD=");
        }
        break;

        case 0x53:
        {
            printf("Reading hardware register CART_BUS=");
        }
        break;

        case 0x19:
        {
            printf("Reading hardware register TMR1_ENA_OSC/TMR1_OSC=");
        }
        break;

        case 0x27:
        case 0x28:
        case 0x29:
        case 0x2A:
        {
            printf("Reading hardware register IRQ_ACT%d=", address - 0x26);
        }
        break;

        case 0x60:
        {
            printf("Reading hardware register IO_DIR=");
        }
        break;

        case 0x61:
        {
            printf("Reading hardware register IO_DATA=");
        }
        break;

        case 0x71:
        {
            printf("Reading hardware register AUD_VOL=");
        }
        break;

        case 0x80:
        {
            printf("Reading hardware register PRC_MODE=");
            data = prc_mode;
        }
        break;

        case 0x81:
        {
            printf("Reading hardware register PRC_RATE=");
            data = prc_rate;
        }
        break;

        case 0x82:
        {
            printf("Reading hardware register PRC_MAP_LO=");
        }
        break;

        case 0x83:
        {
            printf("Reading hardware register PRC_MAP_MID=");
        }
        break;

        case 0x84:
        {
            printf("Reading hardware register PRC_MAP_HI=");
        }
        break;

        case 0x85:
        {
            printf("Reading hardware register PRC_SCROLL_Y=");
        }
        break;

        case 0x86:
        {
            printf("Reading hardware register PRC_SCROLL_X=");
        }
        break;

        case 0x87:
        {
            printf("Reading hardware register PRC_SPR_LO=");
        }
        break;

        case 0x88:
        {
            printf("Reading hardware register PRC_SPR_MID=");
        }
        break;

        case 0x89:
        {
            printf("Reading hardware register PRC_SPR_HI=");
        }
        break;

        case 0x44:
        case 0x45:
        case 0x46:
        case 0x47:
        case 0x50:
        case 0x51:
        case 0x54:
        case 0x55:
        case 0x62:
        {
            printf("Reading hardware register Unknown=");
        }
        break;

        default:
        {
            printf("Reading hardware register 0x%x=", address);
        }
        break;
    }
    printf("0x%x\n", data);
    return data;
}

int main(int argc, char** argv, char** env)
{
    FILE* fp = fopen("data/bios.min", "rb");
    fseek(fp, 0, SEEK_END);
    size_t file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */

    uint8_t* bios = (uint8_t*) malloc(file_size);
    uint8_t* bios_touched = (uint8_t*) calloc(file_size, 1);
    fread(bios, 1, file_size, fp);
    fclose(fp);

    uint8_t* memory = (uint8_t*) calloc(1, 4*1024);

    Verilated::commandArgs(argc, argv);

    Vs1c88* s1c88 = new Vs1c88;
    s1c88->clk = 0;
    s1c88->reset = 1;

    Verilated::traceEverOn(true);
    //VerilatedVcdC* tfp = new VerilatedVcdC;
    //s1c88->trace(tfp, 99);  // Trace 99 levels of hierarchy
    //tfp->open("sim.vcd");

    int mem_counter = 0;
    int frame = 0;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 1600000 && !Verilated::gotFinish())
    {
        s1c88->clk = 1;
        s1c88->eval();
        //if(timestamp > 1400000) tfp->dump(timestamp);
        timestamp++;

        s1c88->clk = 0;
        s1c88->eval();
        //if(timestamp > 1400000) tfp->dump(timestamp);
        timestamp++;

        //if(s1c88->sync && s1c88->pl == 0)
        //    printf("-- 0x%x\n", s1c88->rootp->s1c88__DOT__PC);

        if(timestamp >= 8)
            s1c88->reset = 0;

        // PRC
        if((timestamp/2 + 1) % 855 == 0)
        {
            ++prc_cnt;
            if((prc_rate & 0xF0) == prc_rate_match)
            {
                // Active frame
                if(prc_mode & 0x2)
                {
                    printf("drawing...\n");
                    int outaddr = 0x1000;
                    uint8_t image_data[96*64];
                    for (int yC=0; yC<8; yC++)
                    {
                        int ty = (yC << 3);
                        for (int xC=0; xC<96; xC++)
                        {
                            int tx = xC;
                            int tileidxaddr = 0x1360 + (ty >> 3) * 12 + (tx >> 3);
                            int tiletopaddr = prc_map + memory[tileidxaddr & 0xFFF] * 8;

                            // Read tile data
                            uint8_t data = memory[(tiletopaddr + (tx & 7)) & 0xFFF];
                            for(int i = 0; i < 8; ++i)
                                image_data[96 * (8 * yC + i) + xC] = 255 * ((data >> i) & 1);

                            // Write to VRAM
                            memory[outaddr & 0xFFF] = data;
                            ++outaddr;
                        }
                    }
                    char path[128];
                    snprintf(path, 128, "temp/frame_%03d.png", frame);
                    int has_error = !stbi_write_png(path, 96, 64, 1, image_data, 96);
                    if(has_error) printf("Error saving image %s\n", path);

                    fclose(fp);

                    ++frame;
                    prc_cnt = 1;
                    prc_rate &= 0xF;
                }

                if(prc_cnt == 0x42)
                {
                    prc_cnt = 1;
                    prc_rate &= 0xF;
                }
            }
            else if(prc_cnt == 0x42)
            {
                // Non-active frame
                prc_cnt = 1;
                prc_rate += 0x10;
            }
        }

        // At rising edge of clock
        if(data_sent)
            data_sent = false;

        if(sec_ctrl & 2)
            sec_cnt = 0;

        if((sec_ctrl & 1) && (timestamp % 4000000 == 0))
            ++sec_cnt;

        //s1c88->eval();
        //tfp->dump(timestamp++);

        // @todo: Translate instructions using instructions.csv.
        if(s1c88->rootp->s1c88__DOT__state == 2 && s1c88->pl == 0)
        {
            if(s1c88->rootp->s1c88__DOT__microaddress == 0)
                printf("** Instruction 0x%x not implemented **\n", s1c88->rootp->s1c88__DOT__extended_opcode);
        }

        // Check for errors
        {
            if(s1c88->rootp->s1c88__DOT__not_implemented_addressing_error == 1 && s1c88->pl == 0)
                printf(" ** Addressing not implemented error ** \n");

            if(s1c88->rootp->s1c88__DOT__not_implemented_jump_error == 1 && s1c88->pl == 0)
                printf(" ** Jump not implemented error ** \n");

            if(s1c88->rootp->s1c88__DOT__not_implemented_data_out_error == 1 && s1c88->pl == 0)
                printf(" ** Data-out not implemented error ** \n");

            if(s1c88->rootp->s1c88__DOT__not_implemented_mov_src_error == 1 && s1c88->pl == 0)
                printf(" ** Mov src not implemented error ** \n");

            if(s1c88->rootp->s1c88__DOT__not_implemented_write_error == 1 && s1c88->pl == 0)
                printf(" ** Write not implemented error ** \n");

            if(s1c88->rootp->s1c88__DOT__alu_op_error == 1 && s1c88->pl == 0)
                printf(" ** Alu not implemented error ** \n");
        }

        if(s1c88->bus_status == BUS_MEM_READ && s1c88->pl == 0) // Check if PL=0 just to reduce spam.
        {
            // memory read
            if(s1c88->address_out < 0x1000)
            {
                // read from bios
                bios_touched[s1c88->address_out & (file_size - 1)] = 1;
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
                //printf("0x%x, 0x%x\n", s1c88->rootp->s1c88__DOT__top_address, s1c88->rootp->s1c88__DOT__extended_opcode);
                s1c88->data_in = read_hardware_register(s1c88->address_out & 0x1FFF);
            }
            else
            {
                // read from cartridge
                s1c88->data_in = 0;//*(memory + (s1c88->address_out & 0x003FFF));
            }

            data_sent = true;
        }
        else if(s1c88->bus_status == BUS_MEM_WRITE && s1c88->write)
        {
            // memory write
            if(s1c88->address_out < 0x1000)
            {
                printf("Program trying to write to bios at 0x%x!\n", s1c88->address_out);
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
                //printf("0x%x, 0x%x\n", s1c88->rootp->s1c88__DOT__top_address, s1c88->rootp->s1c88__DOT__extended_opcode);
                write_hardware_register(s1c88->address_out & 0x1FFF, s1c88->data_out);
            }
            else
            {
                printf("Program trying to write to cartridge at 0x%x!\n", s1c88->address_out);
            }

            data_sent = true;
        }
        s1c88->eval();
    }

    //tfp->close();
    delete s1c88;

    size_t total_touched = 0;
    for(size_t i = 0; i < file_size; ++i)
        total_touched += bios_touched[i];
    printf("%zu bytes out of total %zu read from bios.\n", total_touched, file_size);

    return 0;
}
