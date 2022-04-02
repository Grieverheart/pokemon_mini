module prc
(
    input clk,
    input reset,
    input pk,
    input pl,
    input cpu_write,
    input cpu_read,
    input [23:0] address_in,
    input [7:0] data_in,
    output logic [7:0] data_out
);

reg [5:0] mode;
reg [7:0] rate;
reg [23:0] map_base;
reg [23:0] sprite_base;
reg [6:0] scroll_x;
reg [6:0] scroll_y;
reg [6:0] counter;

reg [4:0] map_width;
reg [4:0] map_height;
always_comb
begin
    case(mode[5:4])
        2'd0: 
        begin
            map_width = 12;
            map_height = 16;
        end

        2'd1:
        begin
            map_width = 16;
            map_height = 12;
        end

        2'd2:
        begin
            map_width = 24;
            map_height = 8;
        end

        2'd3:
        begin
            map_width = 24;
            map_height = 16;
        end
    endcase
end

reg [3:0] rate_match;
always_comb
begin
    case(rate[3:1])
        3'h0: rate_match = 4'h2; // Rate /3
        3'h1: rate_match = 4'h5; // Rate /6
        3'h2: rate_match = 4'h8; // Rate /9
        3'h3: rate_match = 4'hB; // Rate /12
        3'h4: rate_match = 4'h1; // Rate /2
        3'h5: rate_match = 4'h3; // Rate /4
        3'h6: rate_match = 4'h5; // Rate /6
        3'h7: rate_match = 4'h7; // Rate /8
    endcase
end

always_ff @ (posedge clk, posedge reset)
begin
    if(reset)
    begin
        counter     <= 7'd0;
        mode        <= 6'h0;
        rate        <= 8'h0;
        map_base    <= 24'h0;
        sprite_base <= 24'h0;
        scroll_x    <= 7'd0;
        scroll_y    <= 7'd0;
    end
    else
    begin
        if(cpu_write)
        begin
            case(address_in)
                24'h2080: // PRC Stage Control
                    mode <= data_in[5:0];

                24'h2081: // PRC Rate Control
                    // Reset the counter when changing the divider.
                    rate <= (rate[3:1] != data_in[3:1])?
                        {4'd0, data_in[3:0]}:
                        {rate[7:4], data_in[3:0]};

                24'h2082: // PRC Map Tile Base Low
                    map_base[7:3] <= data_in[7:3];
                24'h2083: // PRC Map Tile Base Middle
                    map_base[15:8] <= data_in;
                24'h2084: // PRC Map Tile Base High
                    map_base[20:16] <= data_in[4:0];

                24'h2085: // PRC Map Vertical Scroll
                    scroll_y <= data_in[6:0];
                24'h2086: // PRC Map Horizontal Scroll
                    scroll_x <= data_in[6:0];

                24'h2087: // PRC Sprite Tile Base Low
                    sprite_base[7:3] <= data_in[7:3];
                24'h2088: // PRC Sprite Tile Base Middle
                    sprite_base[15:8] <= data_in;
                24'h2089: // PRC Sprite Tile Base High
                    sprite_base[20:16] <= data_in[4:0];

                default:
                begin
                end
            endcase
        end

        // @todo: Do rendering and counting stuff.
    end
end

always_comb
begin
    case(address_in)
		24'h2080: // PRC Stage Control
			data_out = {2'd0, mode};
		24'h2081: // PRC Rate Control
			data_out = rate;
		24'h2082: // PRC Map Tile Base (Lo)
			data_out = map_base[7:0];
		24'h2083: // PRC Map Tile Base (Med)
			data_out = map_base[15:8];
		24'h2084: // PRC Map Tile Base (Hi)
			data_out = map_base[23:16];
		24'h2085: // PRC Map Vertical Scroll
			data_out = {1'd0, scroll_y};
		24'h2086: // PRC Map Horizontal Scroll
			data_out = {1'd0, scroll_x};
		24'h2087: // PRC Map Sprite Base (Lo)
			data_out = map_base[7:0];
		24'h2088: // PRC Map Sprite Base (Med)
			data_out = map_base[15:8];
		24'h2089: // PRC Map Sprite Base (Hi)
			data_out = map_base[23:16];
		24'h208A: // PRC Counter
			data_out = {1'd0, counter};
        default:
            data_out = 8'd0;

    endcase
end

endmodule
