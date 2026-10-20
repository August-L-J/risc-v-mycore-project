// 主译码器：输入一条指令，输出单周期数据通路的全部控制信号（对应 L2 的控制信号表）
module decoder
  import core_pkg::*;
(
  input  logic [31:0] inst,

  // 寄存器堆
  output logic        rf_we,      // 写 rd
  // 立即数与 ALU
  output imm_sel_e    imm_sel,
  output alu_a_sel_e  alu_a_sel,
  output alu_b_sel_e  alu_b_sel,
  output alu_op_e     alu_op,
  // 写回
  output wb_sel_e     wb_sel,
  // 数据存储器
  output logic        mem_we,     // store
  output logic        mem_re,     // load
  output logic [2:0]  mem_size,   // 直接等于 funct3：000 b，001 h，010 w，100 bu，101 hu
  // 下一 PC
  output logic        is_br,
  output logic        is_jal,
  output logic        is_jalr,
  // 仿真控制与异常
  output logic        halt,       // ebreak：通知仿真结束
  output logic        illegal     // 不是 RV32I 合法指令
);




  logic [6:0] opcode ;
  logic [2:0] funct3 ;
  logic [6:0] funct7 ;
  logic [4:0] rd, rs1; // 专门给ebreak和ecall判断使用的，因为这两个指令只有inst[20]位不一样，其他全是0，都一样

  assign opcode = inst[6:0]   ;
  assign funct3 = inst[14:12] ;
  assign funct7 = inst[31:25] ;
  assign rd     = inst[11:7]  ;
  assign rs1    = inst[19:15] ;


  always_comb begin
    rf_we     = 1'b0;

    imm_sel   = IMM_I;
    alu_a_sel = A_RS1;
    alu_b_sel = B_RS2;
    alu_op    = ALU_ADD;

    wb_sel    = WB_ALU;

    mem_we    = 1'b0;
    mem_re    = 1'b0;
    mem_size  = 3'b0;

    is_br = 1'b0;
    is_jal = 1'b0;
    is_jalr = 1'b0;

    halt = 1'b0;  // 只有 ebreak这一个合法指令出现，才会halt=1'b1，其他情况都是halt=0，表示 {正常} 结束。
    illegal = 1'b0; // 当编码不合法的时候，程序跑飞了，要报错打印PC的，在内存default里面出现非法指令要把illegal拉高，并且把一些信号设为默认值。

    unique case(opcode)

      7'b011_0011 : begin   // 寄存器运算，R型opcode
        rf_we = 1'b1;

        // imm_sel 用不到
        alu_a_sel = A_RS1;
        alu_b_sel = B_RS2;
        // alu_op 需要根据funct7和funct3来决定，10种运算

        wb_sel = WB_ALU;

        // mem_we mem_re mem_size 用不到,is_br is_jal is_jalr 用不到, halt , illegal 用不到

        unique case({funct7,funct3})

          10'b000_0000_000 : alu_op = ALU_ADD;
          10'b010_0000_000 : alu_op = ALU_SUB;
          10'b000_0000_001 : alu_op = ALU_SLL;
          10'b000_0000_010 : alu_op = ALU_SLT;

          10'b000_0000_011 : alu_op = ALU_SLTU;
          10'b000_0000_100 : alu_op = ALU_XOR;
          10'b000_0000_101 : alu_op = ALU_SRL;
          10'b010_0000_101 : alu_op = ALU_SRA;

          10'b000_0000_110 : alu_op = ALU_OR;
          10'b000_0000_111 : alu_op = ALU_AND;

          default : begin
              illegal = 1'b1 ;// 非法指令，把下面的信号都拉到默认值

              rf_we     = 1'b0;

              // imm_sel   = IMM_I;
              // alu_a_sel = A_RS1;
              // alu_b_sel = B_RS2;
              // alu_op    = ALU_ADD;

              // wb_sel    = WB_ALU;

              // mem_we    = 1'b0;
              // mem_re    = 1'b0;
              // mem_size  = 3'b0;

              // is_br = 1'b0;
              // is_jal = 1'b0;
              // is_jalr = 1'b0;
          end

        endcase

      end

      7'b001_0011 : begin   // 立即数运算，I型opcode
        rf_we = 1'b1;

        // imm_sel需要根据具体的funct3来决定
        alu_a_sel = A_RS1;  
        alu_b_sel = B_IMM;
        // alu_op 需要根据具体的funct3来决定，毕竟里面还有ori这种逻辑

        wb_sel = WB_ALU; //还是写回register file的rd寄存器的位置

        // mem_we mem_re mem_size 用不到,is_br is_jal is_jalr 用不到, halt , illegal 用不到

        unique case(funct3)

          3'b000 : begin   // addi rd, rs1, imm
            imm_sel = IMM_I;
            alu_op = ALU_ADD;
          end

          3'b010 : begin  // slti rd, rs1, imm
            imm_sel = IMM_I;
            alu_op = ALU_SLT;
          end

          3'b011 : begin   // sltiu rd, rs1, imm
            imm_sel = IMM_I;
            alu_op = ALU_SLTU;
          end

          3'b100 : begin  // xori rd, rs1, imm
            imm_sel = IMM_I;
            alu_op = ALU_XOR;
          end

          3'b110 : begin  // ori rd, rs1, imm
            imm_sel = IMM_I;
            alu_op = ALU_OR;
          end

          3'b111 : begin // andi rd, rs1, imm
            imm_sel = IMM_I;
            alu_op = ALU_AND;
          end 

          3'b001 : begin // slli rd, rs1, shamt

            if(funct7 == 7'b000_0000) begin
              imm_sel = IMM_I;
              alu_op = ALU_SLL;
            end
            else begin
              illegal = 1'b1;     //非法指令，要把指令都拉到默认值
              
              rf_we = 1'b0;
            end


          end

          3'b101 : begin  // srli rd rs1, shamt 或者 srli rd rs1, shamt 都是一样的funct3=101，但是要根据funct7来区分
            imm_sel = IMM_I;
            unique case(funct7)
              7'b000_0000 : alu_op = ALU_SRL;  // srli rd rs1, shamt
              7'b010_0000 : alu_op = ALU_SRA;  // srai rd rs1, shamt
              default :begin
                illegal = 1'b1;         //非法指令，把下面的信号都拉到默认值

                rf_we = 1'b0;
              end
            endcase
          end

        endcase

      end

      7'b000_0011 : begin   // Load指令，I型opcode


        // 因为funct3只有5种情况，剩下的都是非法指令，要特别写出来。
        if(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b100 || funct3 == 3'b101) begin // 有效的load指令

          rf_we = 1'b1;

          imm_sel = IMM_I;
          alu_a_sel = A_RS1;
          alu_b_sel = B_IMM;
          // alu_op = ALU_ADD; // load指令都是用  Reg[rs1] + imm 作为MEM的raddr使用

          wb_sel = WB_MEM;  // WB阶段写回Register File的rd寄存器的输入值为 MEM[raddr]

          // mem_we = 1'b0;
          mem_re = 1'b1; 
          mem_size = funct3; //直接等于funct3：000 b，001 h，010 w，100 bu，101 hu

          // is_br is_jal is_jalr 用不到, halt , illegal 用不到，用不到跳转指令


        end
        else begin // 非法指令，要拉回到默认指令

        illegal = 1'b1;         //非法指令，把下面的信号都拉到默认值        

        end

      end

      7'b010_0011 : begin  // store指令，S型opcode
        
        if(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010) begin  // 有效的store指令，剩下非法丢到illegal里面去

          // rf_we = 1'b0;  // store指令不需要写回到register file里面

          imm_sel = IMM_S;  // S型opcode
          alu_a_sel = A_RS1;
          alu_b_sel = B_IMM;
          // alu_op = ALU_ADD;  // 存指令，store指令使用的都是 Reg[rs2] -> MEM[Reg[rs1] + imm]

          // wb_sel 用不到，不需要写回到 register file里面

          mem_we = 1'b1;
          // mem_re = 1'b0;
          mem_size = funct3; //直接等于funct3：000 b，001 sh, 010 sw

          // is_br is_jal is_jalr 用不到, halt , illegal 用不到，用不到跳转指令
        end
        else begin // 非法指令，要拉回到默认指令

          illegal = 1'b1;         //非法指令，把下面的信号都拉到默认值        

        end

      end

      7'b110_0011 : begin // B型指令，各种branch ， 用rs1和rs2做比较，判断PC跳不跳，跳的位置由ALU做的运算，PC+IMM决定
      
        if(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b100 || funct3 == 3'b101 || funct3 == 3'b110 || funct3 == 3'b111) begin // 有效的branch指令，剩下非法丢到illegal里面去



          // rf_we = 1'b0; // branch指令不需要写回到register file里面

          imm_sel = IMM_B;  // B型opcode
          alu_a_sel = A_PC;  // branch指令的ALU A端使用PC
          alu_b_sel = B_IMM;  
          // alu_op = ALU_ADD; 

          // wb_sel 用不到，不需要写回到 register file里面

          // mem_we = 1'b0;
          // mem_re = 1'b0;
          // mem_size = 3'b0; // branch指令不需要访问MEM

          is_br = 1'b1; // branch指令需要跳转

          // is_jal is_jalr 用不到, halt , illegal 用不到

          // unique case(funct3)
          // 这里根据不同的funct3，应该是有不同情况的branch指令的，现在还没有comp比较器，这个位置怎么写？怎么直接比较rs1和rs2？
          // 到后续L5会着重处理，这里目前译码器只做译码判断。
          // endcase

        end
        else begin // 非法指令，要拉回到默认指令

          illegal = 1'b1;         //非法指令，把下面的信号都拉到默认值        

        end

      end

      7'b110_1111 : begin // jal指令，J型opcode ，跳转并链接， 
        //jal rd, imm ，两个加法操作，1.要跳转到的下一个地址用PC+imm来算，2.把正常按顺序往下走的PC+4地址写到Reg[rd]里面，防止找不到回家的路~
        rf_we = 1'b1; // jal 指令需要写回到register file里面，写回的值是PC+4

        imm_sel = IMM_J; // J型opcode
        alu_a_sel = A_PC; // jal指令的ALU A端使用PC
        alu_b_sel = B_IMM; // jal指令的ALU B端使用IMM
        // alu_op = ALU_ADD; // jal指令的ALU做加法运算，计算跳转的地址PC+IMM

        wb_sel = WB_PC4; // jal指令的WB阶段写回Register File的rd寄存器的输入值为 PC+4

        // mem_we = 1'b0;
        // mem_re = 1'b0;
        // mem_size = 3'b0; // jal指令不需要访问MEM

        // is_br和is_jalr 都不用管

        is_jal = 1'b1; // jal指令需要跳转

      end

      7'b110_0111 : begin // jalr指令，I型opcode ，跳转并链接，jalr rd, imm(rs1)，和jal的区别在于，
       // jalr的跳转地址是Reg[rs1]+imm,而jal的跳转地址是 PC+imm来计算。 二者都是跳转，都是两次加法操作，都是rd = PC+4先存起来而已。

        if(funct3 == 3'b000) begin // jalr指令的funct3是000，其他都是非法指令

          rf_we = 1'b1 ; // jalr指令需要在WB阶段写回到register file里面

          imm_sel = IMM_I; // jalr指令是I型opcode
          alu_a_sel = A_RS1; // jalr指令的ALU A端使用Reg[rs1]
          alu_b_sel = B_IMM; // jalr指令的ALU B端
          // alu_op = ALU_ADD; // jalr指令的ALU做加法运算，计算跳转的地址Reg[rs1]+IMM

          wb_sel = WB_PC4;  // jalr指令的WB阶段写回Register File的rd寄存器的输入值为 PC+4

          // mem_we = 1'b0;
          // mem_re = 1'b0;
          // mem_size = 3'b0; // jalr指令不需要访问MEM

          // is_br和is_jal 都不用管

          is_jalr = 1'b1; // jalr指令需要跳转

        end
        else begin
          illegal = 1'b1; // jalr指令的funct3不是000就是非法指令
        end

      end

      7'b011_0111 : begin // lui指令，U型指令， lui rd,imm20  ，功能： rd = imm20 << 12， ALU里面是0+imm，写回到Reg[rd] 里面

        rf_we = 1'b1; // lui 指令需要在WB阶段写回到register file里面

        imm_sel = IMM_U; // lui指令是U型opcode
        alu_a_sel = A_ZERO; // lui指令的ALU A端使用0
        alu_b_sel = B_IMM; // lui指令的ALU B端使用IMM
        // alu_op = ALU_ADD; // lui指令的ALU做加法

        // wb_sel = WB_ALU;  // lui指令的WB阶段写回Register File的rd寄存器的输入值为 ALU的输出值

        // mem_we = 1'b0;
        // mem_re = 1'b0;
        // mem_size = 3'b0; // lui指令不需要访问MEM

        // is_br和is_jal is_jalr 都不用管
        end

      7'b001_0111 : begin  // auipc指令，U型指令，auipc rd,imm20，功能： Reg[rd] = PC + (imm20 << 12)，ALU里面是PC+imm

        rf_we = 1'b1; // auipc 指令需要在WB阶段写回到register file里面

        imm_sel = IMM_U; // auipc指令是U型opcode
        alu_a_sel = A_PC; // auipc指令的ALU A端使用PC
        alu_b_sel = B_IMM; // auipc指令的ALU B端使用IMM
        // alu_op = ALU_ADD; // auipc指令的ALU做加法

        // wb_sel = WB_ALU;  // auipc指令的WB阶段写回Register File的rd寄存器的输入值为 ALU的输出值

        // mem_we = 1'b0;
        // mem_re = 1'b0;
        // mem_size = 3'b0; // auipc指令不需要访问MEM

        // is_br和is_jal is_jalr 都不用管
      
      
      end

      7'b000_1111 : begin  // fence指令
        //功能： fence指令是内存屏障指令，主要用于多核处理器中，确保在 fence 指令之前的所有内存操作都已经完成，并且在 fence 指令之后的所有内存操作都不会被重排到 fence 指令之前。它不会对寄存器堆、ALU、写回、数据存储器等产生影响。
      
        if(funct3 == 3'b000) begin // fence指令的funct3是000，其他都是非法指令
          // fence指令不需要写回到register file里面
          // imm_sel, alu_a_sel, alu_b_sel, alu_op, wb_sel, mem_we, mem_re, mem_size, is_br, is_jal, is_jalr 都不用管
        end
        else begin
          illegal = 1'b1; // fence指令的funct3不是000就是非法指令
        end
      // 全部保持默认值
      
      end

      7'b111_0011 : begin   // ebreak和ecall指令，功能：触发调试异常，通知仿真结束

        if(funct3 == 3'b000 && rd == 5'b00000 && rs1 == 5'b00000 && inst[31:21] == 11'b0)begin

          if(inst[20] == 1'b1) begin // ebreak指令，inst[20]=1'b1
            halt = 1'b1; // ebreak 指令通知仿真结束, ebreak ,inst[20]=1'b1, halt = 1'b1
          end
          else begin // ecall指令，inst[20]=1'b0
            halt = 1'b0;  // ecall 指令不通知仿真结束 ,ecall ,inst[20]=1'b0, halt = 1'b0
          end

        end

        else begin
          illegal = 1'b1; // 只拿inst[20]来区分ebreak和ecall，其他都是非法指令
        end

      end


      default : begin
        illegal = 1'b1 ;//  没被 unicase匹配的指令就是剩下的非法指令，归类到非法指令，信号都拉到默认值 

      end

    endcase
  end



endmodule
