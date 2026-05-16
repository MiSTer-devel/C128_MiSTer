// ============================================================================
// Drive OSD Overlay (C128 Port)
//
// Functionality:
// - Displays drive track/activity status (Activity Only, Mounted, or Debug).
// - Generates a 2-bit color index to be blended into the final video output.
// ============================================================================
module drv_overlay (
	input clk,
	input ce,
	input hblank,
	input vblank,
	input ntsc,

	// Drive status
	input [1:0] drive_osd_mode, // 0=Activity Only, 1=If Mounted, 2=Always (Debug), 3=Off
	input [1:0] drive_led,
	input [1:0] drive_mounted,
	input [7:0] drive_track_0,
	input [7:0] drive_track_1,
	input [1:0] drive_we,

	// pixel output for video mixer
	// 0=Transparent, 1=Green, 2=Yellow, 3=Red
	output [1:0] pixel_color
);

// Coordinate Logic
reg [10:0] x_pos = 0;
reg [10:0] y_pos = 0;
reg old_hblank = 0;

always @(posedge clk) begin
	if (hblank) x_pos <= 0;
	else if (ce) x_pos <= x_pos + 1'd1;

	if (ce) old_hblank <= hblank;

	if (vblank) y_pos <= 0;
	else if (ce) begin
		if (old_hblank && ~hblank) y_pos <= y_pos + 1'd1;
	end
end

// Overlay Areas
wire [10:0] base_y  = ntsc ? 11'd212 : 11'd222;
wire [10:0] base_x  = ntsc ? 11'd650 : 11'd632;
wire        drv_area = (x_pos >= base_x) && (x_pos < base_x + 84) &&
                       (y_pos >= base_y) && (y_pos < base_y + 12);

// Coordinate generators
reg [2:0] drv_col_r = 0;
reg       drv_row_r = 0;
reg [2:0] drv_px_r  = 0;
reg [2:0] drv_py_r  = 0;
reg       vdc_px_phase = 0;

