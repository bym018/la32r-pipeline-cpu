source [file join [file dirname [info script]] create_project.tcl]
foreach top {tb_div_ip tb_muldiv_cpu} {
    set_property top $top [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation
    run all
    close_sim
}
close_project
