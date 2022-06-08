// C128 OSD info
//
// for the C128 MiSTer FPGA core, by Erik Scheffers

module osdinfo #(
   parameter    OSD_DELAY = 16_000_000,
   parameter    OSD_DELAY_BITS = $clog2(OSD_DELAY)
) (
   input        clk,
   input        reset,

   input        sftlk_sense,
   input        cpslk_sense,
   input        d4080_sense,
   input        noscr_sense,

   input        cpslk_mode,

   output       info_req,
   output [7:0] info
);

always @(posedge clk) begin
   reg sftlk_sense0;
   reg cpslk_sense0;
   reg d4080_sense0;
   reg noscr_sense0;
   reg [OSD_DELAY_BITS-1:0] delay;

   if (reset) begin
      info <= 0;
      info_req <= 0;
      delay <= 0;

      sftlk_sense0 <= 0;
      cpslk_sense0 <= 0;
      d4080_sense0 <= 0;
      noscr_sense0 <= 0;
   end
   else begin
      sftlk_sense0 <= sftlk_sense;
      if (sftlk_sense != sftlk_sense0) begin
         info <= sftlk_sense ? 8'd2 : 8'd1;
         info_req <= 1;
         delay <= OSD_DELAY_BITS'(OSD_DELAY);
      end

      cpslk_sense0 <= cpslk_sense;
      if (cpslk_sense != cpslk_sense0) begin
         info <= cpslk_mode ? (cpslk_sense ? 8'd6 : 8'd5) : (cpslk_sense ? 8'd4 : 8'd3);
         info_req <= 1;
         delay <= OSD_DELAY_BITS'(OSD_DELAY);
      end

      d4080_sense0 <= d4080_sense;
      if (d4080_sense != d4080_sense0) begin
         info <= d4080_sense ? 8'd8 : 8'd7;
         info_req <= 1;
         delay <= OSD_DELAY_BITS'(OSD_DELAY);
      end

      noscr_sense0 <= noscr_sense;
      if (noscr_sense != noscr_sense0) begin
         info <= noscr_sense ? 8'd10 : 8'd9;
         info_req <= 1;
         delay <= OSD_DELAY_BITS'(OSD_DELAY);
      end

      if (~|delay) begin
         delay <= delay - OSD_DELAY_BITS'(1);
      end
      else if (info_req) begin
         info_req <= 0;
      end
   end
end

endmodule
