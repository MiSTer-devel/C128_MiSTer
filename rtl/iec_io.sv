module iec_io
(
   input  ext_en,

   input  cpu_o,
   input  drive_o,
   input  ext_o,

   output cpu_i,
   output drive_i,
   output ext_i
);

assign cpu_i = drive_o && (ext_o || !ext_en);
assign drive_i = cpu_o && (ext_o || !ext_en);
assign ext_i = (cpu_o && drive_o) || !ext_en;

endmodule
