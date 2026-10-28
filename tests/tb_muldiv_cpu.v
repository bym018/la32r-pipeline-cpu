`timescale 1ns/1ps
module tb_muldiv_cpu;
reg clk = 0;
reg resetn = 0;
wire ien, den;
wire [3:0] iwe, dwe, wb_we;
wire [31:0] ia, idata, dw, da, pc, wb_data;
wire [4:0] wb_dest;
reg [31:0] ir, dr;
reg [31:0] imem [0:63];
reg [31:0] dmem [0:15];
reg [31:0] expected [0:63];
integer length = 0;
integer writes = 0;
integer i;

mycpu_top cpu(clk, resetn, iwe, ien, ia, idata, ir,
              dwe, den, da, dw, dr, pc, wb_we, wb_dest, wb_data);
always #5 clk = ~clk;
always @(posedge clk) begin
    if (ien) ir <= imem[ia[7:2]];
    if (den) begin
        dr <= dmem[da[5:2]];
        for (integer k = 0; k < 4; k = k + 1)
            if (dwe[k]) dmem[da[5:2]][k*8 +: 8] <= dw[k*8 +: 8];
    end
end

function [31:0] rr;
    input [31:0] opcode;
    input [4:0] rd, rj, rk;
    rr = opcode | (rk << 10) | (rj << 5) | rd;
endfunction
function [31:0] ri;
    input [31:0] opcode;
    input [4:0] rd, rj;
    input [11:0] imm;
    ri = opcode | (imm << 10) | (rj << 5) | rd;
endfunction
task emit;
    input [31:0] word, result;
    begin
        imem[length] = word;
        expected[length] = result;
        length = length + 1;
    end
endtask

initial begin
    for (i = 0; i < 64; i = i + 1) imem[i] = 32'h50000000;
    for (i = 0; i < 16; i = i + 1) dmem[i] = 0;
    dmem[0] = 32'h80000000;
    emit(ri('h02800000, 4, 0, -13), -13);
    emit(ri('h02800000, 5, 0, 3), 3);
    emit(rr('h00200000, 6, 4, 5), -4);   // div.w
    emit(rr('h00208000, 7, 4, 5), -1);   // mod.w, consecutive division
    emit(rr('h00100000, 8, 6, 7), -5);   // dependent add
    emit(rr('h001c0000, 9, 8, 5), -15);  // mul.w
    emit(rr('h001c8000, 10, 4, 5), -1);  // mulh.w
    emit(rr('h001d0000, 11, 4, 5), 2);   // mulh.wu
    emit(rr('h00210000, 12, 4, 5), 'h55555551);
    emit(rr('h00218000, 13, 4, 5), 0);
    emit(ri('h28800000, 14, 0, 0), 'h80000000);
    emit(ri('h02800000, 15, 0, -1), -1);
    emit(rr('h00200000, 16, 14, 15), 'h80000000); // MIN/-1
    emit(rr('h00208000, 17, 14, 15), 0);
    emit(ri('h28800000, 18, 0, 0), 'h80000000);
    emit(rr('h00210000, 19, 18, 5), 'h2aaaaaaa); // immediate load dependency
    emit(rr('h00200000, 20, 6, 5), -1); // division consuming prior result
    emit(rr('h00208000, 21, 6, 5), -1);
    emit(rr('h001c0000, 22, 20, 21), 1);
    // A load holds MEM while division starts in EX.
    emit(ri('h28800000, 23, 0, 0), 'h80000000);
    emit(rr('h00200000, 24, 4, 5), -4);
    emit(rr('h00100000, 25, 24, 22), -3);
    imem[length] = ri('h29800000, 25, 0, 4); // store forwarded div-dependent data
    imem[length+1] = ri('h28800000, 26, 0, 4);
    expected[length+1] = -3;
    repeat (10) @(negedge clk);
    resetn = 1;
    #30000;
    $fatal(1, "CPU test timeout");
end

always @(posedge clk) begin
    if (resetn && |wb_we && wb_dest != 0) begin
        if (pc[7:2] > length+1 || wb_data !== expected[pc[7:2]])
            $fatal(1, "CPU pc=%h dest=%d value=%h expected=%h", pc, wb_dest, wb_data, expected[pc[7:2]]);
        if (pc[7:2] < length && wb_dest !== pc[7:2]+4)
            $fatal(1, "CPU destination mismatch");
        writes = writes + 1;
        if (pc[7:2] == length+1) begin
            if (writes != length+1) $fatal(1, "Missing or repeated writeback");
            $display("PASS: dense CPU mul/div/mod, all seven ops, load dependencies, MEM stall, forwarded store");
            $finish;
        end
    end
end
endmodule