always @(posedge clk) begin
	if (hblank) begin
		drv_col_r <= 0;
		drv_px_r  <= 0;
		vdc_px_phase <= 0;
	end else if (ce) begin
		if (x_pos == base_x - 11'd1) begin
			drv_col_r <= 0;
			drv_px_r  <= 0;
			vdc_px_phase <= 0;
		end else if (drv_area) begin
			if (!vdc_px_phase) begin
				vdc_px_phase <= 1;
			end else begin
				vdc_px_phase <= 0;
				if (drv_px_r == 5) begin
					drv_px_r  <= 0;
					drv_col_r <= drv_col_r + 1'd1;
				end else begin
					drv_px_r  <= drv_px_r + 1'd1;
				end
			end
		end
	end
end

always @(posedge clk) begin
	if (vblank) begin
		drv_row_r <= 0;
		drv_py_r  <= 0;
	end else if (ce) begin
		if (old_hblank && ~hblank) begin
			if (y_pos == base_y-1) begin
				drv_row_r <= 0;
				drv_py_r  <= 0;
			end else if (drv_area || (y_pos >= base_y && y_pos < base_y + 12)) begin
				if (drv_py_r == 5) begin
					drv_py_r  <= 0;
					drv_row_r <= drv_row_r + 1'd1;
				end else begin
					drv_py_r  <= drv_py_r + 1'd1;
				end
			end else begin
				drv_row_r <= 0;
				drv_py_r  <= 0;
			end
		end
	end
end

wire [2:0] drv_col = drv_col_r;
wire       drv_row = drv_row_r;
wire [2:0] drv_px  = drv_px_r;
wire [2:0] drv_py  = drv_py_r;

// ---------------------------------------------------------------------------
// DATA RESOLUTION (COMBINATORIAL)
// ---------------------------------------------------------------------------

reg [4:0]  drv_char;
wire [7:0] drv_track  = drv_row ? drive_track_1 : drive_track_0;
wire [7:0] full_track = (drv_track >> 1) + 8'd1;
wire       half_track = drv_track[0];

wire [3:0] track_tens = (full_track >= 80) ? 4'd8 : (full_track >= 70) ? 4'd7 : (full_track >= 60) ? 4'd6 :
                        (full_track >= 50) ? 4'd5 : (full_track >= 40) ? 4'd4 : (full_track >= 30) ? 4'd3 :
                        (full_track >= 20) ? 4'd2 : (full_track >= 10) ? 4'd1 : 4'd0;
wire [3:0] track_ones = 4'(full_track - ((track_tens << 3) + (track_tens << 1)));

always @(*) begin
	case (drv_col)
		0: drv_char = 5'h10; // '#'
		1: drv_char = drv_row ? 5'h09 : 5'h08; // '9' or '8'
		2: drv_char = 5'h11; // ' '
		3: drv_char = (track_tens == 0) ? 5'h11 : {1'b0, track_tens};
		4: drv_char = {1'b0, track_ones};
		5: drv_char = half_track ? 5'h12 : 5'h11; // '.' or ' '
		6: drv_char = half_track ? 5'h05 : 5'h11; // '5' or ' '
		default: drv_char = 5'h11;
	endcase
end

wire drv_led_act     = drive_led[drv_row];
wire drv_we_act      = drive_we[drv_row];
wire valid_osd_pixel = drv_area && (drv_px < 5) && (drv_py < 5) &&
					   ((drive_osd_mode == 0 && drv_led_act) ||
					   (drive_osd_mode == 1 && drive_mounted[drv_row]) ||
					   drive_osd_mode == 2);

// ---------------------------------------------------------------------------
// PIPELINE STAGE 1: Latch coordinates, character inputs, and state flags
// ---------------------------------------------------------------------------
reg [4:0] char_to_draw_s1;
reg [2:0] px_s1;
reg [2:0] py_s1;

reg valid_osd_s1;
reg drv_led_act_s1, drv_we_act_s1;

always @(posedge clk) begin
	if (ce) begin
		char_to_draw_s1 <= valid_osd_pixel ? drv_char : 5'd0;
		px_s1           <= valid_osd_pixel ? drv_px   : 3'd0;
		py_s1           <= valid_osd_pixel ? drv_py   : 3'd0;

		valid_osd_s1    <= valid_osd_pixel;
		drv_led_act_s1  <= drv_led_act;
		drv_we_act_s1   <= drv_we_act;
	end
end

// ---------------------------------------------------------------------------
// PIPELINE STAGE 2: Font ROM Lookup
// ---------------------------------------------------------------------------
reg [4:0] font_row_s2;
reg [2:0] px_s2;

reg valid_osd_s2;
reg drv_led_act_s2, drv_we_act_s2;

always @(posedge clk) begin
	if (ce) begin
		// Font Lookup
		case (char_to_draw_s1)
			5'h00: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b10001; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h01: case(py_s1) 0: font_row_s2<=5'b00100; 1: font_row_s2<=5'b01100; 2: font_row_s2<=5'b00100; 3: font_row_s2<=5'b00100; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h02: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b00110; 3: font_row_s2<=5'b01000; 4: font_row_s2<=5'b11111; default: font_row_s2<=0; endcase
			5'h03: case(py_s1) 0: font_row_s2<=5'b11110; 1: font_row_s2<=5'b00001; 2: font_row_s2<=5'b01110; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h04: case(py_s1) 0: font_row_s2<=5'b10001; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b11111; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b00001; default: font_row_s2<=0; endcase
			5'h05: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h06: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h07: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b00001; 2: font_row_s2<=5'b00010; 3: font_row_s2<=5'b00100; 4: font_row_s2<=5'b00100; default: font_row_s2<=0; endcase
			5'h08: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b01110; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h09: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b01111; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h0A: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b11111; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b10001; default: font_row_s2<=0; endcase
			5'h0B: case(py_s1) 0: font_row_s2<=5'b11110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h0C: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b10000; 3: font_row_s2<=5'b10000; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h0D: case(py_s1) 0: font_row_s2<=5'b11110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b10001; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h0E: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10000; 4: font_row_s2<=5'b11111; default: font_row_s2<=0; endcase
			5'h0F: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10000; 4: font_row_s2<=5'b10000; default: font_row_s2<=0; endcase
			5'h10: case(py_s1) 0: font_row_s2<=5'b01010; 1: font_row_s2<=5'b11111; 2: font_row_s2<=5'b01010; 3: font_row_s2<=5'b11111; 4: font_row_s2<=5'b01010; default: font_row_s2<=0; endcase // '#'
			5'h11: case(py_s1) 0: font_row_s2<=5'b00000; 1: font_row_s2<=5'b00000; 2: font_row_s2<=5'b00000; 3: font_row_s2<=5'b00000; 4: font_row_s2<=5'b00000; default: font_row_s2<=0; endcase // ' '
			5'h12: case(py_s1) 0: font_row_s2<=5'b00000; 1: font_row_s2<=5'b00000; 2: font_row_s2<=5'b00000; 3: font_row_s2<=5'b01100; 4: font_row_s2<=5'b01100; default: font_row_s2<=0; endcase // '.'
			default: font_row_s2<=0;
		endcase

		// Forward state
		px_s2          <= px_s1;
		valid_osd_s2   <= valid_osd_s1;
		drv_led_act_s2 <= drv_led_act_s1;
		drv_we_act_s2  <= drv_we_act_s1;
	end
end

// ---------------------------------------------------------------------------
// PIPELINE STAGE 3: Final Pixel Shift and Color Mixing
// ---------------------------------------------------------------------------
wire [2:0] px_rev = (px_s2 < 5) ? 3'd4 - px_s2 : 3'd0;
wire pixel_base   = (px_s2 < 5) ? font_row_s2[px_rev] : 1'b0;

reg [1:0] pixel_color_out;

always @(posedge clk) begin
	if (ce) begin
		if (valid_osd_s2 && pixel_base && drv_led_act_s2 && drv_we_act_s2) begin
			pixel_color_out <= 2'd3; // Red (Drive Write)
		end else if (valid_osd_s2 && pixel_base && drv_led_act_s2 && ~drv_we_act_s2) begin
			pixel_color_out <= 2'd2; // Yellow (Drive Read)
		end else if (valid_osd_s2 && pixel_base && ~drv_led_act_s2) begin
			pixel_color_out <= 2'd1; // Green (Drive Idle)
		end else begin
			pixel_color_out <= 2'd0; // Transparent
		end
	end
end

assign pixel_color = pixel_color_out;

endmodule