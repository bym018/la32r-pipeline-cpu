set root [file normalize [file join [file dirname [info script]] ..]]
file mkdir [file join $root build]
cd [file join $root build]
create_project -force cpu [file join $root build project] -part xc7a200tfbg676-1
add_files [glob [file join $root rtl *.v]]
create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 -module_name div_unsigned
set_property -dict [list CONFIG.algorithm_type Radix2 \
    CONFIG.dividend_and_quotient_width 32 CONFIG.divisor_width 32 \
    CONFIG.operand_sign Unsigned CONFIG.remainder_type Remainder \
    CONFIG.fractional_width 32 CONFIG.clocks_per_division 1 \
    CONFIG.FlowControl NonBlocking CONFIG.latency_configuration Automatic \
    CONFIG.ARESETN true] [get_ips div_unsigned]
generate_target all [get_ips div_unsigned]
set_property top mycpu_top [get_filesets sources_1]
add_files -fileset sim_1 [glob [file join $root tests *.v]]
set_property top tb_muldiv_cpu [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
