// 
// c1541_track
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
/////////////////////////////////////////////////////////////////////////

// Extended with support for 157x models by Erik Scheffers

module c157x_track
(
	input         clk,
	input         reset,
	
	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [1:0] freq,
	input         save_track,
	input         change,
	input   [7:0] track,
	output reg    busy
);

assign sd_lba = {20'h00000, 1'b01, freq, lba};

wire [7:0] track_s;
wire       change_s, save_track_s, reset_s;

iecdrv_sync #(8) track_sync  (clk, track,      track_s);
iecdrv_sync #(1) change_sync (clk, change,     change_s);
iecdrv_sync #(1) save_sync   (clk, save_track, save_track_s);
iecdrv_sync #(1) reset_sync  (clk, reset,      reset_s);

reg [7:0] lba;

always @(posedge clk) begin
	reg  [7:0] cur_track = 0;
	reg  [7:0] track_new;
	reg        old_change, update = 0;
	reg        saving = 0, initing = 0;
	reg        old_save_track = 0;
	reg        old_ack;

	track_new <= track_s;

	old_change <= change_s;
	if(~old_change & change_s) update <= 1;
	
	old_ack <= sd_ack;
	if(sd_ack) {sd_rd,sd_wr} <= 0;

	if(reset_s) begin
		cur_track <= '1;
		busy      <= 0;
		sd_rd     <= 0;
		sd_wr     <= 0;
		saving    <= 0;
		update    <= 1;
	end
	else if(busy) begin
		if(old_ack && ~sd_ack) begin
			if((initing || saving) && (cur_track != track_new)) begin
				saving    <= 0;
				initing   <= 0;
				cur_track <= track_new;
				lba       <= track_new;
				sd_rd     <= 1;
			end
			else begin
				busy      <= 0;
			end
		end
	end
	else begin
		old_save_track <= save_track_s;
		if((old_save_track ^ save_track_s) && ~&cur_track[7:1]) begin
			saving    <= 1;
			lba       <= cur_track;
			sd_wr     <= 1;
			busy      <= 1;
		end
		else if(cur_track != track_new || update) begin
			cur_track <= track_new;
			lba       <= track_new;
			sd_rd     <= 1;
			busy      <= 1;
			update    <= 0;
		end
	end
end

endmodule
