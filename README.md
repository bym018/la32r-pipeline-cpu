# LA32R 五级流水线 CPU

从计算机组成原理课程工程中提取的 CPU 设计主干，保留当前 EX7 阶段实现。
采用 Verilog，目标开发环境为 Vivado 2023.2。

## 结构

- `rtl/mycpu_top.v`：IF、ID、EX、MEM、WB 五级流水线，级间缓存、前递、阻塞与分支冲刷。
- `rtl/alu.v`：算术、逻辑、移位与比较。
- `rtl/regfile.v`：32 × 32 位寄存器堆，r0 恒为零。
- `rtl/tools.v`：译码器。
- `rtl/div_unit.v`：除法 IP 接口、有符号转换及完成状态保持。
- `tests/`：除法器独立测试、乘除法及数据相关的 CPU 小程序测试。

乘法使用 `*` 生成 64 位乘积，按指令选择低位或有/无符号高位。
除法使用 Xilinx Divider Generator 5.1，32 位无符号 Radix-2、整数余数、NonBlocking、自动流水线配置。商和余数的符号在包装模块中处理。CPU 在等待除法完成期间保持 EX 指令。

## 接口与范围

顶层为 `mycpu_top`，输入 `clk` 和低有效 `resetn`；指令与数据存储器使用分离的同步 SRAM 接口，读数据在请求后的时钟周期返回。写使能为 4 位字节使能。另提供写回 PC、寄存器号、数据及使能用于跟踪。

实现课程 EX1–EX7 的整数指令子集，包括字节/半字访问、条件分支和乘除法；不宣称实现完整 LoongArch 系统架构。尚未包含后续异常、中断等课程功能。

本仓库不包含 SoC、板级引脚约束、PLL、官方程序镜像和远程测评框架，不能直接生成上板 bitstream。接入板卡需要外围系统及相应时序约束。

## 运行

在 Vivado 配套终端中，从仓库根目录执行：

```sh
vivado -mode batch -source scripts/test.tcl
```

脚本在 `build/` 内创建工程并生成除法 IP，随后运行两个测试。应看到 `PASS: Xilinx Divider Generator` 和 `PASS: dense CPU mul/div/mod`；检查仿真日志中没有 fatal/error。运行需要 Vivado，不能仅用普通 Verilog 编译器解析尚未生成的 IP。

只创建 GUI 工程可执行：

```sh
vivado -mode batch -source scripts/create_project.tcl
```

然后打开 `build/project/cpu.xpr`。默认器件为 `xc7a200tfbg676-1`，可在脚本中修改。

## 来源与验证范围

这是基于课程预制工程继续修改的学习项目，包含课程原有模块及个人修改，不将全部源码宣称为原创。Xilinx IP 通过 Vivado 本地生成，受其原有许可约束；本仓库未额外授予开源许可证。

提取前的课程工程曾通过 EX7 的 46 个功能测试点及乘除法专项测试；这些外部课程测试不随仓库分发。仓库自带测试只覆盖其明确检查的场景，不代表完整 ISA 验证。
