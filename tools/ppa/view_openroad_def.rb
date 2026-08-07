# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Open an OpenROAD DEF using its adjacent Sky130 LEFs as drawable macro geometry.

input_def = File.expand_path($input_def)
directory = File.dirname(input_def)
tech_lef = File.join(directory, "sky130_fd_sc_hd__nom.tlef")
cell_lef = File.join(directory, "sky130_fd_sc_hd.lef")

[input_def, tech_lef, cell_lef].each do |path|
  raise "Missing OpenROAD viewer input: #{path}" unless File.file?(path)
end

# run_openroad.py links every hard-macro LEF beside the DEF.  Pick them up
# automatically so this viewer works for both the standard-cell and SRAM flows.
lef_files = [tech_lef] + Dir.glob(File.join(directory, "*.lef")).sort

options = RBA::LoadLayoutOptions::new
lefdef = RBA::LEFDEFReaderConfiguration::new
lefdef.lef_files = lef_files
lefdef.read_lef_with_def = false
# Sky130's LEF macros declare FOREIGN, but this estimation flow does not
# generate per-cell GDS layouts. Draw the LEF macro geometry instead.
lefdef.macro_resolution_mode = 1
options.lefdef_config = lefdef

main_window = RBA::Application.instance.main_window
main_window.load_layout(input_def, options, 1)
view = main_window.current_view
view.max_hier
view.zoom_fit
