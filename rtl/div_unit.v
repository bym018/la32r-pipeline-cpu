module div_unit(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        signed_div,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    output reg         done,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder
);

wire [31:0] dividend_abs;
wire [31:0] divisor_abs;
wire [63:0] ip_result;
wire        ip_valid;
reg         pending;
reg         quotient_neg;
reg         remainder_neg;

assign dividend_abs = signed_div && dividend[31] ? -dividend : dividend;
assign divisor_abs  = signed_div && divisor[31] ? -divisor : divisor;

div_unsigned u_div_ip(
    .aclk                   (clk),
    .aresetn                (!reset),
    .s_axis_dividend_tvalid  (start && !reset),
    .s_axis_dividend_tdata   (dividend_abs),
    .s_axis_divisor_tvalid   (start && !reset),
    .s_axis_divisor_tdata    (divisor_abs),
    .m_axis_dout_tvalid      (ip_valid),
    .m_axis_dout_tdata       (ip_result)
);

always @(posedge clk) begin
    if (reset) begin
        done <= 1'b0;
        pending <= 1'b0;
        quotient <= 32'b0;
        remainder <= 32'b0;
    end
    else if (start) begin
        done <= 1'b0;
        pending <= 1'b1;
        quotient_neg <= signed_div && (dividend[31] ^ divisor[31]);
        remainder_neg <= signed_div && dividend[31];
    end
    else if (pending && ip_valid) begin
        quotient <= quotient_neg ? -ip_result[63:32] : ip_result[63:32];
        remainder <= remainder_neg ? -ip_result[31:0] : ip_result[31:0];
        done <= 1'b1;
        pending <= 1'b0;
    end
end

endmodule
