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
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = red[0];
assign LED_POWER = hpos == 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
    "MyCore;;",
    "-;",
    "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "O[2],TV Mode,NTSC,PAL;",
    "O[4:3],Noise,White,Red,Green,Blue;",
    "-;",
    "P1,Test Page 1;",
    "P1-;",
    "P1-, -= Options in page 1 =-;",
    "P1-;",
    "P1O[5],Option 1-1,Off,On;",
    "d0P1F1,BIN;",
    "H0P1O[10],Option 1-2,Off,On;",
    "-;",
    "P2,Test Page 2;",
    "P2-;",
    "P2-, -= Options in page 2 =-;",
    "P2-;",
    "P2S0,DSK;",
    "P2O[7:6],Option 2,1,2,3,4;",
    "-;",
    "-;",
    "T[0],Reset;",
    "R[0],Reset and close OSD;",
    "V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .EXT_BUS(),
    .gamma_bus(gamma_bus),

    .forced_scandoubler(forced_scandoubler),

    .buttons(buttons),
    .status(status),
    .status_menumask({status[5]}),

    .ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_rt;
pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys),
    .outclk_1(clk_rt)
);

reg [7:0] clk_rt_prescale = 0;
always_ff @ (posedge clk_rt) clk_rt_prescale <= clk_rt_prescale + 1;

reg [1:0] clk_prescale = 0;
always_ff @ (posedge clk_sys) clk_prescale <= clk_prescale + 1;

wire reset = RESET | status[0] | buttons[1];

//////////////////////////////////////////////////////////////////

wire ce_pix = &clk_prescale;
wire [7:0] video;

assign CLK_VIDEO = clk_sys;

assign LED_USER  = frame_complete;//ioctl_download | sav_pending;

//assign vsync = vpos < 2 || vpos > V_HEIGHT - 1'd1; // Catch the uneven line in vsync to see if it helps
//assign hsync = hpos < 16 || hpos > (H_WIDTH - 8'd16);
reg hs, vs, hbl, vbl;

// 140 x 119
localparam H_WIDTH   = 8'd140;
localparam V_HEIGHT  = 8'd119;
localparam LCD_XSIZE = 8'd96;
localparam LCD_YSIZE = 8'd64;

