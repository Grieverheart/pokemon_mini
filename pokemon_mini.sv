//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
    //Master input clock
    input         CLK_50M,

    //Async reset from top-level module.
    //Can be used as initial reset.
    input         RESET,

    //Must be passed to hps_io module
    inout  [48:0] HPS_BUS,

    //Base video clock. Usually equals to CLK_SYS.
    output        CLK_VIDEO,

    //Multiple resolutions are supported using different CE_PIXEL rates.
    //Must be based on CLK_VIDEO
    output        CE_PIXEL,

    //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
    //if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,    // = ~(VBlank | HBlank)
    output        VGA_F1,
    output [1:0]  VGA_SL,
    output        VGA_SCALER, // Force VGA scaler

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,

`ifdef MISTER_FB
    // Use framebuffer in DDRAM (USE_FB=1 in qsf)
    // FB_FORMAT:
    //    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
    //    [3]   : 0=16bits 565 1=16bits 1555
    //    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
    //
    // FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
    output        FB_EN,
    output  [4:0] FB_FORMAT,
    output [11:0] FB_WIDTH,
    output [11:0] FB_HEIGHT,
    output [31:0] FB_BASE,
    output [13:0] FB_STRIDE,
    input         FB_VBL,
    input         FB_LL,
    output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
    // Palette control for 8bit modes.
    // Ignored for other video modes.
    output        FB_PAL_CLK,
    output  [7:0] FB_PAL_ADDR,
    output [23:0] FB_PAL_DOUT,
    input  [23:0] FB_PAL_DIN,
    output        FB_PAL_WR,
`endif
`endif

    output        LED_USER,  // 1 - ON, 0 - OFF.

    // b[1]: 0 - LED status is system status OR'd with b[0]
    //       1 - LED status is controled solely by b[0]
    // hint: supply 2'b00 to let the system control the LED.
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,

    // I/O board button press simulation (active high)
    // b[1]: user button
    // b[0]: osd button
    output  [1:0] BUTTONS,

    input         CLK_AUDIO, // 24.576 MHz
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
    output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

    //ADC
    inout   [3:0] ADC_BUS,

    //SD-SPI
    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    //High latency DDR3 RAM interface
    //Use for non-critical time purposes
    output        DDRAM_CLK,
    input         DDRAM_BUSY,
    output  [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output  [7:0] DDRAM_BE,
    output        DDRAM_WE,

    //SDRAM interface with lower latency
    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
    //Secondary SDRAM
    //Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
    input         SDRAM2_EN,
    output        SDRAM2_CLK,
    output [12:0] SDRAM2_A,
    output  [1:0] SDRAM2_BA,
    inout  [15:0] SDRAM2_DQ,
    output        SDRAM2_nCS,
    output        SDRAM2_nCAS,
    output        SDRAM2_nRAS,
    output        SDRAM2_nWE,
`endif

    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    // Open-drain User port.
    // 0 - D+/RX
    // 1 - D-/TX
    // 2..6 - USR2..USR6
    // Set USER_OUT to 1 to read from USER_IN.
    input   [6:0] USER_IN,
    output  [6:0] USER_OUT,

    input         OSD_STATUS
);

// TODO list:
// * color palette
// * convert s1c88 from using posedge/negedge to just using posedge?
// * savestates?

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = {1'b1, bus_ack};
assign LED_POWER = {1'b1, bus_request};
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] scale = status[3:2];
wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
    "PokemonMini;;",
    "-;",
    "FS1,min,Load ROM;",
    "-;",
    "d0R[09],Reload Backup RAM;",
    "d0R[10],Save Backup RAM;",
    "d0O[11],Autosave,Off,On;",
    "-;",
    "O[99:98],Frame Blend,off,2 frames,4 frames;",
    "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "O23,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
    "-;",
    "T[0],Reset;",
    "R[0],Reset and close OSD;",
    // A, B, C, Power
    "J0,A,B,R;",//,select;",
    "V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire [21:0] gamma_bus;

wire ioctl_download;
wire ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0] ioctl_dout;
wire ioctl_wait;
wire [7:0]  filetype;

wire cart_busy;
assign ioctl_wait = cart_busy & cart_download;

wire [15:0] joystick_0;
wire [64:0] rtc_timestamp;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire [13:0] sd_buff_addr;
wire [7:0]  sd_buff_dout;
wire [7:0]  sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

