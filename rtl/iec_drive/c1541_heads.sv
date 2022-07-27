module c1541_heads #(parameter DRIVE)
(
	input        clk,
	input        ce,
	input        reset,
	input        enable,

	input  [1:0] freq,
   input        wgate,

   output       hclk,
	output       hf,  // signal from head
	input        ht,  // signal to head

	output       index,
	
	input			 sd_busy,
	input        sd_clk,
	input [15:0] sd_buff_addr,
	input  [7:0] sd_buff_dout,
	output [7:0] sd_buff_din,
	input        sd_buff_wr
);

localparam BUFFWIDTH=14;

wire [5:0] bit_clk = {2'b00,freq,2'b00};

assign sd_buff_din = (sd_buff_addr > track_len) ? 8'hFF : ram_q;

reg [BUFFWIDTH-1:0] track_len;
always @(posedge sd_clk) if(sd_buff_wr && !sd_buff_addr[BUFFWIDTH-1:1]) begin
	// size and possible flags
	if(sd_buff_addr[0] == 0) track_len[7:0]           <= sd_buff_dout;
	if(sd_buff_addr[0] == 1) track_len[BUFFWIDTH-1:8] <= sd_buff_dout[BUFFWIDTH-9:0];
end

wire                 ram_clk  = sd_busy ? sd_clk                                    : clk;
wire [BUFFWIDTH-1:0] ram_addr = sd_busy ? sd_buff_addr[BUFFWIDTH-1:0]               : buff_addr;
wire           [7:0] ram_q;
wire           [7:0] ram_data = sd_busy ? sd_buff_dout                              : buff_di;
wire                 ram_wren = sd_busy ? sd_buff_wr & ~|sd_buff_addr[15:BUFFWIDTH] : buff_we;

iecdrv_trackmem #(BUFFWIDTH) buffer
(
	.clock(ram_clk),
	.address(ram_addr),
	.data(ram_data),
	.wren(ram_wren),
	.q(ram_q)
);

reg [BUFFWIDTH-1:0] buff_addr;
reg           [7:0] buff_di;
reg                 buff_we;

always @(posedge clk) begin
	reg [5:0] bit_clk_cnt;
	reg [2:0] bit_cnt;
	reg       index_d;
	// reg [2:0] bit_ready;

   // bit_ready <= {bit_ready[1:0], 1'b0};
	buff_we   <= 0;
   index     <= 0;
	hclk      <= 0;

	if(reset) begin
		buff_addr   <= 2;
		bit_clk_cnt <= bit_clk;
		bit_cnt     <= 0;
		index_d     <= 0;
      // bit_ready   <= 0;
	end
	else if(~enable | sd_busy) begin
		bit_clk_cnt <= bit_clk;
      // bit_ready   <= 0;
	end
	else if (ce) begin
		if (buff_addr > track_len) begin
			buff_addr <= 2;
			// index_n   <= 0;
		end

		if (bit_clk_cnt == 'b110000) begin
			if (wgate) begin
				buff_di[~bit_cnt] <= ht;
				buff_we <= 1;
				hf      <= ht;
			end
			else begin
				hf      <= ram_q[~bit_cnt];
				hclk    <= 1;
				index   <= index_d;
				index_d <= 0;
			end
		end

		bit_clk_cnt <= bit_clk_cnt + 1'b1;
		if (&bit_clk_cnt) begin
			// bit_ready[0] <= 1;
			if (wgate) hclk <= 1;

			bit_cnt <= bit_cnt + 1'b1;
			if (bit_cnt == 7) begin
				buff_addr <= buff_addr + 1'd1;
				if (buff_addr >= track_len) begin
					buff_addr <= 2;
					if (wgate) 
						index <= 1; 
					else 
						index_d <= 1;
				end
			end

			bit_clk_cnt <= bit_clk;
		end
	end
end

endmodule
