module eeprom
(
    input clk,
    input reset,
    input ce,
    input data_in,
    output logic data_out
);
    localparam [1:0]
        EEPROM_STATE_IDLE           = 2'd0,
        EEPROM_STATE_START_TRANSFER = 2'd1;

    reg clock_posedge;
    reg data_latch;
    reg [7:0] control_byte;
    reg [1:0] state;
    reg [2:0] bit_count;

    always_ff @ (posedge clk, posedge reset)
    begin
        if(reset)
        begin
            clock_posedge <= 0;
            state         <= EEPROM_STATE_IDLE;
            control_byte  <= 8'd0;
            data_out      <= 1'd0;
        end
        else
        begin
            clock_posedge <= ce;
            data_latch <= data_in;

            // On data edge.
            if(ce && (data_latch != data_in))
            begin
                if(data_in)
                begin
                    state <= EEPROM_STATE_START_TRANSFER;
                    bit_count <= 3'd0;
                end
                else
                begin
                    state <= EEPROM_STATE_IDLE;
                end
            end

            // On clock edge.
            if(ce != clock_posedge)
            begin
                if(ce)
                begin
                    // @note: In principle I should probably set data on the
                    // negative edge and after making sure the data was stable
                    // for the duration of the high period of the clock
                    // signal. This is easier, though. Otherwise, I'd have to
                    // add another Acknowledge state which triggers on the
                    // positive edge.
                    if(state == EEPROM_STATE_START_TRANSFER)
                    begin
                        control_byte <= {control_byte[7:1], data_in};
                        bit_count <= bit_count + 1;

                        if(bit_count == 3'd7)
                            data_out <= 1'd0;
                    end
                end
                else
                begin
                end
            end
        end
    end

endmodule
