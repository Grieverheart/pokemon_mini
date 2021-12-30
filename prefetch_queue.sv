
module prefetch_queue
(
    input clk,
    input reset,
    input pop,
    input push,
    input [15:0] PC,
    input [15:0] data_in,

    // @todo: Add arguments for writing PFP, i.e. to set it to a new location
    // after a jump. In this case, the queue should also be flushed so we need
    // to set write_idx <= 0.

    output reg [15:0] PFP,
    output [7:0] data_out,
    output empty,
    output full
);
    reg [127:0] buffer;
    reg [4:0] write_idx;


    assign data_out = buffer[7:0];
    assign empty = (write_idx == 0);
    assign full  = (write_idx > 5'd14); // Full if at most 1 byte free.

    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            PFP       <= PC;
            write_idx <= 0;
        end
        else
        begin
            // In case both things happen, either 0 or 1 bytes will be added
            // to the queue.
            if(push && pop && !empty && !full)
            begin
                if(PFP[0] == 0)
                begin
                    write_idx <= write_idx + 1;
                    PFP <= PFP + 2;

                    case(write_idx)
                        1:  buffer <= {112'd0, data_in};
                        2:  buffer <= {104'd0, data_in, buffer[15:8]};
                        3:  buffer <= { 96'd0, data_in, buffer[23:8]};
                        4:  buffer <= { 88'd0, data_in, buffer[31:8]};
                        5:  buffer <= { 80'd0, data_in, buffer[39:8]};
                        6:  buffer <= { 72'd0, data_in, buffer[47:8]};
                        7:  buffer <= { 64'd0, data_in, buffer[55:8]};
                        8:  buffer <= { 56'd0, data_in, buffer[63:8]};
                        9:  buffer <= { 48'd0, data_in, buffer[71:8]};
                        10: buffer <= { 40'd0, data_in, buffer[79:8]};
                        11: buffer <= { 32'd0, data_in, buffer[87:8]};
                        12: buffer <= { 24'd0, data_in, buffer[95:8]};
                        13: buffer <= { 16'd0, data_in, buffer[103:8]};
                        14: buffer <= {  8'd0, data_in, buffer[111:8]};
                    endcase
                end
                // The size of the queue will not change.
                else
                begin
                    PFP <= PFP + 1;

                    case(write_idx)
                        1:  buffer <= {120'd0, data_in[7:0]};
                        2:  buffer <= {112'd0, data_in[7:0], buffer[15:8]};
                        3:  buffer <= {104'd0, data_in[7:0], buffer[23:8]};
                        4:  buffer <= { 96'd0, data_in[7:0], buffer[31:8]};
                        5:  buffer <= { 88'd0, data_in[7:0], buffer[39:8]};
                        6:  buffer <= { 80'd0, data_in[7:0], buffer[47:8]};
                        7:  buffer <= { 72'd0, data_in[7:0], buffer[55:8]};
                        8:  buffer <= { 64'd0, data_in[7:0], buffer[63:8]};
                        9:  buffer <= { 56'd0, data_in[7:0], buffer[71:8]};
                        10: buffer <= { 48'd0, data_in[7:0], buffer[79:8]};
                        11: buffer <= { 40'd0, data_in[7:0], buffer[87:8]};
                        12: buffer <= { 32'd0, data_in[7:0], buffer[95:8]};
                        13: buffer <= { 24'd0, data_in[7:0], buffer[103:8]};
                        14: buffer <= { 16'd0, data_in[7:0], buffer[111:8]};
                    endcase
                end
            end
            else if(push && !full)
            begin
                if(PFP[0] == 0)
                begin
                    write_idx <= write_idx + 2;
                    PFP <= PFP + 2;

                    case(write_idx)
                        0:  buffer <= {112'd0, data_in};
                        1:  buffer <= {104'd0, data_in, buffer[7:0]};
                        2:  buffer <= { 96'd0, data_in, buffer[15:0]};
                        3:  buffer <= { 88'd0, data_in, buffer[23:0]};
                        4:  buffer <= { 80'd0, data_in, buffer[31:0]};
                        5:  buffer <= { 72'd0, data_in, buffer[39:0]};
                        6:  buffer <= { 64'd0, data_in, buffer[47:0]};
                        7:  buffer <= { 56'd0, data_in, buffer[55:0]};
                        8:  buffer <= { 48'd0, data_in, buffer[63:0]};
                        9:  buffer <= { 40'd0, data_in, buffer[71:0]};
                        10: buffer <= { 32'd0, data_in, buffer[79:0]};
                        11: buffer <= { 24'd0, data_in, buffer[87:0]};
                        12: buffer <= { 16'd0, data_in, buffer[95:0]};
                        13: buffer <= {  8'd0, data_in, buffer[103:0]};
                        14: buffer <= {data_in, buffer[111:0]};
                    endcase

                end
                else
                begin
                    // When PFP is odd, we can only fetch a single byte.
                    write_idx <= write_idx + 1;
                    PFP <= PFP + 1;

                    case(write_idx)
                        0:  buffer <= {120'd0, data_in[7:0]};
                        1:  buffer <= {112'd0, data_in[7:0], buffer[7:0]};
                        2:  buffer <= {104'd0, data_in[7:0], buffer[15:0]};
                        3:  buffer <= { 96'd0, data_in[7:0], buffer[23:0]};
                        4:  buffer <= { 88'd0, data_in[7:0], buffer[31:0]};
                        5:  buffer <= { 80'd0, data_in[7:0], buffer[39:0]};
                        6:  buffer <= { 72'd0, data_in[7:0], buffer[47:0]};
                        7:  buffer <= { 64'd0, data_in[7:0], buffer[55:0]};
                        8:  buffer <= { 56'd0, data_in[7:0], buffer[63:0]};
                        9:  buffer <= { 48'd0, data_in[7:0], buffer[71:0]};
                        10: buffer <= { 40'd0, data_in[7:0], buffer[79:0]};
                        11: buffer <= { 32'd0, data_in[7:0], buffer[87:0]};
                        12: buffer <= { 24'd0, data_in[7:0], buffer[95:0]};
                        13: buffer <= { 16'd0, data_in[7:0], buffer[103:0]};
                        14: buffer <= {  8'd0, data_in[7:0], buffer[111:0]};
                    endcase
                end
            end

            else if(pop && !empty)
            begin
                write_idx <= write_idx - 1;
                buffer <= {8'b0, buffer[127:8]};
            end
        end
    end

endmodule;

