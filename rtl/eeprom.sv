module eeprom
(
    input clk,
    input reset,
    input ce,
    input data_in,
    output data_out
);
    localparam [2:0]
        EEPROM_STATE_IDLE           = 3'd0,
        EEPROM_STATE_START_TRANSFER = 3'd1,
        EEPROM_STATE_ACKNOWLEDGE    = 3'd2,
        EEPROM_STATE_READ_ADDRESS   = 3'd3,
        EEPROM_STATE_DATA_READ      = 3'd4,
        EEPROM_STATE_DATA_WRITE     = 3'd5;

    reg clock_posedge;
    reg data_latch;
    reg reg_data_out;
    reg [7:0] control_byte;
    reg [12:0] address;
    reg [2:0] state;
    reg [3:0] bit_count;

    assign data_out = reg_data_out & data_latch;

    always_ff @ (posedge clk, posedge reset)
    begin
        if(reset)
        begin
            clock_posedge <= 0;
            state         <= EEPROM_STATE_IDLE;
            control_byte  <= 8'd0;
            reg_data_out  <= 1'd1;
        end
        else
        begin
            clock_posedge <= ce;
            data_latch <= data_in;

            // On data edge.
            if(ce && (data_latch != data_in))
            begin
                if(!data_in)
                begin
                    $display("start");
                    state <= EEPROM_STATE_START_TRANSFER;
                    bit_count <= 4'd0;
                end
                else
                begin
                    $display("stop");
                    state <= EEPROM_STATE_IDLE;
                    reg_data_out <= 1'd1;
                end
            end

            // On clock edge.
            if(ce != clock_posedge)
            begin
                if(ce)
                begin
                    reg_data_out <= 1'd1;
                    // @note: In principle I should probably set data on the
                    // negative edge and after making sure the data was stable
                    // for the duration of the high period of the clock
                    // signal. This is easier, though. Otherwise, I'd have to
                    // add another Acknowledge state which triggers on the
                    // positive edge.
                    if(state == EEPROM_STATE_START_TRANSFER)
                    begin
                        control_byte <= {control_byte[6:0], data_in};
                        bit_count <= bit_count + 1;

                        if(bit_count == 4'd7)
                        begin
                            $display("control byte received");
                            state <= EEPROM_STATE_ACKNOWLEDGE;
                            bit_count <= 4'd0;
                            reg_data_out <= 1'd0;
                        end
                    end
                    else if(state == EEPROM_STATE_ACKNOWLEDGE)
                    begin
                        $display("acknowledge");
                        if(control_byte == 8'hA0)
                        begin
                            state <= EEPROM_STATE_READ_ADDRESS;
                            address <= 13'd0;
                        end
                        else if(control_byte == 8'hA1)
                        begin
                            state <= EEPROM_STATE_DATA_READ;
                        end
                    end
                    else if(state == EEPROM_STATE_READ_ADDRESS)
                    begin
                        address <= {address[11:0], data_in};
                        bit_count <= bit_count + 1;
                    end
                end
                else
                begin
                end
            end
        end
    end

endmodule
