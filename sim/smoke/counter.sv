// Toolchain smoke test only; not part of the core.
module counter (
    input  logic       clk,
    input  logic       rst_n,
    output logic [7:0] count
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) count <= '0;
        else        count <= count + 8'd1;
    end
endmodule