reg [7:0] green;
reg [7:0] red;
reg [7:0] blue;
reg [7:0] hpos,vpos;
reg [12:0] pixel_address;
//reg frame_complete_latch;
always @ (posedge CLK_VIDEO, posedge reset)
begin
    if(reset)
    begin
        //frame_complete_latch <= 0;
        pixel_address <= 0;
    end
    else if(ce_pix)
    begin
        if(hpos == LCD_XSIZE + 16)  hbl <= 1;
        if(vpos ==  32)             vbl <= 0;
        if(vpos >=  32+LCD_YSIZE)   vbl <= 1;
        if(hpos == 16)              hbl <= 0;
        if(hpos == 120)
        begin
            hs <= 1;
            if(vpos == 1) vs <= 1;
            if(vpos == 4) vs <= 0;
        end

        if(hpos == 120+16) hs <= 0;

        hpos <= hpos + 1;
        if(hpos == 8'd140)
        begin
            hpos <= 0;
            vpos <= vpos + 1;

            if(vpos == 8'd119) vpos <= 0;
        end

        // @note: If we have hpos and vpos anyway, perhaps we can use
        // those instead of pixel_address.
        if(~hbl && ~vbl) // if(VGA_DE) ?
        begin
            red   <= fb0[{pixel_address[12:9], pixel_address[5:0]}][pixel_address[8:6]]? 8'd255: 8'h0;
            green <= fb0[{pixel_address[12:9], pixel_address[5:0]}][pixel_address[8:6]]? 8'd255: 8'h0;
            blue  <= fb0[{pixel_address[12:9], pixel_address[5:0]}][pixel_address[8:6]]? 8'd255: 8'h0;
            pixel_address <= pixel_address + 1;
        end
        else if(vbl)
        begin
            pixel_address <= 0;
        end

        //if(frame_complete)
        //    frame_complete_latch <= 1;

        //if(frame_complete_latch)
        //begin
        //    frame_complete_latch <= 0;
        //end
    end
end


wire [5:0] lcd_contrast;
wire [7:0] minx_data_in;
wire [7:0] minx_data_out;
wire [23:0] minx_address_out;
minx minx
(
    .clk                   (clk_sys),
    // @todo: Pass rt_clk and rt_ce instead; clk_rt_prescale[7] is not really
    // a clock.
    .rt_clk                (clk_rt_prescale[7]),
    .reset                 (reset),
    .data_in               (minx_data_in),
    //.keys_active           (keys_active),
    //.pk                    (pk),
    //.pl                    (pl),
    //.i01                   (i01),
    .data_out              (minx_data_out),
    .address_out           (minx_address_out),
    .bus_status            (bus_status),
    //.read                  (read),
    //.read_interrupt_vector (read_interrupt_vector),
    //.write                 (write),
    //.sync                  (sync),
    //.iack                  (iack),

    .lcd_contrast(lcd_contrast),
    .frame_complete(frame_complete)
);

wire [7:0] bios_data_out;
dpram #(
    .init_file("verilator/data/bios.hex"),
    .widthad_a(12),
    .width_a(8)
) vmem
(
    .clock_a(clk_sys),
    .address_a(minx_address_out[11:0] - 12'h300),
    .wren_a(1'b0),
    .q_a(bios_data_out)

    //.clock_b(clk_sys),
    //.wren_b(bus_status == 2'd2),
    //.address_b(minx_address_out),
    //.data_b(data_out)
);

reg [7:0] fb0[768];
reg [7:0] ram[3328];
assign minx_data_in =
     (minx_address_out < 24'h1000)? bios_data_out:
    ((minx_address_out < 24'h1300)? fb0[minx_address_out[9:0]]:
    ((minx_address_out < 24'h2000)? ram[minx_address_out[11:0] - 12'h300]:
                                    0));

always_ff @ (posedge clk_sys)
begin
    if(bus_status == BUS_COMMAND_MEM_WRITE && minx_address_out >= 24'h1000)
    begin
        if(minx_address_out < 24'h1300)
            fb0[minx_address_out[9:0]] <= minx_data_out;
        else if(minx_address_out < 24'h2000)
            ram[minx_address_out[11:0] - 12'h300] <= minx_data_out;
    end
end

//altsyncram  altsyncram_component
//(
//    .address_a (bram_addr),
//    .address_b (sd_buff_addr),
//    .clock0 (clk_ram),
//    .clock1 (clk_sys),
//    .data_a (bram_din),
//    .data_b (sd_buff_dout),
//    .wren_a (~bk_loading & bram_ack),
//    .wren_b (sd_buff_wr && ~extra_data_addr),
//    .q_a (bram_dout),
//    .q_b (bram_buff_out),
//    .byteena_a (1'b1),
//    .byteena_b (1'b1),
//    .clocken0 (1'b1),
//    .clocken1 (1'b1),
//    .rden_a (1'b1),
//    .rden_b (1'b1)
//);
//defparam
//    altsyncram_component.address_reg_b = "CLOCK1",
//    altsyncram_component.clock_enable_input_a = "BYPASS",
//    altsyncram_component.clock_enable_input_b = "BYPASS",
//    altsyncram_component.clock_enable_output_a = "BYPASS",
//    altsyncram_component.clock_enable_output_b = "BYPASS",
//    altsyncram_component.indata_reg_b = "CLOCK1",
//    altsyncram_component.intended_device_family = "Cyclone V",
//    altsyncram_component.lpm_type = "altsyncram",
//    altsyncram_component.numwords_a = 256,
//    altsyncram_component.numwords_b = 256,
//    altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
//    altsyncram_component.outdata_aclr_a = "NONE",
//    altsyncram_component.outdata_aclr_b = "NONE",
//    altsyncram_component.outdata_reg_a = "UNREGISTERED",
//    altsyncram_component.outdata_reg_b = "UNREGISTERED",
//    altsyncram_component.power_up_uninitialized = "FALSE",
//    altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
//    altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
//    altsyncram_component.widthad_a = 8,
//    altsyncram_component.widthad_b = 8,
//    altsyncram_component.width_a = 16,
//    altsyncram_component.width_b = 16,
//    altsyncram_component.width_byteena_a = 1,
//    altsyncram_component.width_byteena_b = 1,
//    altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK1";


video_mixer #(640, 0) mixer
(
    .*,
    .CE_PIXEL       (CE_PIXEL),
    .hq2x           (0),
    .scandoubler    (forced_scandoubler),
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
