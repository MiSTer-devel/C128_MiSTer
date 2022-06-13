//-------------------------------------------------------------------------------
//
// Commodore 1541 gcr floppy (read/write) by Dar (darfpga@aol.fr) 23-May-2017
// http://darfpga.blogspot.fr
//
// produces GCR data, byte(ready) and sync signal to feed c1541_logic from current
// track buffer ram which contains D64 data
//
// gets GCR data from c1541_logic, while producing byte(ready) signal. Data feed
// track buffer ram after conversion
//
// Reworked and adapted to MiSTer by Alexey Melnikov
//
//-------------------------------------------------------------------------------

module c1541_gcr
(
	input             clk,
	input             ce,

	output reg  [7:0] dout,    // data from ram to 1541 logic
	input       [7:0] din,     // data from 1541 logic to ram
	input             mode,    // read/write
	input             mtr,     // stepper motor on/off
	input       [1:0] freq,    // motor (gcr_bit) frequency
	output            sync_n,  // reading SYNC bytes
	output reg        byte_n,  // byte ready

	input       [5:0] track,
	input             busy,
	output reg        we,
	
	input             sd_clk,
	input      [31:0] sd_lba,
	input      [12:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	output      [7:0] sd_buff_din,
	input             sd_buff_wr
);

assign sync_n = ~mtr | busy | sync_in_n;

wire [4:0] sector_max=	(track < 18) ? 5'd20 :
								(track < 25) ? 5'd18 :
								(track < 31) ? 5'd17 :
													5'd16;

wire [7:0] data_header= (byte_cnt == 0) ? 8'h08 :
								(byte_cnt == 1) ? hdr_cks :
								(byte_cnt == 2) ? sector :
								(byte_cnt == 3) ? track :
								(byte_cnt == 4) ? id2 :
								(byte_cnt == 5) ? id1 :
														8'h0F;

wire [7:0] data_body=	(byte_cnt == 0)   ? 8'h07 :
								(byte_cnt == 257) ? data_cks :
								(byte_cnt == 258) ? 8'h00 :
								(byte_cnt == 259) ? 8'h00 :
								(byte_cnt >= 260) ? 8'h0F :
														  buff_do;

wire [7:0] data = state ? data_body : data_header;
wire [4:0] gcr_nibble = gcr_lut[nibble ? data[3:0] : data[7:4]];

wire [4:0] gcr_lut[16] = '{
	5'b01010, 5'b11010, 5'b01001, 5'b11001,
	5'b01110, 5'b11110, 5'b01101, 5'b11101,
	5'b10010, 5'b10011, 5'b01011, 5'b11011,
	5'b10110, 5'b10111, 5'b01111, 5'b10101
};

wire [3:0] nibble_out;
always_comb begin
	case(gcr_nibble_out)
		5'b01010: nibble_out = 'h0;
		5'b01011: nibble_out = 'h1;
		5'b10010: nibble_out = 'h2;
		5'b10011: nibble_out = 'h3;
		5'b01110: nibble_out = 'h4;
		5'b01111: nibble_out = 'h5;
		5'b10110: nibble_out = 'h6;
		5'b10111: nibble_out = 'h7;
		5'b01001: nibble_out = 'h8;
		5'b11001: nibble_out = 'h9;
		5'b11010: nibble_out = 'hA;
		5'b11011: nibble_out = 'hB;
		5'b01101: nibble_out = 'hC;
		5'b11101: nibble_out = 'hD;
		5'b11110: nibble_out = 'hE;
		default:  nibble_out = 'hF;
	endcase
end

