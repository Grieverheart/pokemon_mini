module prc
(
    input clk,
    input reset,
    input bus_write,
    input bus_read,
    input [23:0] bus_address_in,
    input [7:0] bus_data_in,
    output logic [7:0] bus_data_out,
    output logic [23:0] bus_address_out,
    output logic [1:0]  bus_status,
    output logic write,
    output logic read,
    output logic bus_request,
    input bus_ack,
    output logic irq_copy_complete,
    output logic irq_render_done
);

// @todo: Thinking about taking FR (32.768kHz clock divided by 7?) as input.
// 'reg_counter' will then be driven by this clock, while the rest will run on the
// system clock. Some work is required to actually run simulations with
// multiple clocks.

// @todo: Make PRC work only on posedge. Do we really need set the read/write
// at negedge? Are we going to make use of these 'read'/'write's?

// @todo: What about page 8?

reg [7:0] data_out;
reg [7:0] reg_data_out;
assign bus_data_out = bus_ack? data_out: reg_data_out;

localparam [1:0]
    PRC_STATE_IDLE       = 2'd0,
    PRC_STATE_MAP_DRAW   = 2'd1,
    PRC_STATE_SPR_DRAW   = 2'd2,
    PRC_STATE_FRAME_COPY = 2'd3;

localparam [2:0]
    FRAME_COPY_STATE_COLUMN_SET1 = 3'd0,
    FRAME_COPY_STATE_COLUMN_SET2 = 3'd1,
    FRAME_COPY_STATE_PAGE_SET    = 3'd2,
    FRAME_COPY_STATE_MEM_READ    = 3'd3,
    FRAME_COPY_STATE_LCD_WRITE   = 3'd4;

localparam [2:0]
    SPRITE_DRAW_STATE_READ_TILE_INFO    = 3'd0,
    SPRITE_DRAW_STATE_READ_TILE_ADDRESS = 3'd1,
    SPRITE_DRAW_STATE_READ_POS_Y        = 3'd2,
    SPRITE_DRAW_STATE_READ_POS_X        = 3'd3,
    SPRITE_DRAW_STATE_READ_PIXEL        = 3'd4;

localparam [1:0]
    BUS_COMMAND_IDLE      = 2'd0,
    BUS_COMMAND_IRQ_READ  = 2'd1,
    BUS_COMMAND_MEM_WRITE = 2'd2,
    BUS_COMMAND_MEM_READ  = 2'd3;

reg [5:0] reg_mode;
reg [7:0] reg_rate;
reg [23:0] reg_map_base;
reg [23:0] reg_sprite_base;
reg [6:0] reg_scroll_x;
reg [6:0] reg_scroll_y;
reg [6:0] reg_counter;

reg [1:0] state;
wire [1:0] next_state =
     (state == PRC_STATE_IDLE     && reg_mode[1])? PRC_STATE_MAP_DRAW:
    ((state <= PRC_STATE_MAP_DRAW && reg_mode[2])? PRC_STATE_SPR_DRAW:
    ((state <= PRC_STATE_SPR_DRAW && reg_mode[3])? PRC_STATE_FRAME_COPY:
                                                   PRC_STATE_IDLE));

reg [9:0] prc_osc_counter;
reg bus_cycle;
reg [8:0] execution_step;

reg [4:0] map_width;
reg [4:0] map_height;
always_comb
begin
    case(reg_mode[5:4])
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
    case(reg_rate[3:1])
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

reg [2:0] frame_copy_state;
reg [2:0] sprite_draw_state;
// @todo: Reuse execution_step? Rename to something else e.g.
// prc_stage_state.
task init_next_state(input [1:0] state);
    case(state)
        PRC_STATE_MAP_DRAW:
            execution_step <= 0;

        PRC_STATE_FRAME_COPY:
            frame_copy_state <= FRAME_COPY_STATE_COLUMN_SET1;

        PRC_STATE_SPR_DRAW:
        begin
            sprite_draw_state <= SPRITE_DRAW_STATE_READ_TILE_INFO;
            current_sprite_id <= 5'd23;
        end

        default:
        begin
        end
    endcase
