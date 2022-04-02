module lcd_controller
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

// @todo: Handle contrast.
// @todo: Handle reading out of the lcd_data. Can either be done with
// additional inputs/outputs, or using the standard controller interface.

reg [5:0] contrast;
reg contrast_set;
reg display_enabled;
reg segment_driver_direction;
reg read_modify_mode;
reg max_contrast_enabled;
reg all_pixels_on_enabled;
reg invert_pixels_enabled;
reg row_order;
reg [5:0] start_line;
reg [7:0] column;
reg [3:0] page;

// (0-8, pages 0-7 are 8px high, Page 8 = 1px high)
reg [7:0] lcd_data[9*132];


wire [10:0] pixel_address = (11'd132 << page) + (
    (segment_driver_direction)?
        131 - {3'd0, column}:
        {3'd0, column});

always_ff @ (posedge clk, posedge reset)
begin
    if(reset)
    begin
        contrast_set             <= 0;
        start_line               <= 0;
        display_enabled          <= 0;
        segment_driver_direction <= 0;
        read_modify_mode         <= 0;
        column                   <= 8'd0;
        page                     <= 4'd0;
    end
    else
    begin
        if(cpu_write)
        begin
            case(address_in)
                24'h20FE:
                begin
                    if(contrast_set)
                    begin
                        contrast_set <= 0;
                        contrast <= data_in[5:0];
                    end
                    else
                    begin
                        casez(data_in)
                            8'b0000_????:
                            begin
                                if(!read_modify_mode)
                                    column <= {column[7:4], data_in[3:0]};
                            end
                            8'b0001_????:
                            begin
                                if(!read_modify_mode)
                                    column <= {data_in[3:0], column[3:0]};
                            end
                            8'b01??_????:
                                // Set starting LCD scanline (cause warp around)
                                start_line <= data_in[5:0];

                            8'b1000_0001:
                                // Set contrast at the next write
                                contrast_set <= 1;

                            8'b1010_000?:
                                // Segment Driver Direction Select, Normal
                                segment_driver_direction <= data_in[0];

                            8'b1010_001?:
                                // Max Contrast, Disable
                                max_contrast_enabled <= data_in[0];

                            8'b1010_010?:
                                // Set All Pixels, Disable
                                all_pixels_on_enabled <= data_in[0];

                            8'b1010_011?:
                                // Invert All Pixels, Disable
                                invert_pixels_enabled <= data_in[0];

                            8'b1010_111?:
                                // Display Off
                                display_enabled <= data_in[0];

                            8'b1011_????:
                                // Set page (0-8, each page is 8px high)
                                page <= data_in[3:0];

                            8'b1100_????:
                                // Display rows from top to bottom as 0 to 63
                                row_order <= data_in[3];

                            8'b1110_0000:
                                // Start "Read Modify Write"
                                read_modify_mode <= 1;
                                //MinxLCD.RMWColumn = MinxLCD.Column;

                            8'b1110_0010:
                            begin
                                // Reset
                                contrast_set                 <= 0;
                                contrast                     <= 6'h20;
                                column                       <= 0;
                                start_line                   <= 0;
                                segment_driver_direction     <= 0;
                                max_contrast_enabled         <= 0;
                                all_pixels_on_enabled        <= 0;
                                invert_pixels_enabled        <= 0;
                                display_enabled              <= 0;
                                page                         <= 0;
                                row_order                    <= 0;
                                read_modify_mode             <= 0;
                            end

                            8'b1110_1110:
                                // End "Read Modify Write"
                                read_modify_mode <= 0;
                                //MinxLCD.Column = MinxLCD.RMWColumn;

                            default:
                            begin
                            end
                        endcase
                    end
                end
                24'h20FF:
                begin
                    if(contrast_set)
                    begin
                        contrast_set <= 0;
                        contrast <= data_in[5:0];
                    end
                    else
                    begin
                        lcd_data[pixel_address] = data_in;
                        column <= (column < 8'd131)? column + 8'd1: 8'd131;
                    end
                end

            endcase
        end
        else if(cpu_read)
        begin
            case(address_in)
                24'h20FE:
                begin
                    if(contrast_set)
                    begin
                        contrast_set <= 0;
                        contrast <= 6'h3F;
                    end
                end
                24'h20FF:
                begin
                    if(!read_modify_mode && pk == 1)
                    begin
                        // How often is it increased? Do we need to receive
                        // pl/pk and only run this when e.g. pk == 1?
                        column <= (column < 8'd131)? column + 8'd1: 8'd131;
                    end
                end
            endcase
        end
    end
end

always_comb
begin
    if(contrast_set)
        data_out = 8'd0;
    else
    begin
        case(address_in)
            24'h20FE:
                data_out = 8'h40 | (display_enabled ? 8'h20: 8'h00);

            24'h20FF:
            begin
                data_out = lcd_data[pixel_address];
                if(page >= 8)
                     data_out = {7'd0, data_out[0]};
            end

            default:
                data_out = 8'd0;

        endcase
    end
end

endmodule