reg       bit_clk_en;
reg [5:0] old_track;
always @(posedge clk) begin
	reg [5:0] bit_clk_cnt;
	reg       mode_r1;

	bit_clk_en <= 0;

	if(ce) begin
		old_track <= track;
		mode_r1 <= mode;
		byte_n <= 1;

		if ((old_track != track) | (mode_r1 ^ mode) | busy | ~mtr) begin
			bit_clk_cnt <= {freq,2'b00};
		end
		else begin
			bit_clk_cnt <= bit_clk_cnt + 1'b1;
			if(byte_in && bit_clk_cnt[5:4] == 1) byte_n <= 0;

			if (&bit_clk_cnt) begin
				bit_clk_en <= 1;
				bit_clk_cnt <= {freq,2'b00};
			end
		end
	end
end

reg [7:0] id1=0, id2=0;
always @(posedge sd_clk) begin
	if(sd_lba == 357 && sd_buff_wr) begin
		if(sd_buff_addr == 'hA2) id1 <= sd_buff_dout;
		if(sd_buff_addr == 'hA3) id2 <= sd_buff_dout;
	end
end

iecdrv_mem #(8,13) buffer
(
	.clock_a(sd_clk),
	.address_a(sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_buff_wr),
	.q_a(sd_buff_din),

	.clock_b(clk),
	.address_b(buff_addr),
	.data_b(buff_di),
	.wren_b(we),
	.q_b(buff_do)
);

reg [12:0] buff_addr;
wire [7:0] buff_do;
reg  [7:0] buff_di;

reg  [4:0] sector;
reg        sync_in_n;
reg        byte_in;
reg  [8:0] byte_cnt;
reg        nibble;
reg        state;
reg  [7:0] data_cks; 
reg  [7:0] gcr_byte_out;
reg  [4:0] gcr_nibble_out;
reg  [7:0] hdr_cks;

always @(posedge clk) begin
	reg       mode_r2;
	reg       autorise_write;
	reg       autorise_count;
	reg [5:0] sync_cnt;
	reg [7:0] gcr_byte;
	reg [2:0] bit_cnt;
	reg [3:0] gcr_bit_cnt;

	hdr_cks <= track ^ sector ^ id1 ^ id2;
	we <= 0;

	if (sector > sector_max) sector <= 0;
	else if (bit_clk_en) begin
		mode_r2 <= mode;
		if (mode) autorise_write <= 0;

		if (mode ^ mode_r2) begin
			if (mode) begin		// leaving write mode
				sync_in_n <= 0;
				sync_cnt <= 0;
				state <= 0;
			end else begin
				// entering write mode
				byte_cnt <= 0;
				nibble <= 0;
				gcr_bit_cnt <= 0;
				bit_cnt <= 0;
				gcr_byte <= 0;
				data_cks <= 0;
			end
		end

		byte_in <= 0;

		if (~sync_in_n & mode) begin
			byte_cnt <= 0;
			nibble <= 0;
			gcr_bit_cnt <= 0;
			bit_cnt <= 0;
			dout <= 8'hFF;
			gcr_byte <= 0;
			data_cks <= 0;
			sync_cnt <= sync_cnt + 1'd1;
			if (sync_cnt == 39) begin
				sync_cnt <= 0;
				sync_in_n <= 1;
			end
		end
		else begin
			gcr_bit_cnt <= gcr_bit_cnt + 1'b1;
			if (gcr_bit_cnt == 4) begin
				gcr_bit_cnt <= 0;
				if (nibble) begin
					nibble <= 0;
					buff_addr <= {sector,byte_cnt[7:0]};
					if (!byte_cnt) data_cks <= 0;
					else data_cks <= data_cks ^ data;

					if (mode | autorise_count) byte_cnt <= byte_cnt + 1'b1;
				end else begin
					nibble <= 1;
					if (~mode && buff_di == 'h07) begin
						autorise_write <= 1;
						autorise_count <= 1;
					end
					if (byte_cnt[8]) begin
						autorise_write <= 0;
						autorise_count <= 0;
					end
				end
			end

			bit_cnt <= bit_cnt + 1'b1;
			if (bit_cnt == 7) begin
				byte_in <= 1;
				gcr_byte_out <= din;
			end

			if (~state) begin
				if (byte_cnt == 16) begin
					sync_in_n <= 0;
					state <= 1;
				end
			end
			else if (byte_cnt == 273) begin
				sync_in_n <= 0;
				state <= 0;
				if (sector == sector_max) sector <= 0;
				else sector <= sector + 1'b1;
			end

			// demux byte from floppy (ram)
			gcr_byte <= {gcr_byte[6:0], gcr_nibble[gcr_bit_cnt]};

			if (bit_cnt == 7) dout <= {gcr_byte[6:0], gcr_nibble[gcr_bit_cnt]};

			// serialise/convert byte to floppy (ram)
			gcr_nibble_out <= {gcr_nibble_out[3:0], gcr_byte_out[~bit_cnt]};

			if (!gcr_bit_cnt) begin
				if (nibble) buff_di[7:4] <= nibble_out;
				else buff_di[3:0] <= nibble_out;
			end

			if (gcr_bit_cnt == 1 && ~nibble) begin
				if (autorise_write) we <= 1;
			end
		end
	end
end

endmodule
