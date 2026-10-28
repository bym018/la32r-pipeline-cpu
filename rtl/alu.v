module alu(
  input  wire [20:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_slti;  //signed compared and set less than imm
wire op_sltu;  //unsigned compared and set less than
wire op_sltui; //unsigned compared adn set less than imm
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate
wire op_andi;  //bitwise and immediate
wire op_ori;   //bitwise or immediate
wire op_xori;  //bitwise xor immediate
wire op_sll_w; //Shift Left Logic, Word
wire op_srl_w; //Shift Right Logic, Word
wire op_sra_w; //Shift Right Arithmetic, Word
wire op_pcaddu12i; // PC add upper i12

// control code decomposition
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];
assign op_slti = alu_op[12];
assign op_sltui = alu_op[13];
assign op_andi = alu_op[14];
assign op_ori = alu_op[15];
assign op_xori = alu_op[16];
assign op_sll_w = alu_op[17];
assign op_srl_w = alu_op[18];
assign op_sra_w = alu_op[19];
assign op_pcaddu12i = alu_op[20];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu | op_slti | op_sltui) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu | op_slti | op_sltui) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// ADD, SUB result
assign add_sub_result = adder_result;

// SLT/SLTI result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);


// SLTU/SLTUI result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
assign sr64_result = {{32{(op_sra | op_sra_w) & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

// final result mux
assign alu_result = ({32{op_add|op_sub|op_pcaddu12i}} & add_sub_result)
                  | ({32{op_slt|op_slti       }} & slt_result)
                  | ({32{op_sltu|op_sltui}} & sltu_result)
                  | ({32{op_and|op_andi       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or|op_ori        }} & or_result)
                  | ({32{op_xor|op_xori       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll|op_sll_w       }} & sll_result)
                  | ({32{op_srl|op_sra|op_srl_w|op_sra_w}} & sr_result);

endmodule
