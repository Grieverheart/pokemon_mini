module key_input
(
    input reset,
    input [7:0] keys_active,
    input [23:0] bus_address_in,
    output logic [7:0] bus_data_out
);

wire [7:0] reg_keys = reset ? 8'hFF: ~keys_active;

always_comb
begin
    bus_data_out = 0;
    if(bus_address_in == 24'h2052)
        bus_data_out = reg_keys;
end

endmodule