endtask

reg [2:0] yC;
reg [6:0] xC;
reg [4:0] current_sprite_id;
reg [6:0] sprite_x;
reg [6:0] sprite_y;
reg [7:0] sprite_tile_address;
reg [3:0] sprite_info;
wire sprite_enabled = sprite_info[3];
always_ff @ (posedge clk, posedge reset)
begin
    if(reset)
    begin
        prc_osc_counter   <= 10'd0;
        bus_cycle         <= 1'd0;
        reg_counter       <= 7'd1;
        reg_mode          <= 6'h0;
        reg_rate          <= 8'h0;
        reg_map_base      <= 24'h0;
        reg_sprite_base   <= 24'h0;
        reg_scroll_x      <= 7'd0;
        reg_scroll_y      <= 7'd0;
        state             <= PRC_STATE_IDLE;
        yC                <= 0;
        xC                <= 0;
        irq_copy_complete <= 0;
        irq_render_done   <= 0;
        bus_status        <= BUS_COMMAND_IDLE;
    end
    else
    begin
        if(bus_write)
        begin
            case(bus_address_in)
                24'h2080: // PRC Stage Control
                    reg_mode <= bus_data_in[5:0];

                24'h2081: // PRC Rate Control
                    // Reset the reg_counter when changing the divider.
                    reg_rate <= (reg_rate[3:1] != bus_data_in[3:1])?
                        {4'd0, bus_data_in[3:0]}:
                        {reg_rate[7:4], bus_data_in[3:0]};

                24'h2082: // PRC Map Tile Base Low
                    reg_map_base[7:3] <= bus_data_in[7:3];
                24'h2083: // PRC Map Tile Base Middle
                    reg_map_base[15:8] <= bus_data_in;
                24'h2084: // PRC Map Tile Base High
                    reg_map_base[20:16] <= bus_data_in[4:0];

                24'h2085: // PRC Map Vertical Scroll
                    reg_scroll_y <= bus_data_in[6:0];
                24'h2086: // PRC Map Horizontal Scroll
                    reg_scroll_x <= bus_data_in[6:0];

                24'h2087: // PRC Sprite Tile Base Low
                    reg_sprite_base[7:3] <= bus_data_in[7:3];
                24'h2088: // PRC Sprite Tile Base Middle
                    reg_sprite_base[15:8] <= bus_data_in;
                24'h2089: // PRC Sprite Tile Base High
                    reg_sprite_base[20:16] <= bus_data_in[4:0];

                default:
                begin
                end
            endcase
        end

        prc_osc_counter <= prc_osc_counter + 1;

        if(prc_osc_counter == 10'd854)
        begin
            prc_osc_counter <= 10'd0;
            reg_counter <= reg_counter + 1;
            irq_copy_complete  <= 0;
            irq_render_done <= 0;

            if(reg_rate[7:4] == rate_match)
            begin
                // Active frame
                if(reg_counter < 7'h18)
                begin
                    state           <= PRC_STATE_IDLE;
                end
                else if(reg_counter < 7'h42)
                begin
                    // Draw map/sprite or copy frame
                    if(reg_mode[3:1] > 0 && !bus_ack)
                    begin
                        bus_request <= 1;
                        bus_cycle   <= 0;
                        state       <= next_state;
                        init_next_state(next_state);
                    end
                end
                else if(reg_counter == 7'h42)
                begin
                    bus_request     <= 0;
                    reg_counter     <= 7'h1;
                    reg_rate[7:4]   <= 4'd0;
                    irq_render_done <= 1;
                end
            end
            else if(reg_counter == 7'h42)
            begin
                // Non-active frame
                reg_counter   <= 7'd1;
                reg_rate[7:4] <= reg_rate[7:4] + 4'd1;
            end
        end

        if(bus_ack)
        begin
            bus_cycle <= bus_cycle + 1;

            case(state)
                PRC_STATE_MAP_DRAW:
                begin
                    if(!bus_cycle)
                    begin
                        execution_step <= execution_step + 1;

                        if(execution_step % 3 < 2)
                            bus_status <= BUS_COMMAND_MEM_READ;
                        else
                            bus_status <= BUS_COMMAND_MEM_WRITE;

                        if(execution_step % 3 == 0)
                        begin
                            // Read tile address
                            bus_address_out <= 24'h1360 + yC * 12 + {20'd0, xC[6:3]};
                        end
                        else if(execution_step % 3 == 1)
                        begin
                            // Read tile data
                            bus_address_out <= reg_map_base + bus_data_in * 8 + {21'd0, xC[2:0]};
                        end
                        else
                        begin
                            // @note: Perform this at the last posedge step to
                            // avoid changing stuff too early. Ideally I should
                            // either do it on the last negedge, or even better,
                            // make it work only on posedge.

                            data_out <= bus_data_in;
                            bus_address_out <= 24'h1000 + yC * 96 + {16'h0, xC};

                            xC <= xC + 1;
                            if(xC == 7'd95)
                            begin
                                xC <= 0;

                                if(yC == 3'd7)
                                begin
                                    yC <= 0;
                                    state <= next_state;
                                    init_next_state(next_state);
                                    execution_step <= 0;
                                end
                                else
                                    yC <= yC + 1;
                            end
                        end
                    end
                end

                PRC_STATE_SPR_DRAW:
                begin
                    if(!bus_cycle)
                    begin
                        case(sprite_draw_state)
                            SPRITE_DRAW_STATE_READ_TILE_INFO:
                            begin
                                bus_address_out   <= 24'h1300 + {17'd0, current_sprite_id, 2'd3};
                                bus_status        <= BUS_COMMAND_MEM_READ;
                                sprite_draw_state <= SPRITE_DRAW_STATE_READ_TILE_ADDRESS;
                            end
                            SPRITE_DRAW_STATE_READ_TILE_ADDRESS:
                            begin
                                sprite_info       <= bus_data_in[3:0];
                                bus_address_out   <= 24'h1300 + {17'd0, current_sprite_id, 2'd2};
                                bus_status        <= BUS_COMMAND_MEM_READ;
                                sprite_draw_state <= SPRITE_DRAW_STATE_READ_POS_Y;
                            end
                            SPRITE_DRAW_STATE_READ_POS_Y:
                            begin
                                sprite_tile_address <= bus_data_in;
                                bus_address_out     <= 24'h1300 + {17'd0, current_sprite_id, 2'd1};
                                bus_status          <= BUS_COMMAND_MEM_READ;
                                sprite_draw_state   <= SPRITE_DRAW_STATE_READ_POS_X;
                            end
                            SPRITE_DRAW_STATE_READ_POS_X:
                            begin
                                sprite_y          <= bus_data_in[6:0];
                                bus_address_out   <= 24'h1300 + {17'd0, current_sprite_id, 2'd0};
                                bus_status        <= BUS_COMMAND_MEM_READ;
                                current_sprite_id <= (current_sprite_id > 0)? current_sprite_id - 1: 0;

                                if(sprite_enabled)
                                begin
                                    sprite_draw_state <= SPRITE_DRAW_STATE_READ_PIXEL;
                                    current_sprite_id <= current_sprite_id - 1;
                                end
                                else
                                begin
                                    sprite_draw_state <= SPRITE_DRAW_STATE_READ_TILE_INFO;

                                    if(current_sprite_id == 5'd0)
                                    begin
                                        state <= next_state;
                                        init_next_state(next_state);
                                    end
                                end

                            end
                            SPRITE_DRAW_STATE_READ_PIXEL:
                            begin
                                //bus_address_out <= 24'h1000 + yC * 96 + {16'h0, sprite_x + xC};
                            end
                            default:
                            begin
                            end
                        endcase
                    end
                end

                PRC_STATE_FRAME_COPY:
                begin
                    //execution_step <= execution_step + 1;
                    if(!bus_cycle)
                    begin
                        case(frame_copy_state)
                            FRAME_COPY_STATE_COLUMN_SET1:
                            begin
                                frame_copy_state <= FRAME_COPY_STATE_COLUMN_SET2;
                                data_out        <= 8'h10;
                                bus_address_out <= 24'h20FE;
                                bus_status      <= BUS_COMMAND_MEM_WRITE;
                            end
                            FRAME_COPY_STATE_COLUMN_SET2:
                            begin
                                frame_copy_state <= FRAME_COPY_STATE_PAGE_SET;
                                data_out        <= 8'h0;
                                bus_address_out <= 24'h20FE;
                                bus_status      <= BUS_COMMAND_MEM_WRITE;
                            end
                            FRAME_COPY_STATE_PAGE_SET:
                            begin
                                frame_copy_state <= FRAME_COPY_STATE_MEM_READ;
                                data_out        <= {4'hB, 1'h0, yC};
                                bus_address_out <= 24'h20FE;
                                bus_status      <= BUS_COMMAND_MEM_WRITE;
                            end
                            FRAME_COPY_STATE_MEM_READ:
                            begin
                                frame_copy_state <= FRAME_COPY_STATE_LCD_WRITE;
                                bus_address_out <= 24'h1000 + yC * 96 + {16'h0, xC};
                                bus_status      <= BUS_COMMAND_MEM_READ;
                            end
                            FRAME_COPY_STATE_LCD_WRITE:
                            begin
                                frame_copy_state <= FRAME_COPY_STATE_MEM_READ;
                                // Write the data to lcd
                                data_out        <= bus_data_in;
                                bus_address_out <= 24'h20FF;
                                bus_status      <= BUS_COMMAND_MEM_WRITE;

                                xC <= xC + 1;
                                if(xC == 7'd95)
                                begin
                                    xC <= 0;
                                    frame_copy_state <= FRAME_COPY_STATE_COLUMN_SET1;

                                    if(yC == 3'd7)
                                    begin
                                        irq_copy_complete  <= 1;
                                        yC <= 0;
                                        state <= next_state;
                                    end
                                    else
                                        yC <= yC + 1;
                                end
                            end
                            default:
                            begin
                            end
                        endcase
                    end
                end

                default:
                begin
                end
            endcase
        end
    end
end

always_ff @ (negedge clk, posedge reset)
begin
    read  <= 0;
    write <= 0;

    if(bus_cycle)
    begin
        if(bus_status == BUS_COMMAND_MEM_READ)
            read <= 1;
        else if(bus_status == BUS_COMMAND_MEM_WRITE)
            write <= 1;
    end
end

always_comb
begin
    case(bus_address_in)
        24'h2080: // PRC Stage Control
            reg_data_out = {2'd0, reg_mode};
        24'h2081: // PRC Rate Control
            reg_data_out = reg_rate;
        24'h2082: // PRC Map Tile Base (Lo)
            reg_data_out = reg_map_base[7:0];
        24'h2083: // PRC Map Tile Base (Med)
            reg_data_out = reg_map_base[15:8];
        24'h2084: // PRC Map Tile Base (Hi)
            reg_data_out = reg_map_base[23:16];
        24'h2085: // PRC Map Vertical Scroll
            reg_data_out = {1'd0, reg_scroll_y};
        24'h2086: // PRC Map Horizontal Scroll
            reg_data_out = {1'd0, reg_scroll_x};
        24'h2087: // PRC Map Sprite Base (Lo)
            reg_data_out = reg_map_base[7:0];
        24'h2088: // PRC Map Sprite Base (Med)
            reg_data_out = reg_map_base[15:8];
        24'h2089: // PRC Map Sprite Base (Hi)
            reg_data_out = reg_map_base[23:16];
        24'h208A: // PRC Counter
            reg_data_out = {1'd0, reg_counter};
        default:
            reg_data_out = 8'd0;

    endcase
end

endmodule
