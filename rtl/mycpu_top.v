module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire [3:0]  inst_sram_we,
    output wire        inst_sram_en,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire [3:0]  data_sram_we,
    output wire        data_sram_en,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

// ============================================================================
// 0. Clock / reset / bootstrap validity
// ============================================================================
reg         reset;
always @(posedge clk) reset <= ~resetn;

reg         valid;
always @(posedge clk) begin
    if (reset) begin
        valid <= 1'b0;
    end
    else begin
        valid <= 1'b1;
    end
end

// ============================================================================
// 1. Signal map
//
// IF request:       pc -> inst_sram_addr -> inst_sram_rdata (one cycle later)
// IF/ID register:   {if_id_cache_valid, if_id_cache_pc, if_id_cache_inst}
// ID outputs:       decoded control + rj_value/rkd_value + imm
// EX outputs:       alu_result
// MEM output:       mem_result
// WB output:        {rf_we, rf_waddr, rf_wdata}
//
// Five pipeline stages use valid/allowin to hold instructions when needed.
// ============================================================================

// ---- IF: program counter and instruction-SRAM request ---------------------
wire [31:0] seq_pc;
wire [31:0] nextpc;
wire        br_taken;
wire [31:0] br_target;
reg  [31:0] pc;

// ---- IF/ID: the instruction currently being decoded -----------------------
wire [31:0] inst;
wire        id_allowin;
wire        if_id_cache_allowin;
reg  [31:0] if_id_cache_ppc;    // PC sent to SRAM in the previous cycle
reg  [31:0] if_id_cache_pinst;
reg         if_id_cache_pvalid; // validity of that previous request
reg  [31:0] if_id_cache_inst;   // returned instruction
reg  [31:0] if_id_cache_pc;     // PC paired with returned instruction
reg         if_id_cache_valid;  // IF/ID contains a usable instruction

// ---- ID: instruction fields and one-hot opcode decoders -------------------
wire [20:0] alu_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire        mem_byte;
wire        mem_half;
wire        mem_unsigned;
wire        src_reg_is_rd;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

// ---- ID: instruction recognition ------------------------------------------
wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_pcaddu12i;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_div_wu;
wire        inst_mod_w;
wire        inst_mod_wu;
wire [2:0]  mul_op;
wire [2:0]  div_op;

wire        need_ui5;
wire        need_ui12;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

// ---- ID: register-file read and writeback interface -----------------------
wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

// ---- EX / MEM / WB datapath signals ---------------------------------------
wire [31:0] alu_src1   ;
wire [31:0] alu_src2   ;
wire [31:0] alu_result ;
wire [31:0] mem_result;
wire [31:0] final_result;
wire        rj_eq_rd;
wire        rj_lt_rd;
wire        rj_ltu_rd;

// ============================================================================
// IF: update PC and issue an instruction-SRAM read request
// ============================================================================

assign seq_pc       = pc + 3'h4;
assign nextpc       = br_taken ? br_target : seq_pc;

always @(posedge clk) begin
    if (reset) begin
        pc <= 32'h1bfffffc;     //trick: to make nextpc be 0x1c000000 during reset
    end
    else if (if_id_cache_allowin) begin
        pc <= nextpc;
    end
end

assign inst_sram_we    = 4'b0000;
assign inst_sram_en    = valid && if_id_cache_allowin;
assign inst_sram_addr  = pc;
assign inst_sram_wdata = 32'b0;

assign if_id_cache_allowin = !if_id_cache_valid || id_allowin;
// ============================================================================
// IF/ID: pair synchronous-SRAM response with the request from one cycle ago
// Input:  inst_sram_rdata
// Output: if_id_cache_{valid, pc, inst} -> ID
// ============================================================================
always @(posedge clk) begin
      if (reset) begin
          if_id_cache_pvalid <= 1'b0;
          if_id_cache_valid  <= 1'b0;
      end
      else if (br_taken) begin // branch&jump flush
        if_id_cache_pvalid <= 1'b0;
        if_id_cache_valid <= 1'b0;
      end
      else begin
          // fetch last
          if (if_id_cache_allowin) begin
              // keep current request
              if_id_cache_ppc    <= pc;
              if_id_cache_pvalid <= valid;
              if_id_cache_valid <= if_id_cache_pvalid;

              if (if_id_cache_pvalid) begin
                  if_id_cache_inst <= inst_sram_rdata;
                  if_id_cache_pc   <= if_id_cache_ppc;
              end
          end
      end
  end
// IF/ID -> ID connector.  id_allowin will become ID's stall permission later.
assign inst            = if_id_cache_inst;