hps_io
#(
    .CONF_STR(CONF_STR),
    .WIDE(0),
    .BLKSZ(2)
)
hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .EXT_BUS(),


    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_wait(ioctl_wait),
    .ioctl_index(filetype),

    .sd_lba('{sd_lba}),
    .sd_rd(sd_rd),
    .sd_wr(sd_wr),
    .sd_ack(sd_ack),
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din('{sd_buff_din}),
    .sd_buff_wr(sd_buff_wr),
    .img_mounted(img_mounted),
    .img_readonly(img_readonly),
    .img_size(img_size),

    .gamma_bus(gamma_bus),

    .forced_scandoubler(forced_scandoubler),

    .buttons(buttons),
    .status(status),
    .status_menumask(cart_ready),

    .ps2_key(ps2_key),
    .joystick_0(joystick_0),

    .RTC(rtc_timestamp)
);


///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_rt;
wire clk_ram;
wire pll_locked;
pll pll
(
    .refclk   (CLK_50M),
    .rst      (0),
    .outclk_0 (clk_ram), // 40 MHz
    .outclk_1 (clk_rt),  // 4.194756 MHz
    .outclk_2 (clk_sys), // 16 MHz
    .locked   (pll_locked)
);

reg [6:0] clk_rt_prescale = 0;
always_ff @ (posedge clk_rt) clk_rt_prescale <= clk_rt_prescale + 1;

reg [1:0] clk_prescale = 0;
reg [1:0] minx_clk_prescale = 0;
always_ff @ (posedge clk_sys)
begin
    clk_prescale <= clk_prescale + 1;
    minx_clk_prescale  <= minx_clk_prescale + 1;
end

//reg sdram_read = 0;
//always_ff @ (posedge clk_sys) sdram_read <= ~sdram_read;

wire reset = RESET | status[0] | buttons[1] | cart_download | bios_download | bk_loading;
reg [3:0] reset_counter;
always_ff @ (posedge clk_sys)
begin
    if(reset) reset_counter <= 4'hF;
    else if(reset_counter > 4'd0 && &minx_clk_prescale) reset_counter <= reset_counter - 4'd1;
end

//////////////////////////////////////////////////////////////////

wire ce_pix = &clk_prescale;
wire [7:0] video;

assign CLK_VIDEO = clk_sys;

assign LED_USER  = ioctl_download | sav_pending;

reg hs, vs, hbl, vbl;

localparam H_WIDTH   = 9'd280;
localparam V_HEIGHT  = 9'd238;
localparam LCD_XSIZE = 9'd96;
localparam LCD_YSIZE = 9'd64;
localparam LCD_COLS  = LCD_YSIZE >> 3;

reg frame_complete_latch;
(* ramstyle = "no_rw_check" *) reg [7:0] fb0[768];
(* ramstyle = "no_rw_check" *) reg [7:0] fb1[768];
(* ramstyle = "no_rw_check" *) reg [7:0] fb2[768];
(* ramstyle = "no_rw_check" *) reg [7:0] fb3[768];
reg [1:0] fb_write_index = 0;
reg [1:0] fb_read_index = 0;
wire [9:0] fb_read_address  = {1'b0, LCD_XSIZE} * {5'b0, ypos[6:3]} + {1'b0, xpos};
wire [9:0] fb_write_address = {1'b0, LCD_XSIZE} * {5'b0, lcd_read_ypos} + {1'b0, lcd_read_xpos};
reg [7:0] fb0_read;
reg [7:0] fb1_read;
reg [7:0] fb2_read;
reg [7:0] fb3_read;
wire [7:0] fb_read[0:3] = '{fb0_read, fb1_read, fb2_read, fb3_read};
// Try putting them in same always block as lcd read block, below.
// @todo: 6shades doesn't work because we are copying at copy complete instead
// of render complete, and 6shades does not issue copy complete; it writes
// straight to the lcd.

reg [7:0] lcd_read_xpos;
reg [3:0] lcd_read_ypos;
always @ (posedge clk_sys)
begin
    if(reset)
    begin
        fb_read_index <= 0;
        fb_write_index <= 1;
        frame_complete_latch <= 0;
        lcd_read_xpos <= 0;
        lcd_read_ypos <= 0;
    end
    else
    begin
        if(frame_complete)
            frame_complete_latch <= 1;

        // Need to wait 2 clocks for data from lcd?
        if(frame_complete_latch && &minx_clk_prescale)
        begin
            case(fb_write_index)
                0:
                    fb0[fb_write_address] <= lcd_read_column;
                1:
                    fb1[fb_write_address] <= lcd_read_column;
                2:
                    fb2[fb_write_address] <= lcd_read_column;
                3:
                    fb3[fb_write_address] <= lcd_read_column;
            endcase

            lcd_read_xpos <= lcd_read_xpos + 1;
            if(lcd_read_xpos == LCD_XSIZE - 1)
            begin
                lcd_read_xpos <= 0;
                lcd_read_ypos <= lcd_read_ypos + 1;
                if(lcd_read_ypos == LCD_COLS - 1)
                begin
                    fb_write_index <= fb_write_index + 1;
                    fb_read_index <= fb_write_index;
                    frame_complete_latch <= 0;
                    lcd_read_ypos <= 0;
                end
            end
        end
    end

    fb0_read <= fb0[fb_read_address];
    fb1_read <= fb1[fb_read_address];
    fb2_read <= fb2[fb_read_address];
    fb3_read <= fb3[fb_read_address];
end

reg [8:0] hpos,vpos;
reg [7:0] pixel_value_red;
reg [7:0] pixel_value_green;
reg [7:0] pixel_value_blue;
// @todo: Latch lcd_contrast for each fb0-3?
wire [7:0] pixel_on = (lcd_contrast >= 6'h20)? 8'd255: {lcd_contrast[4:0], 3'd0};

wire [7:0] red   = pixel_value_red;
wire [7:0] green = pixel_value_green;
wire [7:0] blue  = pixel_value_blue;

wire [1:0] blend_mode = status[99:98];

localparam bit[7:0] OFF_COLOR[0:2] = '{8'hB7, 8'hCA, 8'hB7};
localparam bit[7:0] ON_COLOR[0:2]  = '{8'h04, 8'h16, 8'h04};

// 3-shades
wire [8:0] pixel_2frame_blend = 
    ({1'd0, pixel_on} * {8'b0, fb_read[fb_read_index-0][ypos[2:0]]}) +
    ({1'd0, pixel_on} * {8'b0, fb_read[fb_read_index-1][ypos[2:0]]});

// 5-shades
wire [9:0] pixel_4frame_blend = 
    ({2'd0, pixel_on} * {9'b0, fb_read[fb_read_index-0][ypos[2:0]]}) +
    ({2'd0, pixel_on} * {9'b0, fb_read[fb_read_index-1][ypos[2:0]]}) +
    ({2'd0, pixel_on} * {9'b0, fb_read[fb_read_index-2][ypos[2:0]]}) +
    ({2'd0, pixel_on} * {9'b0, fb_read[fb_read_index-3][ypos[2:0]]});

// @todo: Perhaps make intensity go to 256 instead of 255. Then we can just
// shift the final color result instead of dividing by 256.
wire [7:0] pixel_intensity =
    (blend_mode == 0)?
        pixel_on * {7'b0, fb_read[fb_read_index][ypos[2:0]]}:
    ((blend_mode == 1)?
        pixel_2frame_blend[8:1]:
        pixel_4frame_blend[9:2]);

reg [7:0] xpos, ypos;
always @ (posedge CLK_VIDEO)
begin
    if(ce_pix)
    begin
        if(hpos == LCD_XSIZE + 16) hbl <= 1;
        if(hpos == 16)             hbl <= 0;
        if(vpos >= 32+LCD_YSIZE)   vbl <= 1;
        if(vpos == 32)             vbl <= 0;

        if(hpos == 120)
        begin
            hs <= 1;
            if(vpos == 1) vs <= 1;
            if(vpos == 4) vs <= 0;
        end

        if(hpos == 120+16) hs <= 0;

        hpos <= hpos + 1;
        if(hpos == H_WIDTH - 1'd1)
        begin
            hpos <= 0;
            vpos <= vpos + 1;

            if(vpos == V_HEIGHT - 1'd1) vpos <= 0;
        end

        if(vbl)
        begin
            ypos <= 0;
            xpos <= 0;
        end
        else if(!hbl)
        begin
            xpos <= xpos + 1;
            if(xpos == LCD_XSIZE - 1)
            begin
                xpos <= 0;
                ypos <= ypos + 1;
            end
        end

    end

    pixel_value_red   <= ({8'h0, 8'hFF - pixel_intensity} * OFF_COLOR[0] + {8'h0, pixel_intensity} * ON_COLOR[0]) / 255;
    pixel_value_green <= ({8'h0, 8'hFF - pixel_intensity} * OFF_COLOR[1] + {8'h0, pixel_intensity} * ON_COLOR[1]) / 255;
    pixel_value_blue  <= ({8'h0, pixel_intensity} * OFF_COLOR[2] + {8'h0, 8'hFF - pixel_intensity} * ON_COLOR[2]) / 255;
end


// in:  {select, R, b, a, up, down, left, right}
// out: {power, right, left, down, up, c, b, a}
wire [7:0] keys_active =
{
    1'b0,//joystick_0[7], // (select) power
    joystick_0[0], //  (right) right
    joystick_0[1], //   (left) left
    joystick_0[2], //   (down) down
    joystick_0[3], //     (up) up
    joystick_0[6], //      (R) c
    joystick_0[5], //      (b) b
    joystick_0[4]  //      (a) a
};

wire [5:0] lcd_contrast;
wire [7:0] minx_data_in;
wire [7:0] minx_data_out;
wire [23:0] minx_address_out;

wire bus_request;
wire bus_ack;
wire minx_we;
wire [1:0] bus_status;
wire [7:0] lcd_read_column;
wire frame_complete;

// @todo: Need access to eeprom for initialization. While initializing it, we
// can set clk_ce to low so that the cpu is paused.
wire sound_pulse;
wire [1:0] sound_volume;
wire eeprom_internal_we;
wire eeprom_we = eeprom_we_rtc | bk_wr;
wire [12:0] eeprom_address = eeprom_we_rtc? eeprom_write_address_rtc: bk_addr;
wire [7:0] eeprom_write_data = eeprom_we_rtc? eeprom_write_data_rtc: bk_data;
minx minx
(
    .clk                   (clk_sys),
    .clk_ce_4mhz           (&minx_clk_prescale),
    .clk_rt                (clk_rt),
    .clk_rt_ce             (&clk_rt_prescale),
    .reset                 (reset | (|reset_counter)),
    .data_in               (minx_data_in),
    .keys_active           (keys_active),
    //.pk                    (pk),
    //.pl                    (pl),
    //.i01                   (i01),
    .data_out              (minx_data_out),
    .address_out           (minx_address_out),
    .bus_status            (bus_status),
    //.read                  (read),
    //.read_interrupt_vector (read_interrupt_vector),
    .write                 (minx_we),
    //.sync                  (sync),
    //.iack                  (iack),

    .lcd_contrast          (lcd_contrast),
    .lcd_read_x            (lcd_read_xpos),
    .lcd_read_y            (lcd_read_ypos),
    .lcd_read_column       (lcd_read_column),
    .frame_complete        (frame_complete),

    .sound_pulse           (sound_pulse),
    .sound_volume          (sound_volume),

    .validate_rtc          (validate_rtc),
    .eeprom_internal_we    (eeprom_internal_we),
    .eeprom_we             (eeprom_we),
    .eeprom_address        (eeprom_address),
    .eeprom_write_data     (eeprom_write_data),
    .eeprom_read_data      (bk_q)
);

reg [15:0] sound_out;
always_comb
begin
    case({sound_volume, sound_pulse})
        3'b000, 3'b001: sound_out = 16'h7FFF;
        3'b010, 3'b100: sound_out = 16'h4000;
        3'b011, 3'b101: sound_out = 16'hBFFE;
        3'b110:         sound_out = 16'h0000;
        3'b111:         sound_out = 16'hFFFF;
    endcase
end
assign AUDIO_L = sound_out;
assign AUDIO_R = sound_out;

wire [7:0] bios_data_out;
spram #(
    .init_file("verilator/data/freebios.hex"),
    .widthad_a(12),
    .width_a(8)
) bios
(
    .clock   (clk_sys),
    .address (bios_download? ioctl_addr[11:0]: minx_address_out[11:0]),
    .q       (bios_data_out),

    .wren    (bios_download & ioctl_wr),
    .data    (ioctl_dout)
);

wire [7:0] ram_data_out;
spram #(
    .widthad_a(12),
    .width_a(8)
) minx_ram
(
    .clock(clk_sys),
    .address(minx_address_out[11:0]),
    .q(ram_data_out),
    .data(minx_data_out),
    .wren(
        minx_we &&
        (bus_status == BUS_COMMAND_MEM_WRITE) &&
        (minx_address_out >= 24'h1000) &&
        (minx_address_out < 24'h2000)
    )
);

/////////////   EEPROM saving/loading/RTC   //////////////////////
reg eeprom_we_rtc;
reg [12:0] eeprom_write_address_rtc;
reg [7:0] eeprom_write_data_rtc;
reg validate_rtc;


function [7:0] bcd2bin(input [7:0] bcd);
    bcd2bin = {4'd0, bcd[7:4]} * 8'd10 + {4'd0, bcd[3:0]};
endfunction

wire [7:0] rtc_year  = bcd2bin(rtc_timestamp[47:40]);
wire [7:0] rtc_month = bcd2bin(rtc_timestamp[39:32]);
wire [7:0] rtc_day   = bcd2bin(rtc_timestamp[31:24]);
wire [7:0] rtc_hour  = bcd2bin(rtc_timestamp[23:16]);
wire [7:0] rtc_min   = bcd2bin(rtc_timestamp[15:8]);
wire [7:0] rtc_sec   = bcd2bin(rtc_timestamp[7:0]);

wire [7:0] rtc_checksum = rtc_year + rtc_month + rtc_day + rtc_hour + rtc_min + rtc_sec;

reg [3:0] eeprom_write_stage;
// @todo: Test eeprom datetime setting.
// @todo: Should we check that this only runs once?
always_ff @ (posedge clk_sys)
begin
    if(minx_address_out == 24'hAB)
        eeprom_write_stage <= 1;

    if(eeprom_write_stage > 0)
    begin
        eeprom_write_stage <= eeprom_write_stage + 1;
        case(eeprom_write_stage)
            1:
            begin
                eeprom_we_rtc             <= 1;
                validate_rtc              <= 1;

                eeprom_write_address_rtc <= 13'h0;
                eeprom_write_data_rtc    <= 8'h47;
            end
            2:
            begin
                eeprom_write_address_rtc <= 13'h1;
                eeprom_write_data_rtc    <= 8'h42;
            end
            3:
            begin
                eeprom_write_address_rtc <= 13'h2;
                eeprom_write_data_rtc    <= 8'h4D;
            end
            4:
            begin
                eeprom_write_address_rtc <= 13'h3;
                eeprom_write_data_rtc    <= 8'h4E;
            end
            5:
            begin
                eeprom_write_address_rtc <= 13'h1FF6;
                eeprom_write_data_rtc    <= 0;
            end
            6:
            begin
                eeprom_write_address_rtc <= 13'h1FF7;
                eeprom_write_data_rtc    <= 0;
            end
            7:
            begin
                eeprom_write_address_rtc <= 13'h1FF8;
                eeprom_write_data_rtc    <= 0;
            end
            8:
            begin
                eeprom_write_address_rtc <= 13'h1FF9;
                eeprom_write_data_rtc    <= rtc_year;
            end
            9:
            begin
                eeprom_write_address_rtc <= 13'h1FFA;
                eeprom_write_data_rtc    <= rtc_month;
            end
            10:
            begin
                eeprom_write_address_rtc <= 13'h1FFB;
                eeprom_write_data_rtc    <= rtc_day;
            end
            11:
            begin
                eeprom_write_address_rtc <= 13'h1FFC;
                eeprom_write_data_rtc    <= rtc_hour;
            end
            12:
            begin
                eeprom_write_address_rtc <= 13'h1FFD;
                eeprom_write_data_rtc    <= rtc_min;
            end
            13:
            begin
                eeprom_write_address_rtc <= 13'h1FFE;
                eeprom_write_data_rtc    <= rtc_sec;
            end
            14:
            begin
                eeprom_write_address_rtc <= 13'h1FFF;
                eeprom_write_data_rtc    <= rtc_checksum;
            end
            15:
            begin
                validate_rtc       <= 0;
                eeprom_we_rtc      <= 0;
                eeprom_write_stage <= 0;
            end
            default:
            begin
            end
        endcase
    end
end

/////////////////////////  BRAM SAVE/LOAD  /////////////////////////////

// @note: Since bk_loading is taken into account in the reset signal, this
// means that rtc setting will always come after the eeprom is already loaded.
wire [12:0] bk_addr = {sd_lba[3:0], sd_buff_addr[8:0]};
wire bk_wr = sd_buff_wr & sd_ack;
wire [7:0] bk_data = sd_buff_dout;
wire [7:0] bk_q;

assign sd_buff_din = bk_q;
wire downloading = cart_download;

reg bk_ena          = 0;
reg new_load        = 0;
reg old_downloading = 0;
reg sav_pending     = 0;
reg cart_ready      = 0;

wire downloading_negedge = old_downloading & ~downloading;
wire downloading_posedge = ~old_downloading & downloading;
always @(posedge clk_sys)
begin
    old_downloading <= downloading;
    if(downloading_posedge) bk_ena <= 0;

    //Save file always mounted in the end of downloading state.
    if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

    // Load eeprom after loading a rom.
    if (downloading_negedge & bk_ena)
    begin
        new_load   <= 1'b1;
        cart_ready <= 1'b1;
    end
    else if (bk_state)
        new_load <= 1'b0;

    // This enables a save whenever a write was done to the eeprom.
    if(eeprom_internal_we & ~OSD_STATUS & bk_ena)
        sav_pending <= 1'b1;
    else if (bk_state)
        sav_pending <= 1'b0;
end

wire bk_load    = status[9] | new_load;
wire bk_save    = status[10] | (sav_pending & OSD_STATUS & status[11]);
reg  bk_loading = 0;
reg  bk_state   = 0;


reg old_load = 0, old_save = 0, old_ack;
wire load_posedge = ~old_load &  bk_load;
wire save_posedge = ~old_save &  bk_save;
wire ack_posedge  = ~old_ack  &  sd_ack;
wire ack_negedge  =  old_ack  & ~sd_ack;
always @(posedge clk_sys)
begin
    old_load <= bk_load;
    old_save <= bk_save;
    old_ack  <= sd_ack;

    if(ack_posedge) {sd_rd, sd_wr} <= 0;

    if(!bk_state)
    begin
        if(bk_ena & (load_posedge | save_posedge))
        begin
            bk_state   <= 1;
            bk_loading <= bk_load;
            sd_lba     <= 32'd0;
            sd_rd      <= bk_load;
            sd_wr      <= ~bk_load;
        end
        if(bk_ena & downloading_negedge & |img_size)
        begin
            bk_state   <= 1;
            bk_loading <= 1;
            sd_lba     <= 0;
            sd_rd      <= 1;
            sd_wr      <= 0;
        end
    end
    else if(ack_negedge)
    begin
        if(&sd_lba[3:0])
        begin
            bk_loading <= 0;
            bk_state   <= 0;
        end
        else
        begin
            sd_lba <= sd_lba + 1'd1;
            sd_rd  <= bk_loading;
            sd_wr  <= ~bk_loading;
        end
    end
end

//////////////////////////////////////////////////////////////////


// @check: Correct filetype?
wire cart_download = ioctl_download && filetype == 8'h01;
wire bios_download = ioctl_download && filetype == 8'h00;
wire [7:0] cartridge_data;
sdram cartridge_rom
(
    .SDRAM_DQ   (SDRAM_DQ),
    .SDRAM_A    (SDRAM_A),
    .SDRAM_DQML (SDRAM_DQML),
    .SDRAM_DQMH (SDRAM_DQMH),
    .SDRAM_BA   (SDRAM_BA),
    .SDRAM_nCS  (SDRAM_nCS),
    .SDRAM_nWE  (SDRAM_nWE),
    .SDRAM_nRAS (SDRAM_nRAS),
    .SDRAM_nCAS (SDRAM_nCAS),
    .SDRAM_CLK  (SDRAM_CLK),
    .SDRAM_CKE  (SDRAM_CKE),

    .init       (~pll_locked),
    .clk        (clk_ram),

    .ch0_addr   (cart_download? ioctl_addr: {4'd0, minx_address_out[20:0]}),
    .ch0_rd     (~cart_download & clk_sys),
    .ch0_wr     (cart_download & ioctl_wr),
    .ch0_din    (ioctl_dout),
    .ch0_dout   (cartridge_data),
    .ch0_busy   (cart_busy)
);

assign minx_data_in =
     (minx_address_out < 24'h1000)? bios_data_out:
    ((minx_address_out < 24'h2000)? ram_data_out:
                                    cartridge_data);

video_mixer #(640, 0) mixer
(
    .*,
    .CE_PIXEL       (CE_PIXEL),
    .hq2x           (scale == 1),
    .scandoubler    (scale || forced_scandoubler),
    .freeze_sync    (),
    .gamma_bus      (gamma_bus),
    .R              (red),
    .G              (green),
    .B              (blue),
    .HSync          (hs),
    .VSync          (vs),
    .HBlank         (hbl),
    .VBlank         (vbl),
    .VGA_R          (VGA_R),
    .VGA_G          (VGA_G),
    .VGA_B          (VGA_B),
    .VGA_VS         (VGA_VS),
    .VGA_HS         (VGA_HS),
    .VGA_DE         (VGA_DE)
);

endmodule
