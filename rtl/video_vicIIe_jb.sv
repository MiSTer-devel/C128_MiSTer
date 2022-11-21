//============================================================================
//
//  C128 VIC IIe jailbars
//  Copyright (C) 2022 Erik Scheffers
//
//============================================================================

module video_vicIIe_jb
(
	input        clk,
   input  [1:0] mode,

   input        hsync,
   input  [7:0] Ri,
   input  [7:0] Gi,
   input  [7:0] Bi,

   output [7:0] Ro,
   output [7:0] Go,
   output [7:0] Bo
);

assign Ro = 9'(Ri + adjR) >= 256 ? 8'd255 : Ri + adjR;
assign Go = 9'(Gi + adjG) >= 256 ? 8'd255 : Gi + adjG;
assign Bo = 9'(Bi + adjB) >= 256 ? 8'd255 : Bi + adjB;

wire [2:0] luma = 3'((Ri * 13'd10 + Gi * 13'd19 + Bi * 13'd3) >> 10);

reg  [3:0] adjR, adjG, adjB;

always @(posedge clk) begin
   reg [5:0] counter;
   reg [3:0] adj;

   if (hsync)
      counter <= 6'd24;
   else
      counter <= counter + 1'd1;

   if (mode && luma) begin
      case(counter[4:1])
         15     : adj = mode == 1 ? 4'd3 : mode == 2 ? 4'd3 : 4'd5;
         0      : adj = mode == 1 ? 4'd6 : mode == 2 ? 4'd8 : 4'd11;
         1      : adj = mode == 1 ? 4'd1 : mode == 2 ? 4'd5 : 4'd7;
         2      : adj = mode == 1 ? 4'd0 : mode == 2 ? 4'd1 : 4'd2;
         default: adj = 4'd0;
      endcase

      adj = adj < luma ? 4'd0 : 4'(adj - luma);

      adjR <= adj + 1'(mode[1] && adj<4 &&  counter[5]);
      adjG <= adj + 1'(mode[1] && adj<4 && !counter[5]);
      adjB <= adj;
   end else
   begin
      adjR <= 4'd0;
      adjG <= 4'd0;
      adjB <= 4'd0;
   end
end

endmodule
