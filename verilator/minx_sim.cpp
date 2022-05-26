#include "Vminx.h"
#include "Vminx___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstring>
#include <cstdint>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define VERBOSE 1

#if VERBOSE == 0
#define PRINTE(...) do{ } while ( false )
#define PRINTD(...) do{ } while ( false )
#elif VERBOSE == 1
#define PRINTE(...) do{ fprintf( stderr, __VA_ARGS__ ); } while( false )
#define PRINTD(...) do{ } while ( false )
#else
#define PRINTE(...) do{ fprintf( stderr, __VA_ARGS__ ); } while( false )
#define PRINTD(...) do{ fprintf( stdout, __VA_ARGS__ ); } while( false )
#endif


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
            PRINTD("Writing hardware register SYS_CTRL%d=", address+1);
        }
        break;

        case 0x8:
        {
            PRINTD("Writing hardware register SEC_CTRL=");
            sec_ctrl = data & 3;
        }
        break;

        case 0x10:
        {
            PRINTD("Writing hardware register SYS_BATT=");
        }
        break;

        case 0x19:
        {
            PRINTD("Writing hardware register TMR1_ENA_OSC/TMR1_OSC=");
        }
        break;

        case 0x20:
        case 0x21:
        case 0x22:
        {
            PRINTD("Writing hardware register IRQ_PRI%d=", address - 0x1F);
        }
        break;

        case 0x23:
        case 0x24:
        case 0x25:
        case 0x26:
        {
            PRINTD("Writing hardware register IRQ_ENA%d=", address - 0x22);
        }
        break;

        case 0x27:
        case 0x28:
        case 0x29:
        case 0x2A:
        {
            PRINTD("Writing hardware register IRQ_ACT%d=", address - 0x26);
            data = registers[address] & ~data;
        }
        break;

        case 0x40:
        {
            PRINTD("Writing hardware register TMR256_CTRL=");
        }
        break;

        case 0x60:
        {
            PRINTD("Writing hardware register IO_DIR=");
        }
        break;

        case 0x61:
        {
            PRINTD("Writing hardware register IO_DATA=");
        }
        break;

        case 0x70:
        {
            PRINTD("Writing hardware register AUD_CTRL=");
        }
        break;

        case 0x71:
        {
            PRINTD("Writing hardware register AUD_VOL=");
        }
        break;

        case 0x80:
        {
            PRINTD("Writing hardware register PRC_MODE=");
            prc_mode = data & 0x3F;
        }
        break;

        case 0x81:
        {
            PRINTD("Writing hardware register PRC_RATE=");
            if((prc_rate & 0xE) != (data & 0xE)) prc_rate = data & 0xF;
            else prc_rate = (prc_rate & 0xF0) | (data & 0x0F);
            switch (data & 0xE) {
                case 0x00: prc_rate_match = 0x20; break;    // Rate /3
                case 0x02: prc_rate_match = 0x50; break;    // Rate /6
                case 0x04: prc_rate_match = 0x80; break;    // Rate /9
                case 0x06: prc_rate_match = 0xB0; break;    // Rate /12
                case 0x08: prc_rate_match = 0x10; break;    // Rate /2
                case 0x0A: prc_rate_match = 0x30; break;    // Rate /4
                case 0x0C: prc_rate_match = 0x50; break;    // Rate /6
                case 0x0E: prc_rate_match = 0x70; break;    // Rate /8
            }
        }
        break;

        case 0x82:
        {
            PRINTD("Writing hardware register PRC_MAP_LO=");
            prc_map = (prc_map & 0xFFFFF00) | (data & 0xFF);
        }
        break;

        case 0x83:
        {
            PRINTD("Writing hardware register PRC_MAP_MID=");
            prc_map = (prc_map & 0xFFF00FF) | ((data & 0xFF) << 8);
        }
        break;

        case 0x84:
        {
            PRINTD("Writing hardware register PRC_MAP_HI=");
            prc_map = (prc_map & 0xF00FFFF) | ((data & 0xFF) << 16);
        }
        break;

        case 0x85:
        {
            PRINTD("Writing hardware register PRC_SCROLL_Y=");
        }
        break;

        case 0x86:
        {
            PRINTD("Writing hardware register PRC_SCROLL_X=");
        }
        break;

        case 0x87:
        {
            PRINTD("Writing hardware register PRC_SPR_LO=");
        }
        break;

        case 0x88:
        {
            PRINTD("Writing hardware register PRC_SPR_MID=");
        }
        break;

        case 0x89:
        {
            PRINTD("Writing hardware register PRC_SPR_HI=");
        }
        break;

        case 0xFE:
        {
            switch(data) {
                case 0x00: case 0x01: case 0x02: case 0x03: case 0x04: case 0x05: case 0x06: case 0x07:
                case 0x08: case 0x09: case 0x0A: case 0x0B: case 0x0C: case 0x0D: case 0x0E: case 0x0F:
                    PRINTD("LCD_CTRL: Set column low.\n");
                    break;
                case 0x10: case 0x11: case 0x12: case 0x13: case 0x14: case 0x15: case 0x16: case 0x17:
                case 0x18: case 0x19: case 0x1A: case 0x1B: case 0x1C: case 0x1D: case 0x1E: case 0x1F:
                    PRINTD("LCD_CTRL: Set column high.\n");
                    break;
                case 0x20: case 0x21: case 0x22: case 0x23: case 0x24: case 0x25: case 0x26: case 0x27:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x28: case 0x29: case 0x2A: case 0x2B: case 0x2C: case 0x2D: case 0x2E: case 0x2F:
                    // Modify LCD voltage? (2F Default)
                    // 0x28 = Blank
                    // 0x29 = Blank
                    // 0x2A = Blue screen then blank
                    // 0x2B = Blank
                    // 0x2C = Blank
                    // 0x2D = Blank
                    // 0x2E = Blue screen (overpower?)
                    // 0x2F = Normal
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37:
                case 0x38: case 0x39: case 0x3A: case 0x3B: case 0x3C: case 0x3D: case 0x3E: case 0x3F:
                    // Do nothing?
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45: case 0x46: case 0x47:
                case 0x48: case 0x49: case 0x4A: case 0x4B: case 0x4C: case 0x4D: case 0x4E: case 0x4F:
                case 0x50: case 0x51: case 0x52: case 0x53: case 0x54: case 0x55: case 0x56: case 0x57:
                case 0x58: case 0x59: case 0x5A: case 0x5B: case 0x5C: case 0x5D: case 0x5E: case 0x5F:
                case 0x60: case 0x61: case 0x62: case 0x63: case 0x64: case 0x65: case 0x66: case 0x67:
                case 0x68: case 0x69: case 0x6A: case 0x6B: case 0x6C: case 0x6D: case 0x6E: case 0x6F:
                case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x76: case 0x77:
                case 0x78: case 0x79: case 0x7A: case 0x7B: case 0x7C: case 0x7D: case 0x7E: case 0x7F:
                    // Set starting LCD scanline (cause warp around)
                    PRINTD("LCD_CTRL: Display start line\n");
                    break;
                case 0x80:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x81:
                    PRINTD("LCD_CTRL: Set contrast\n");
                    break;
                case 0x82: case 0x83: case 0x84: case 0x85: case 0x86: case 0x87:
                case 0x88: case 0x89: case 0x8A: case 0x8B: case 0x8C: case 0x8D: case 0x8E: case 0x8F:
                case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: case 0x97:
                case 0x98: case 0x99: case 0x9A: case 0x9B: case 0x9C: case 0x9D: case 0x9E: case 0x9F:
                    // Do nothing?
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xA0:
                    // Segment Driver Direction Select: Normal
                    PRINTD("LCD_CTRL: Segment driver direction normal\n");
                    break;
                case 0xA1:
                    // Segment Driver Direction Select: Reverse
                    PRINTD("LCD_CTRL: Segment driver direction reverse\n");
                    break;
                case 0xA2:
                    // Max Contrast: Disable
                    PRINTD("LCD_CTRL: Normal voltage bias\n");
                    break;
                case 0xA3:
                    // Max Contrast: Enable
                    PRINTD("LCD_CTRL: Darker voltage bias\n");
                    break;
                case 0xA4:
                    // Set All Pixels: Disable
                    PRINTD("LCD_CTRL: Set all pixels disable\n");
                    break;
                case 0xA5:
                    // Set All Pixels: Enable
                    PRINTD("LCD_CTRL: Set all pixels enable\n");
                    break;
                case 0xA6:
                    // Invert All Pixels: Disable
                    PRINTD("LCD_CTRL: Invert all pixels disable\n");
                    break;
                case 0xA7:
                    // Invert All Pixels: Enable
                    PRINTD("LCD_CTRL: Invert all pixels enable\n");
                    break;
                case 0xA8: case 0xA9: case 0xAA: case 0xAB:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xAC: case 0xAD:
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
                case 0xAE:
                    // Display Off
                    PRINTD("LCD_CTRL: Display off\n");
                    break;
                case 0xAF:
                    // Display On
                    PRINTD("LCD_CTRL: Display on\n");
                    break;
                case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: case 0xB7:
                case 0xB8:
                    // Set page (0-8, each page is 8px high)
                    PRINTD("LCD_CTRL: Set page\n");
                    break;
                case 0xB9: case 0xBA: case 0xBB: case 0xBC: case 0xBD: case 0xBE: case 0xBF:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xC0: case 0xC1: case 0xC2: case 0xC3: case 0xC4: case 0xC5: case 0xC6: case 0xC7:
                    // Display rows from top to bottom as 0 to 63
                    PRINTD("LCD_CTRL: Scan direction normal\n");
                    break;
                case 0xC8: case 0xC9: case 0xCA: case 0xCB: case 0xCC: case 0xCD: case 0xCE: case 0xCF:
                    // Display rows from top to bottom as 63 to 0
                    PRINTD("LCD_CTRL: Scan direction mirrored\n");
                    break;
                case 0xD0: case 0xD1: case 0xD2: case 0xD3: case 0xD4: case 0xD5: case 0xD6: case 0xD7:
                case 0xD8: case 0xD9: case 0xDA: case 0xDB: case 0xDC: case 0xDD: case 0xDE: case 0xDF:
                    // Do nothing?
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xE0:
                    // Start "Read Modify Write"
                    break;
                case 0xE2:
                    // Reset
                    PRINTD("LCD_CTRL: Reset display\n");
                    break;
                case 0xE3:
                    // No operation
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xEE:
                    // End "Read Modify Write"
                    PRINTD("LCD_CTRL: Read modify write\n");
                    break;
                case 0xE1: case 0xE4: case 0xE5: case 0xE6: case 0xE7:
                case 0xE8: case 0xE9: case 0xEA: case 0xEB: case 0xEC: case 0xED: case 0xEF:
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
                case 0xF0: case 0xF1: case 0xF2: case 0xF3: case 0xF4: case 0xF5: case 0xF6: case 0xF7:
                    // 0xF1 and 0xF5 freeze LCD and cause malfunction (need to power off the device to restore)
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
                case 0xF8: case 0xF9: case 0xFA: case 0xFB: case 0xFC: case 0xFD: case 0xFE: case 0xFF:
                    // Contrast voltage control, FC = Default
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
            }
            PRINTD("Writing hardware register LCD_CTRL=");
        }
        break;

        case 0xFF:
        {
            PRINTD("Writing hardware register LCD_DATA=");
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
            PRINTD("Writing hardware register Unknown=");
        }
        break;

        default:
        {
            PRINTD("Writing to hardware register 0x%x\n", address);
            return;
        }
    }
    registers[address] = data;
    PRINTD("0x%x\n", data);
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
            PRINTD("Reading hardware register SYS_CTRL%d=", address+1);
        }
        break;

        case 0x8:
        {
            PRINTD("Reading hardware register SEC_CTRL=");
            data = sec_ctrl;
        }
        break;

        case 0x9:
        {
            PRINTD("Reading hardware register SEC_CNT_LO=");
            data = sec_cnt & 0xFF;
        }
        break;

        case 0xA:
        {
            PRINTD("Reading hardware register SEC_CNT_MID=");
            data = (sec_cnt >> 8) & 0xFF;
        }
        break;

        case 0xB:
        {
            PRINTD("Reading hardware register SEC_CNT_MID=");
            data = (sec_cnt >> 16) & 0xFF;
        }
        break;

        case 0x10:
        {
            PRINTD("Reading hardware register SYS_BATT=");
        }
        break;

        case 0x52:
        {
            PRINTD("Reading hardware register KEY_PAD=");
        }
        break;

        case 0x53:
        {
            PRINTD("Reading hardware register CART_BUS=");
        }
        break;

        case 0x19:
        {
            PRINTD("Reading hardware register TMR1_ENA_OSC/TMR1_OSC=");
        }
        break;

        case 0x27:
        case 0x28:
        case 0x29:
        case 0x2A:
        {
            PRINTD("Reading hardware register IRQ_ACT%d=", address - 0x26);
        }
        break;

        case 0x36:
        case 0x37:
        case 0x3E:
        case 0x3F:
        case 0x41:
        case 0x4E:
        case 0x4F:
        {
            PRINTE("** Reading hardware register 0x%x which is a timer register and is not implemented! **\n", address);
        }
        break;

        case 0x60:
        {
            PRINTD("Reading hardware register IO_DIR=");
        }
        break;

        case 0x61:
        {
            PRINTD("Reading hardware register IO_DATA=");
        }
        break;

        case 0x71:
        {
            PRINTD("Reading hardware register AUD_VOL=");
        }
        break;

        case 0x80:
        {
            PRINTD("Reading hardware register PRC_MODE=");
            data = prc_mode;
        }
        break;

        case 0x81:
        {
            PRINTD("Reading hardware register PRC_RATE=");
            data = prc_rate;
        }
        break;

        case 0x82:
        {
            PRINTD("Reading hardware register PRC_MAP_LO=");
        }
        break;

        case 0x83:
        {
            PRINTD("Reading hardware register PRC_MAP_MID=");
        }
        break;

        case 0x84:
        {
            PRINTD("Reading hardware register PRC_MAP_HI=");
        }
        break;

        case 0x85:
        {
            PRINTD("Reading hardware register PRC_SCROLL_Y=");
        }
        break;

        case 0x86:
        {
            PRINTD("Reading hardware register PRC_SCROLL_X=");
        }
        break;

        case 0x87:
        {
            PRINTD("Reading hardware register PRC_SPR_LO=");
        }
        break;

        case 0x88:
        {
            PRINTD("Reading hardware register PRC_SPR_MID=");
        }
        break;

        case 0x89:
        {
            PRINTD("Reading hardware register PRC_SPR_HI=");
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
            PRINTD("Reading hardware register Unknown=");
        }
        break;

        default:
        {
            PRINTD("Reading hardware register 0x%x=", address);
        }
        break;
    }
    PRINTD("0x%x\n", data);
    return data;
}

