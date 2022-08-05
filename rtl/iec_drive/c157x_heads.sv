//-------------------------------------------------------------------------------
//
// C1541/157x sd-card to read/write head signals conversion
//
// Split from C1541/157x direct gcr module (C) 2021 Alexey Melnikov
//
// Changes for 157x by Erik Scheffers
//
//-------------------------------------------------------------------------------

module c157x_heads #(parameter DRIVE, parameter TRACK_BUF_LEN)
(
	input        clk,
	input        ce,
	input        reset,
	input        enable,

	input  [1:0] freq,  // GCR bitrate
   input        mode,  // GCR mode (0=write, 1=read)
   input        wgate, // MFM wgate (0=read, 1=write)
	output       write, // Write mode

   output       hclk,
	output       hf,    // signal from head
	input        ht,    // signal to head

	output       index,
	
	input			 sd_busy,
	input        sd_clk,
	input [15:0] sd_buff_addr,
	input  [7:0] sd_buff_dout,
	output [7:0] sd_buff_din,
	input        sd_buff_wr,
	output       sd_update
);

assign     write     = ~mode ^ wgate;
assign     sd_update = buff_we;

wire       mfm       = track_len[13]; // assume tracks >= 8192 bytes are MFM
wire [5:0] bitrate   = mfm ? 6'b100000 : {2'b00,freq,2'b00};

wire [7:0] sd_buff_do;
assign sd_buff_din = sd_buff_addr == 0 ? track_len[7:0]
                   : sd_buff_addr == 1 ? {2'b00, track_len[13:8]}
						 : sd_buff_addr > track_len+2 ? 8'hFF : sd_buff_do;

reg [13:0] track_len;
always @(posedge sd_clk) begin
	reg [1:0] freq_l;

	if(sd_buff_wr && !sd_buff_addr[13:2])
		case(sd_buff_addr[1:0])
			0: track_len[7:0]  <= sd_buff_dout;
			1: track_len[13:8] <= sd_buff_dout[5:0];
			2: if (track_len+2 > TRACK_BUF_LEN) track_len <= 14'(TRACK_BUF_LEN-2);
		endcase

	freq_l <= freq;
	if (!sd_busy && write && (track_len == 0 || wgate != mfm || freq_l != freq))
		track_len <= wgate ? 14'd12500 
		       : freq == 0 ? 14'd6250 
				 : freq == 1 ? 14'd6666 
				 : freq == 2 ? 14'd7142 : 14'd7692;
end

reg  [13:0] buff_addr;
reg   [7:0] buff_di;
wire  [7:0] buff_do;
reg         buff_we;

iecdrv_trackmem #(14, TRACK_BUF_LEN) buffer
(
	.clock_a(sd_clk),
	.address_a(sd_buff_addr[13:0]),
	.data_a(sd_buff_dout),
	.wren_a(sd_buff_wr & (sd_buff_addr < TRACK_BUF_LEN)),
	.q_a(sd_buff_do),

	.clock_b(clk),
	.address_b(buff_addr),
	.data_b(buff_di),
	.wren_b(buff_we),
	.q_b(buff_do)
);

always @(posedge clk) begin
	reg [21:0] pulse_cnt;

	if (reset || sd_busy || !enable) begin
		pulse_cnt <= 0;
		index     <= 0;
	end
	else if (ce) begin
		index <= 0;
		if (pulse_cnt && pulse_cnt <= 50995)
			index <= 1;

		if (buff_addr == 2 && bit_cnt == 0 && bit_clk_cnt == 'b110000)
			pulse_cnt <= 22'd50995;
		else if (pulse_cnt)
			pulse_cnt <= 22'(pulse_cnt - 1);
		else if (track_len == 0) 
			pulse_cnt <= 22'd3200000;
	end
end

reg [5:0] bit_clk_cnt;
reg [2:0] bit_cnt;

always @(posedge clk) begin
	reg write_r;

	buff_we <= 0;
	hclk    <= 0;
	write_r <= write;

	if (reset || sd_buff_wr) begin
		buff_addr   <= 2;
		bit_clk_cnt <= bitrate;
		bit_cnt     <= 0;
	end
	else if (~enable || !track_len || (write & ~write_r)) begin
		bit_clk_cnt <= bitrate;
		bit_cnt     <= 0;
	end
	else if (~sd_busy && ce) begin
		if (buff_addr >= track_len+2)
			buff_addr <= 2;

		if (bit_clk_cnt == 'b110000) begin
			if (bit_cnt == 0)	buff_di <= buff_do;
			if (write) begin
				buff_di[~bit_cnt] <= ht;
				hf <= ht;
				if (&bit_cnt) buff_we <= 1;
			end
			else begin
				hf   <= buff_do[~bit_cnt];
				hclk <= 1;
			end
		end

		bit_clk_cnt <= bit_clk_cnt + 1'b1;
		if (&bit_clk_cnt) begin
			if (write) hclk <= 1;

			bit_cnt <= bit_cnt + 1'b1;
			if (&bit_cnt) begin
				buff_addr <= buff_addr + 1'd1;
				if (buff_addr >= track_len+1)
					buff_addr <= 2;
			end

			bit_clk_cnt <= bitrate;
		end
	end
end

endmodule
