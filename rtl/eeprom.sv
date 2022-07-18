module eeprom
(
    input clk,
    input reset,
    input ce,
    input data_in,
    output data_out
);
    localparam [2:0]
        EEPROM_STATE_IDLE              = 3'd0,
        EEPROM_STATE_START_TRANSFER    = 3'd1,
        EEPROM_STATE_READ_ADDRESS_HIGH = 3'd2,
        EEPROM_STATE_READ_ADDRESS_LOW  = 3'd3,
        EEPROM_STATE_DATA_READ         = 3'd4,
        EEPROM_STATE_DATA_WRITE        = 3'd5;

    reg clock_posedge;
    reg data_latch;
    reg reg_data_out;
    reg [7:0] input_byte;
    reg [12:0] address;
    reg [2:0] state;
    reg [3:0] bit_count;
    // @todo: Move to explicit bram?
    (* ramstyle = "no_rw_check" *) reg [7:0] rom[0:8191];

    assign data_out = reg_data_out & data_latch;

    reg [7:0] rom_read;
    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            clock_posedge <= 0;
            state         <= EEPROM_STATE_IDLE;
            reg_data_out  <= 1'd1;
            input_byte    <= 8'd0;
        end
        else
        begin
            rom_read <= rom[address];
            clock_posedge <= ce;
            data_latch <= data_in;

            // On data edge.
            if(ce && (data_latch != data_in))
            begin
                if(!data_in)
                begin
                    bit_count  <= 4'd0;
                    input_byte <= 8'd0;
                    state      <= EEPROM_STATE_START_TRANSFER;
                end
                else
                begin
                    state <= EEPROM_STATE_IDLE;
                    reg_data_out <= 1'd1;
                end
            end

            // On clock edge.
            if(ce != clock_posedge)
            begin
                if(ce)
                begin
                    if(state != EEPROM_STATE_DATA_READ)
                        input_byte <= {input_byte[6:0], data_latch};
                    else
                    begin
                        if(bit_count == 4'd0)
                        begin
                            if(data_out) // Basically (data_latch & reg_io_dir[2]).
                            begin
                                state <= EEPROM_STATE_IDLE;
                                reg_data_out <= 1'd1;
                            end
                        end
                        else
                        begin
                            reg_data_out <= input_byte[7];
                            input_byte <= {input_byte[6:0], 1'd0};
                        end
                    end
                end
                else
                begin
                    if(state != EEPROM_STATE_DATA_READ)
                        reg_data_out <= 1'd1;
                    bit_count <= bit_count + 1;

                    if(bit_count == 4'd8)
                    begin
                        bit_count <= 4'd0;
                        if(state == EEPROM_STATE_START_TRANSFER)
                        begin
                            if(input_byte == 8'hA0)
                            begin
                                state <= EEPROM_STATE_READ_ADDRESS_HIGH;
                                address <= 13'd0;
                                reg_data_out <= 1'd0;
                            end
                            else if(input_byte == 8'hA1)
                            begin
                                //$display("Reading byte 0x%x at %d", rom[address], address);
                                state <= EEPROM_STATE_DATA_READ;
                                input_byte <= rom_read;
                                reg_data_out <= 1'd0;
                                address <= address + 1;
                            end
                            else
                            begin
                                state <= EEPROM_STATE_IDLE;
                                reg_data_out <= 1'd1;
                            end

                        end
                        else if(state == EEPROM_STATE_READ_ADDRESS_HIGH)
                        begin
                            address[12:8] <= input_byte[4:0];
                            state <= EEPROM_STATE_READ_ADDRESS_LOW;
                            reg_data_out <= 1'd0;
                        end
                        else if(state == EEPROM_STATE_READ_ADDRESS_LOW)
                        begin
                            address[7:0] <= input_byte;
                            state <= EEPROM_STATE_DATA_WRITE;
                            reg_data_out <= 1'd0;
                        end
                        else if(state == EEPROM_STATE_DATA_WRITE)
                        begin
                            //$display("Wrote byte 0x%x at %d", input_byte, address);
                            rom[address] <= input_byte;
                            address <= address + 1;
                            reg_data_out <= 1'd0;
                        end
                        else if(state == EEPROM_STATE_DATA_READ)
                        begin
                            // @todo: Oops, wee need to set the input byte
                            // again?
                            //$display("Reading byte 0x%x at %d", rom[address], address);
                            address <= address + 1;
                            input_byte <= rom_read;
                            reg_data_out <= 1'd1;
                        end
                    end
                end
            end
        end
    end

endmodule
