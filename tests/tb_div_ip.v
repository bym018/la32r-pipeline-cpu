`timescale 1ns/1ps
module tb_div_ip;
reg clk = 0;
reg reset = 1;
reg start = 0;
reg signed_div;
reg [31:0] dividend, divisor;
wire done;
wire [31:0] quotient, remainder;
integer tests = 0;
integer i;
reg [31:0] a, b;

div_unit dut(clk, reset, start, signed_div, dividend, divisor,
             done, quotient, remainder);
always #5 clk = ~clk;

task check;
    input [31:0] x, y;
    input sign_mode;
    reg [31:0] expected_q, expected_r;
    reg signed [63:0] sx, sy;
    integer cycles;
    begin
        sx = {{32{x[31]}}, x}; sy = {{32{y[31]}}, y};
        if (sign_mode) begin
            expected_q = sx / sy;
            expected_r = sx % sy;
        end
        else begin
            expected_q = x / y;
            expected_r = x % y;
        end
        @(negedge clk);
        dividend = x; divisor = y; signed_div = sign_mode; start = 1;
        @(negedge clk);
        start = 0; dividend = ~x; divisor = ~y; signed_div = !sign_mode;
        cycles = 0;
        while (!done && cycles < 100) begin
            @(negedge clk); cycles = cycles + 1;
        end
        if (!done || (y != 0 && (quotient !== expected_q || remainder !== expected_r)))
            $fatal(1, "IP x=%h y=%h signed=%b q=%h/%h r=%h/%h cycles=%0d",
                   x, y, sign_mode, quotient, expected_q, remainder, expected_r, cycles);
        repeat (3) @(negedge clk);
        if (!done) $fatal(1, "Result valid not held");
        tests = tests + 1;
    end
endtask

initial begin
    repeat (5) @(negedge clk);
    reset = 0;
    check(13, 3, 0);
    check(-13, 3, 1);
    check(13, -3, 1);
    check(-13, -3, 1);
    check(32'h80000000, 32'hffffffff, 1);
    check(32'hffffffff, 32'h80000000, 0);
    check(0, 7, 1);
    check(7, 0, 0);
    for (i = 0; i < 200; i = i + 1) begin
        a = $random; b = $random;
        check(a, b, i % 2);
    end
    @(negedge clk);
    start = 1; dividend = 123; divisor = 7; signed_div = 0;
    @(negedge clk); start = 0;
    repeat (4) @(negedge clk);
    reset = 1;
    repeat (4) @(negedge clk);
    if (done) $fatal(1, "Reset did not cancel pending result");
    reset = 0;
    check(100, 3, 0);
    $display("PASS: Xilinx Divider Generator, %0d cases, input capture, held result, reset", tests);
    $finish;
end
initial begin
    #1000000;
    $fatal(1, "IP timeout");
end
endmodule
