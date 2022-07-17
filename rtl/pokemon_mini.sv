// A simple system-on-a-chip (SoC) for the MiST
// (c) 2015 Till Harbaum

// VGA controller generating 160x100 pixles. The VGA mode ised is 640x400
// combining every 4 row and column

// http://tinyvga.com/vga-timing/640x400@70Hz

module pokemon_mini
(
    // pixel clock
    input  pclk,
    input reset,
    // VGA output
    output reg   hs,
    output reg   vs,
    output [7:0] r,
    output [7:0] g,
    output [7:0] b,
    output VGA_DE
);

    // 640x400 70HZ VESA according to  http://tinyvga.com/vga-timing/640x400@70Hz

    parameter H   = 640;    // width of visible area
    parameter HFP = 16;     // unused time before hsync
    parameter HS  = 96;     // width of hsync
    parameter HBP = 48;     // unused time after hsync

    parameter V   = 400;    // height of visible area
    parameter VFP = 12;     // unused time before vsync
    parameter VS  = 2;      // width of vsync
    parameter VBP = 35;     // unused time after vsync


    reg[9:0]  h_cnt;        // horizontal pixel counter
    reg[9:0]  v_cnt;        // vertical pixel counter

    reg hblank;
    reg vblank;

    // both counters count from the begin of the visibla area

    // horizontal pixel counter
    always@(posedge pclk) begin
        if(h_cnt==H+HFP+HS+HBP-1)   h_cnt <= 10'b0;
        else                        h_cnt <= h_cnt + 10'b1;

        // generate negative hsync signal
        if(h_cnt == H+HFP)    hs <= 1'b0;
        if(h_cnt == H+HFP+HS) hs <= 1'b1;
        if(h_cnt == H+HFP+HS) hblank <= 1'b1; else hblank<=1'b0;

        end

    // veritical pixel counter
    always@(posedge pclk) begin
        // the vertical counter is processed at the begin of each hsync
        if(h_cnt == H+HFP) begin
            if(v_cnt==VS+VBP+V+VFP-1)  v_cnt <= 10'b0; 
            else                               v_cnt <= v_cnt + 10'b1;

                // generate positive vsync signal
            if(v_cnt == V+VFP)    vs <= 1'b1;
            if(v_cnt == V+VFP+VS) vs <= 1'b0;
            if(v_cnt == V+VFP+VS) vblank <= 1'b1; else vblank<=1'b0;
        end
    end

    // read VRAM
    reg [13:0] video_counter;
    reg [7:0] pixel;
    reg de;

    always@(posedge pclk) begin
            // The video counter is being reset at the begin of each vsync.
            // Otherwise it's increased every fourth pixel in the visible area.
            // At the end of the first three of four lines the counter is
            // decreased by the total line length to display the same contents
            // for four lines so 100 different lines are displayed on the 400
            // VGA lines.

        // visible area?
        if((v_cnt < V) && (h_cnt < H)) begin
            if(h_cnt[1:0] == 2'b11)
                video_counter <= video_counter + 14'd1;
            
            pixel <= (v_cnt[2] ^ h_cnt[2])?8'h00:8'hff;    // checkboard
            de<=1;
        end else begin
            if(h_cnt == H+HFP) begin
                if(v_cnt == V+VFP)
                    video_counter <= 14'd0;
                else if((v_cnt < V) && (v_cnt[1:0] != 2'b11))
                    video_counter <= video_counter - 14'd160;
            de<=0;
            end
                
            pixel <= 8'h00;   // black
        end
    end

    // seperate 8 bits into three colors (332)
    assign r = { pixel[7:5],  3'b00000 };
    assign g = { pixel[4:2],  3'b00000 };
    assign b = { pixel[1:0], 4'b000000 };

    //assign VGA_DE  = ~(hblank | vblank);
    assign VGA_DE = de;

    wire [7:0] data_in;
    wire [7:0] data_out;
    wire pk;
    wire pl;
    wire [23:0] address_out;
    wire [1:0]  bus_status;
    wire read;
    wire write;
    wire sync;
    wire iack;
    wire read_interrupt_vector;
    wire [1:0] i01;
    wire [7:0] keys_active;
    wire clk_32768;

    minx minx
    (
        .clk                   (pclk),
        .rt_clk                (clk_32768),
        .reset                 (reset),
        .data_in               (data_in),
        .keys_active           (keys_active),
        .pk                    (pk),
        .pl                    (pl),
        .i01                   (i01),
        .data_out              (data_out),
        .address_out           (address_out),
        .bus_status            (bus_status),
        .read                  (read),
        .read_interrupt_vector (read_interrupt_vector),
        .write                 (write),
        .sync                  (sync),
        .iack                  (iack)
    );

    dpram #(
        .init_file("verilator/data/bios.hex"),
        .widthad_a(24),
        .width_a(8)
    ) vmem
    (
        .clock_a(pclk),
        .address_a(address_out),
        .wren_a(1'b0),
        .q_a(data_in),

        .clock_b(pclk),
        .wren_b(bus_status == 2'd2),
        .address_b(address_out),
        .data_b(data_out)
    );

endmodule