// ============================================================================
// ID: split instruction fields, recognize opcode, read registers, and create
// control/data outputs for the future ID/EX register.
// ============================================================================

assign op_31_26  = inst[31:26];
assign op_25_22  = inst[25:22];
assign op_21_20  = inst[21:20];
assign op_19_15  = inst[19:15];

assign rd   = inst[ 4: 0];
assign rj   = inst[ 9: 5];
assign rk   = inst[14:10];

assign i12  = inst[21:10];
assign i20  = inst[24: 5];
assign i16  = inst[25:10];
assign i26  = {inst[ 9: 0], inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i = op_31_26_d[6'h07] & (~inst[25]);
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign mul_op = {inst_mulh_wu, inst_mulh_w, inst_mul_w};
assign div_op = {inst_mod_w | inst_mod_wu, inst_div_wu | inst_mod_wu,
                 inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu};

// ALU(EX stage) selector

assign alu_op[ 0] = inst_add_w | inst_addi_w | res_from_mem | mem_we
                    | inst_jirl | inst_bl;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt;
assign alu_op[ 3] = inst_sltu;
assign alu_op[ 4] = inst_and;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or;
assign alu_op[ 7] = inst_xor;
assign alu_op[ 8] = inst_slli_w;
assign alu_op[ 9] = inst_srli_w;
assign alu_op[10] = inst_srai_w;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_slti;
assign alu_op[13] = inst_sltui;
assign alu_op[14] = inst_andi;
assign alu_op[15] = inst_ori;
assign alu_op[16] = inst_xori;
assign alu_op[17] = inst_sll_w;
assign alu_op[18] = inst_srl_w;
assign alu_op[19] = inst_sra_w;
assign alu_op[20] = inst_pcaddu12i;

// imm generator

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
assign need_si12  =  inst_addi_w | res_from_mem | mem_we | inst_slti | inst_sltui;
assign need_si16  =  inst_jirl | inst_beq | inst_bne | inst_blt | inst_bltu | inst_bge | inst_bgeu;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui12 ? {20'b0, i12[11:0]}         :
/*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]} ;

// branch&jump target generator
assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

// ALU(EX stage) source & memRW selector

assign src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bltu | inst_bge | inst_bgeu | mem_we;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       res_from_mem|
                       mem_we      |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_pcaddu12i;

assign res_from_mem  = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
assign dst_is_r1     = inst_bl;
assign gr_we         = ~mem_we & ~inst_beq & ~inst_bne & ~inst_b & ~inst_blt & ~inst_bltu & ~inst_bge & ~inst_bgeu;
assign mem_we        = inst_st_w | inst_st_b | inst_st_h;
assign mem_byte      = inst_ld_b | inst_ld_bu | inst_st_b;
assign mem_half      = inst_ld_h | inst_ld_hu | inst_st_h;
assign mem_unsigned  = inst_ld_bu | inst_ld_hu;
assign dest          = dst_is_r1 ? 5'd1 : rd;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd :rk;
regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );


// data forwarding
wire rdata1_ifcached_alu;
wire rdata1_ifcached_mem;
wire rdata1_ifcached_wb;
wire rdata2_ifcached_alu;
wire rdata2_ifcached_mem;
wire rdata2_ifcached_wb;

assign rdata1_ifcached_alu = (rf_raddr1 == id_ex_cache_dest) && id_ex_cache_valid && id_ex_cache_gr_we && (id_ex_cache_dest != 5'd0);
assign rdata1_ifcached_mem = (rf_raddr1 == ex_mem_cache_dest) && ex_mem_cache_valid && ex_mem_cache_gr_we && (ex_mem_cache_dest != 5'd0);
assign rdata1_ifcached_wb = (rf_raddr1 == mem_wb_cache_dest) && mem_wb_cache_valid && mem_wb_cache_gr_we && (mem_wb_cache_dest != 5'd0);
assign rdata2_ifcached_alu = (rf_raddr2 == id_ex_cache_dest) && id_ex_cache_valid && id_ex_cache_gr_we && (id_ex_cache_dest != 5'd0);
assign rdata2_ifcached_mem = (rf_raddr2 == ex_mem_cache_dest) && ex_mem_cache_valid && ex_mem_cache_gr_we && (ex_mem_cache_dest != 5'd0);
assign rdata2_ifcached_wb = (rf_raddr2 == mem_wb_cache_dest) && mem_wb_cache_valid && mem_wb_cache_gr_we && (mem_wb_cache_dest != 5'd0);

assign rj_value  = rdata1_ifcached_alu ? alu_result : (rdata1_ifcached_mem ? final_result : (rdata1_ifcached_wb ? mem_wb_cache_final_result : rf_rdata1));
assign rkd_value = rdata2_ifcached_alu ? alu_result : (rdata2_ifcached_mem ? final_result : (rdata2_ifcached_wb ? mem_wb_cache_final_result : rf_rdata2));

// Branch decision is resolved in ID for now and feeds back directly to IF.
assign rj_eq_rd = (rj_value == rkd_value);
assign rj_lt_rd = ($signed(rj_value) < $signed(rkd_value));
assign rj_ltu_rd = ($unsigned(rj_value) < $unsigned(rkd_value));
assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_blt  && rj_lt_rd
                   || inst_bltu && rj_ltu_rd
                   || inst_bge  && !rj_lt_rd
                   || inst_bgeu && !rj_ltu_rd
                   || inst_jirl
                   || inst_bl
                   || inst_b
                  ) && if_id_cache_valid && id_allowin;
assign br_target = (inst_beq || inst_bne || inst_bl || inst_b || inst_blt || inst_bltu || inst_bge || inst_bgeu) ? (if_id_cache_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs);

assign alu_src1 = src1_is_pc  ? if_id_cache_pc[31:0] : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;

// ID-EX cache
wire        id_ex_cache_allowin;
wire        id_ready_go;
wire        ex_wait_ld;
wire        mem_wait_ld;
wire        id_uses_rj;
wire        id_uses_rdata2;

reg [31:0] id_ex_cache_pc;           // from IF-ID cache, for branch&jump relative target calculation and debug
reg        id_ex_cache_valid;        // validity state propagated from last cache
reg [31:0] id_ex_cache_sdata;        // data need to store into mem
reg [20:0] id_ex_cache_alu_op;       // alu operation, pass to EX stage
reg [31:0] id_ex_cache_alu_src1;     // alu source selector 1
reg [31:0] id_ex_cache_alu_src2;     // alu source selector 2
reg        id_ex_cache_gr_we;        // regfile we, to WB stage
reg        id_ex_cache_res_from_mem; // regfile writeback source seletor(ALU or mem)
reg [4:0]  id_ex_cache_dest;         // writeback target reg number in regfile
reg        id_ex_cache_mem_we;       // mem we, to MEM stage
reg        id_ex_cache_mem_byte;
reg        id_ex_cache_mem_half;
reg        id_ex_cache_mem_unsigned;
reg [2:0]  id_ex_cache_mul_op;
reg [2:0]  id_ex_cache_div_op;
wire       ex_ready_go;


assign id_ex_cache_allowin = !id_ex_cache_valid || (ex_ready_go && ex_mem_cache_allowin);
// Only actual register operands participate in dependency checks.
assign id_uses_rj = inst_add_w | inst_sub_w | inst_slt | inst_sltu
                 | inst_and | inst_or | inst_xor | inst_nor
                 | inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w
                 | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
                 | inst_sll_w | inst_srl_w | inst_sra_w
                 | (|mul_op) | div_op[0]
                 | res_from_mem | mem_we | inst_beq | inst_bne | inst_jirl | inst_blt | inst_bltu | inst_bge | inst_bgeu;
assign id_uses_rdata2 = inst_add_w | inst_sub_w | inst_slt | inst_sltu
                     | inst_and | inst_or | inst_xor | inst_nor
                     | inst_sll_w | inst_srl_w | inst_sra_w
                     | (|mul_op) | div_op[0]
                     | mem_we | inst_beq | inst_bne | inst_blt | inst_bltu | inst_bge | inst_bgeu;

assign ex_wait_ld = if_id_cache_valid
                 && id_ex_cache_valid
                 && id_ex_cache_res_from_mem
                 && id_ex_cache_gr_we
                 && (id_ex_cache_dest != 5'd0)
                 && ((id_uses_rj && (rf_raddr1 == id_ex_cache_dest))
                 || (id_uses_rdata2 && (rf_raddr2 == id_ex_cache_dest)));

// A newer EX writer takes priority over an older MEM writer of the same reg.
// Otherwise keep ID waiting until the matching MEM load's data is available.
assign mem_wait_ld = if_id_cache_valid
                  && ex_mem_cache_res_from_mem
                  && !mem_ready_go
                  && ((id_uses_rj && !rdata1_ifcached_alu && rdata1_ifcached_mem)
                   || (id_uses_rdata2 && !rdata2_ifcached_alu && rdata2_ifcached_mem));

assign id_ready_go = !ex_wait_ld && !mem_wait_ld;
assign id_allowin  = id_ex_cache_allowin && id_ready_go;

always @(posedge clk) begin
    if (reset) begin
        id_ex_cache_valid <= 1'b0;
    end
    else if (id_ex_cache_allowin) begin
        // validity&pc
        id_ex_cache_valid <= if_id_cache_valid && id_ready_go;
        id_ex_cache_pc <= if_id_cache_pc;
        // selectors&data sources
        id_ex_cache_sdata <= rkd_value;
        id_ex_cache_alu_op <= alu_op;
        id_ex_cache_alu_src1 <= alu_src1;
        id_ex_cache_alu_src2 <= alu_src2;
        id_ex_cache_gr_we <= gr_we;
        id_ex_cache_res_from_mem <= res_from_mem;
        id_ex_cache_dest <= dest;
        id_ex_cache_mem_we <= mem_we;
        id_ex_cache_mem_byte <= mem_byte;
        id_ex_cache_mem_half <= mem_half;
        id_ex_cache_mem_unsigned <= mem_unsigned;
        id_ex_cache_mul_op <= mul_op;
        id_ex_cache_div_op <= div_op;
    end
end

// ============================================================================
// EX: select operands and execute the ALU
// ============================================================================


wire [31:0] base_alu_result;
wire [63:0] product_signed;
wire [63:0] product_unsigned;
wire [31:0] mul_result;
wire [31:0] div_quotient;
wire [31:0] div_remainder;
wire        div_done;
wire        div_start;
reg         div_started;

assign product_signed = $signed(id_ex_cache_alu_src1) * $signed(id_ex_cache_alu_src2);
assign product_unsigned = id_ex_cache_alu_src1 * id_ex_cache_alu_src2;
assign mul_result = id_ex_cache_mul_op[0] ? product_unsigned[31:0] :
                    id_ex_cache_mul_op[1] ? product_signed[63:32] : product_unsigned[63:32];
assign div_start = id_ex_cache_valid && id_ex_cache_div_op[0] && !div_started && !reset;
assign ex_ready_go = !id_ex_cache_div_op[0] || (div_started && div_done);
assign alu_result = id_ex_cache_div_op[0] ? (id_ex_cache_div_op[2] ? div_remainder : div_quotient) :
                    (|id_ex_cache_mul_op) ? mul_result : base_alu_result;

always @(posedge clk) begin
    if (reset)
        div_started <= 1'b0;
    else if (id_ex_cache_allowin)
        div_started <= 1'b0;
    else if (div_start)
        div_started <= 1'b1;
end

div_unit u_div(
    .clk        (clk),
    .reset      (reset),
    .start      (div_start),
    .signed_div (!id_ex_cache_div_op[1]),
    .dividend   (id_ex_cache_alu_src1),
    .divisor    (id_ex_cache_alu_src2),
    .done       (div_done),
    .quotient   (div_quotient),
    .remainder  (div_remainder)
);

alu u_alu(
    .alu_op     (id_ex_cache_alu_op    ),
    .alu_src1   (id_ex_cache_alu_src1  ),
    .alu_src2   (id_ex_cache_alu_src2  ),
    .alu_result (base_alu_result)
    );

wire       ex_mem_cache_allowin;
wire       mem_wb_cache_allowin;
wire       mem_ready_go;
wire       mem_to_wb_valid;
reg [31:0] ex_mem_cache_pc;           // from IF-ID cache, for branch&jump relative target calculation and debug
reg        ex_mem_cache_valid;        // validity state propagated from last cache
reg [31:0] ex_mem_cache_alu_result;   // alu result
reg [31:0] ex_mem_cache_sdata;        // from ID-EX cache, for st.w inst
reg        ex_mem_cache_gr_we;        // regfile we, from ID stage, to WB stage
reg        ex_mem_cache_res_from_mem; // regfile writeback source seletor(ALU or mem), from ID stage, to WB stage
reg [4:0]  ex_mem_cache_dest;         // writeback target reg number in regfile, from ID stage, to WB stage
reg        ex_mem_cache_mem_we;       // mem we, from ID stage, to MEM stage
reg        ex_mem_cache_mem_byte;
reg        ex_mem_cache_mem_half;
reg        ex_mem_cache_mem_unsigned;

always @(posedge clk) begin
    if (reset) begin
        ex_mem_cache_valid <= 1'b0;
    end
    else if (ex_mem_cache_allowin) begin
        ex_mem_cache_pc <= id_ex_cache_pc;
        ex_mem_cache_valid <= id_ex_cache_valid && ex_ready_go;
        ex_mem_cache_alu_result <= alu_result;
        ex_mem_cache_sdata <= id_ex_cache_sdata;
        ex_mem_cache_gr_we <= id_ex_cache_gr_we;
        ex_mem_cache_res_from_mem <= id_ex_cache_res_from_mem;
        ex_mem_cache_dest <= id_ex_cache_dest;
        ex_mem_cache_mem_we <= id_ex_cache_mem_we;
        ex_mem_cache_mem_byte <= id_ex_cache_mem_byte;
        ex_mem_cache_mem_half <= id_ex_cache_mem_half;
        ex_mem_cache_mem_unsigned <= id_ex_cache_mem_unsigned;
    end

end
// ============================================================================
// MEM: use ALU result as data-SRAM address; select load data when needed
// ============================================================================
wire [1:0] mem_offset;
wire [3:0] mem_wmask;
wire [31:0] mem_rdata;

assign mem_offset = ex_mem_cache_alu_result[1:0];
assign mem_wmask  = ex_mem_cache_mem_byte ? (4'b0001 << mem_offset) :
                    ex_mem_cache_mem_half ? (4'b0011 << mem_offset) : 4'b1111;
assign data_sram_en    = (ex_mem_cache_mem_we || ex_mem_cache_res_from_mem) && ex_mem_cache_valid;
assign data_sram_we    = mem_wmask & {4{ex_mem_cache_mem_we && ex_mem_cache_valid}};
assign data_sram_addr  = ex_mem_cache_alu_result;
assign data_sram_wdata = ex_mem_cache_mem_byte ? {4{ex_mem_cache_sdata[7:0]}} :
                         ex_mem_cache_mem_half ? {2{ex_mem_cache_sdata[15:0]}} : ex_mem_cache_sdata;

assign mem_rdata = data_sram_rdata >> {mem_offset, 3'b0};
assign mem_result = ex_mem_cache_mem_byte ? {{24{!ex_mem_cache_mem_unsigned && mem_rdata[7]}}, mem_rdata[7:0]} :
                    ex_mem_cache_mem_half ? {{16{!ex_mem_cache_mem_unsigned && mem_rdata[15]}}, mem_rdata[15:0]} :
                    data_sram_rdata;
assign final_result = ex_mem_cache_res_from_mem ? mem_result : ex_mem_cache_alu_result;

reg        mem_wb_cache_ready; // Current MEM load has waited for SRAM response.
reg        mem_wb_cache_res_from_mem;
reg [31:0] mem_wb_cache_pc;
reg        mem_wb_cache_valid;
reg [31:0] mem_wb_cache_final_result;
reg [4:0]  mem_wb_cache_dest;
reg        mem_wb_cache_gr_we;

// WB completes every cycle. MEM may need one cycle for synchronous SRAM.
assign mem_wb_cache_allowin = 1'b1;
assign mem_ready_go = !ex_mem_cache_res_from_mem || mem_wb_cache_ready;
assign mem_to_wb_valid = ex_mem_cache_valid && mem_ready_go;
assign ex_mem_cache_allowin = !ex_mem_cache_valid
                           || (mem_ready_go && mem_wb_cache_allowin);

// Response state belongs to the instruction held in EX/MEM.
always @(posedge clk) begin
    if (reset)
        mem_wb_cache_ready <= 1'b0;
    else if (ex_mem_cache_allowin)
        mem_wb_cache_ready <= 1'b0;
    else if (ex_mem_cache_valid && ex_mem_cache_res_from_mem)
        mem_wb_cache_ready <= 1'b1;
end

always @(posedge clk) begin
    if (reset) begin
        mem_wb_cache_valid <= 1'b0;
    end
    else if (mem_wb_cache_allowin) begin
        mem_wb_cache_valid <= mem_to_wb_valid;
        if (mem_to_wb_valid) begin
            mem_wb_cache_pc <= ex_mem_cache_pc;
            mem_wb_cache_dest <= ex_mem_cache_dest;
            mem_wb_cache_gr_we <= ex_mem_cache_gr_we;
            mem_wb_cache_final_result <= final_result;
        end
    end

end



// ============================================================================
// WB: write a result to the register file and expose the trace interface
// ============================================================================
assign rf_we    = mem_wb_cache_gr_we && mem_wb_cache_valid;
assign rf_waddr = mem_wb_cache_dest;
assign rf_wdata = mem_wb_cache_final_result;

// debug info generate
assign debug_wb_pc       = mem_wb_cache_pc;
assign debug_wb_rf_we   = {4{rf_we}};
assign debug_wb_rf_wnum  = mem_wb_cache_dest;
assign debug_wb_rf_wdata = mem_wb_cache_final_result;

endmodule
