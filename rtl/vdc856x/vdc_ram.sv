module vdc_ram (
	input          ramsize,   // 0 = 16kB, 1 = 64kB

	input          clk,
	input          reset,

	input          update,    // update register
	input    [7:0] regSel,    // selected register
	input    [7:0] db_in,     // cpu data in

	input          reg_copy,  // copy mode
	output  [15:0] reg_ua,    // update address
	output   [7:0] reg_wc,    // word count
	output   [7:0] reg_da,    // data
	output  [15:0] reg_ba,    // block start address

	output         busy
);

localparam R_IDLE   = 3'd0;
localparam R_READ1  = 3'd1;
localparam R_READ2  = 3'd2;
localparam R_WRITE1 = 3'd3;
localparam R_WRITE2 = 3'd4;
localparam R_COPY1  = 3'd5;
localparam R_COPY2  = 3'd6;
localparam R_COPY3  = 3'd7;

localparam D_IDLE   = 3'd0;

reg  [2:0] regState  = R_IDLE;
reg  [2:0] dispState = D_IDLE;

reg        ram_we;
reg [15:0] ram_addr;
reg  [7:0] ram_di;
reg  [7:0] ram_do;

spram #(8,16) ram
(
	.clk(clk),
	.we(ram_we),
	.addr(ramsize ? {2'b00, ram_addr[13:0]} : ram_addr),
	.data(ram_di),
	.q(ram_do)
);

// RAM interface registers
always @(posedge clk) begin
	if (reset) begin
		regState <= R_IDLE;
		dispState <= D_IDLE;
		reg_ua <= 0;
		reg_wc <= 0;
		reg_da <= 0;
		reg_ba <= 0;
	end
	else if (update)
		case (regSel)
			8'd18: begin
						 reg_ua[15:8]<= db_in;
						 regState    <= R_READ1;
					 end
			8'd19: begin
						 reg_ua[7:0] <= db_in;
						 regState    <= R_READ1;
					 end
			8'd30: begin
						 reg_wc      <= db_in;
						 regState    <= reg_copy ? R_COPY1 : R_WRITE1;
					 end
			8'd31: begin
						 reg_da      <= db_in;
						 regState    <= R_WRITE1;
					 end
			8'd32: reg_ba[15:8]   <= db_in;
			8'd33: reg_ba[7:0]    <= db_in;
		endcase

	ram_we <= 0;
	if (regState == R_READ1) begin
		ram_addr <= reg_ua;
		regState <= R_READ2;
	end
	else if (regState == R_READ2) begin
		reg_da   <= ram_do;
		reg_ua   <= reg_ua + 16'd1;
		regState <= R_IDLE;
	end
	else if (regState == R_WRITE1) begin
		ram_addr <= reg_ua;
		ram_di   <= reg_da;
		ram_we   <= 1;
		regState <= R_WRITE2;
	end
	else if (regState == R_WRITE2) begin
		reg_ua   <= reg_ua + 16'd1;
		if (reg_wc == 8'd0)
			regState <= R_IDLE;
		else begin
			reg_wc   <= reg_wc - 8'd1;
			ram_addr <= reg_ua;
			ram_di   <= reg_da;
			ram_we   <= 1;
			//regState <= R_WRITE2;
		end
	end
	else if (regState == R_COPY1) begin
		ram_addr <= reg_ba;
		regState <= R_COPY2;
	end
	else if (regState == R_COPY2) begin
		ram_di   <= ram_do;
		reg_da   <= ram_do;
		reg_ba   <= reg_ba + 16'd1;
		ram_addr <= reg_ua;
		ram_we   <= 1;
		regState <= R_COPY3;
	end
	else if (regState == R_COPY3) begin
		reg_ua   <= reg_ua + 16'd1;
		if (reg_wc == 8'd0) begin
			regState <= R_IDLE;
		end
		else begin
			reg_wc <= reg_wc - 8'd1;
			ram_addr <= reg_ba;
			regState <= R_COPY2;
		end
	end

	busy <= regState != R_IDLE || dispState != D_IDLE;
end

endmodule