// @todo: Detect when page registers need to be used (error not implemented). Are they even used?
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

    // Load a cartridge.
    uint8_t* cartridge = (uint8_t*) calloc(1, 0x200000);
    {
        FILE* fp = fopen("data/party_j.min", "rb");
        fseek(fp, 0, SEEK_END);
        size_t file_size = ftell(fp);
        fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */
        fread(cartridge, 1, file_size, fp);
        fclose(fp);
    }

    Verilated::commandArgs(argc, argv);

    Vminx* minx = new Vminx;
    minx->clk = 0;
    minx->reset = 1;

    bool dump = true;
    VerilatedVcdC* tfp;
    if(dump)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        minx->trace(tfp, 99);  // Trace 99 levels of hierarchy
        tfp->open("sim.vcd");
    }

    int mem_counter = 0;
    int frame = 0;

    int timestamp = 0;
    int prc_state = 0;
    bool data_sent = false;
    int irq_render_done_old = 0;
    int irq_copy_complete_old = 0;
    while (timestamp < 25000000 && !Verilated::gotFinish())
    {
        minx->clk = 1;
        minx->eval();
        if(dump && timestamp > 8803088 - 400000 && timestamp < 8803088 + 400000) tfp->dump(timestamp);
        timestamp++;

        minx->clk = 0;
        minx->eval();
        if(dump && timestamp > 8803088 - 400000 && timestamp < 8803088 + 400000) tfp->dump(timestamp);
        timestamp++;

        //if(minx->sync && minx->pl == 0)
        //    printf("-- 0x%x\n", minx->rootp->minx__DOT__cpu__DOT__PC);

        if(minx->rootp->minx__DOT__irq_render_done && irq_render_done_old == 0)
        {
            registers[0x27] |= 0x40;
            irq_render_done_old = 1;
            PRINTD("Render done %d.\n", timestamp / 2);

            uint8_t image_data[96*64];

            for (int yC=0; yC<8; yC++)
            {
                for (int xC=0; xC<96; xC++)
                {
                    uint8_t data = minx->rootp->minx__DOT__lcd__DOT__lcd_data[yC * 132 + xC];
                    for(int i = 0; i < 8; ++i)
                        image_data[96 * (8 * yC + i) + xC] = 255 * ((~data >> i) & 1);
                }
            }

            char path[128];
            snprintf(path, 128, "temp/frame_%03d.png", frame);
            printf("%d, %d\n", frame, timestamp);
            int has_error = !stbi_write_png(path, 96, 64, 1, image_data, 96);
            if(has_error) printf("Error saving image %s\n", path);

            ++frame;
        }
        else if(!minx->rootp->minx__DOT__irq_render_done) irq_render_done_old = 0;

        if(minx->rootp->minx__DOT__irq_copy_complete && irq_copy_complete_old == 0)
        {
            registers[0x27] |= 0x80;
            irq_copy_complete_old = 1;
            PRINTD("Copy complete %d.\n", timestamp / 2);
        }
        else if(!minx->rootp->minx__DOT__irq_copy_complete) irq_copy_complete_old = 0;

        // At rising edge of clock
        data_sent = false;

        if(sec_ctrl & 2)
            sec_cnt = 0;

        if((sec_ctrl & 1) && (timestamp % 4000000 == 0))
            ++sec_cnt;

        //minx->eval();
        //tfp->dump(timestamp++);

        // @todo: Translate instructions using instructions.csv.
        if(minx->rootp->minx__DOT__cpu__DOT__state == 2 && minx->pl == 0)
        {
            if(minx->rootp->minx__DOT__cpu__DOT__microaddress == 0)
                PRINTE("** Instruction 0x%x not implemented at 0x%x, timestamp: %d**\n", minx->rootp->minx__DOT__cpu__DOT__extended_opcode, minx->rootp->minx__DOT__cpu__DOT__top_address, timestamp);
        }
        //if(minx->sync == 1 && minx->pl == 0)
        //    printf("** Instruction 0x%x not implemented at 0x%x, timestamp: %d**\n", minx->rootp->minx__DOT__cpu__DOT__extended_opcode, minx->rootp->minx__DOT__cpu__DOT__top_address, timestamp);

        // Check for errors
        {
            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_addressing_error == 1 && minx->pl == 0)
                PRINTE(" ** Addressing not implemented error: 0x%llx, timestamp: %d** \n", (minx->rootp->minx__DOT__cpu__DOT__micro_op & 0x3F00000) >> 20, timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_jump_error == 1 && minx->pl == 0)
                PRINTE(" ** Jump not implemented error, timestamp: %d** \n", timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_data_out_error == 1 && minx->pl == 1)
                PRINTE(" ** Data-out not implemented error, timestamp: %d** \n", timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_mov_src_error == 1 && minx->pl == 0)
                PRINTE(" ** Mov src not implemented error, timestamp: %d** \n", timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_write_error == 1 && minx->pl == 0)
                PRINTE(" ** Write not implemented error, timestamp: %d** \n", timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__alu_op_error == 1 && minx->pl == 0)
                PRINTE(" ** Alu not implemented error, timestamp: %d** \n", timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_alu_dec_pack_ops_error == 1 && minx->pl == 0)
                PRINTE(" ** Alu decimal and packed operations not implemented error, timestamp: %d** \n", timestamp);

            if(minx->rootp->minx__DOT__cpu__DOT__not_implemented_divzero_error  == 1 && minx->pl == 0)
                PRINTE("** Division by zero exception not implemented error, timestamp: %d**\n", timestamp);
        }

        if(timestamp >= 8)
            minx->reset = 0;

        //if(timestamp == 258)
        //{
        //    minx->irq = 1 << 3;
        //}
        //else if(timestamp > 258 && minx->iack == 1 && minx->pl == 0)
        //{
        //    minx->irq = 0;
        //    minx->data_in = 0x8;
        //}

        if(minx->bus_status == BUS_MEM_READ && minx->pl == 0) // Check if PL=0 just to reduce spam.
        {
            // memory read
            if(minx->address_out < 0x1000)
            {
                //if(minx->sync == 1 && minx->pl == 0)
                //{
                //    //if(minx->rootp->minx__DOT__cpu__DOT__top_address == 0xd7c) printf("%d\n", minx->rootp->minx__DOT__cpu__DOT__BA & 0xFF);
                //    //if(minx->rootp->minx__DOT__cpu__DOT__top_address == 0xd73) printf("@%d\n", minx->rootp->minx__DOT__cpu__DOT__BA);
                //    printf("___ 0x%x\n", minx->rootp->address_out);
                //}
                // read from bios
                bios_touched[minx->address_out & (file_size - 1)] = 1;
                minx->data_in = *(bios + (minx->address_out & (file_size - 1)));
            }
            else if(minx->address_out < 0x2000)
            {
                // read from ram
                uint32_t address = minx->address_out & 0xFFF;
                minx->data_in = *(uint8_t*)(memory + address);
            }
            else if(minx->address_out < 0x2100)
            {
                // read from hardware registers
                //printf("0x%x, 0x%x\n", minx->rootp->minx__DOT__cpu__DOT__top_address, minx->rootp->minx__DOT__cpu__DOT__extended_opcode);
                minx->data_in = read_hardware_register(minx->address_out & 0x1FFF);
            }
            else
            {
                // read from cartridge
                //printf("0x%x, 0x%x\n", minx->rootp->minx__DOT__cpu__DOT__top_address, minx->rootp->minx__DOT__cpu__DOT__extended_opcode);
                if((minx->address_out & 0x8000) && (minx->rootp->minx__DOT__cpu__DOT__CB > 0))
                    PRINTE("** CB not implemented 0x%x, 0x%x **\n", minx->address_out, minx->rootp->minx__DOT__cpu__DOT__CB);
                minx->data_in = *(uint8_t*)(cartridge + (minx->address_out & 0x1FFFFF));
            }

            data_sent = true;
        }
        else if(minx->bus_status == BUS_MEM_WRITE && minx->write)
        {
            // memory write
            if(minx->address_out < 0x1000)
            {
                PRINTD("Program trying to write to bios at 0x%x, timestamp: %d\n", minx->address_out, timestamp);
            }
            else if(minx->address_out < 0x2000)
            {
                // write to ram
                //if(minx->address_out <= 0x12FF) printf("= 0x%x: 0x%x\n", minx->address_out, minx->data_out);
                //if(minx->address_out < 0x1360 && minx->address_out >= 0x1300) printf("= 0x%x, 0x%x, %d\n", minx->address_out, minx->data_out, timestamp);
                //if(minx->address_out >= prc_map && minx->address_out < 0x1928) printf("= 0x%x, 0x%x\n", minx->address_out, minx->data_out);
                uint32_t address = minx->address_out & 0xFFF;
                *(uint8_t*)(memory + address) = minx->data_out;
            }
            else if(minx->address_out < 0x2100)
            {
                // write to hardware registers
                //printf("0x%x, 0x%x\n", minx->rootp->minx__DOT__cpu__DOT__top_address, minx->rootp->minx__DOT__cpu__DOT__extended_opcode);
                write_hardware_register(minx->address_out & 0x1FFF, minx->data_out);
            }
            else
            {
                PRINTD("Program trying to write to cartridge at 0x%x, timestamp: %d\n", minx->address_out, timestamp);
            }

            data_sent = true;
        }
        //minx->eval();
    }

    if(dump) tfp->close();
    delete minx;

    size_t total_touched = 0;
    for(size_t i = 0; i < file_size; ++i)
        total_touched += bios_touched[i];
    printf("%zu bytes out of total %zu read from bios.\n", total_touched, file_size);

    return 0;
}
