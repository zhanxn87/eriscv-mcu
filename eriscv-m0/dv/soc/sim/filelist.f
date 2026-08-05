// eRISCV-M0 SoC regression source manifest.
// Expand with:
//   python3 ../../../../tools/project/resolve_filelist.py filelist.f --output file.list

// Shared TB helpers live with the core TB.
+incdir+../../core/tb
+incdir+../tb

-f ../../../rtl/soc/filelist.f
../tb/tb_plic_agent.sv
../tb/soc_tb.sv
../tb/tcm_arbitration_tb.sv
