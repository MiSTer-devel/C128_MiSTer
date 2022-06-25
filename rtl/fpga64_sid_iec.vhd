-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- System runs on 32 Mhz
-- The VIC-II runs in 4 cycles of first 16 cycles.
-- The CPU runs in the last 16 cycles. Effective cpu speed is 1 Mhz.
--
-- -----------------------------------------------------------------------
-- Dar 08/03/2014
--
-- Based on fpga64_cone
-- add external selection for 15KHz(TV)/31KHz(VGA)
-- add external selection for power on NTSC(60Hz)/PAL(50Hz)
-- add external conection in/out for IEC signal
-- add sid entity
-- -----------------------------------------------------------------------
--
-- Alexey Melnikov 2021
--
-- add dma engine
-- implement up to 4x turbo of C128 and smart types.
-- add user port signals
-- various fixes and tweaks
--
-- -----------------------------------------------------------------------
--
-- Erik Scheffers 2022
--
-- extended for C128


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_sid_iec is
port(
	clk32       : in  std_logic;
	reset_n     : in  std_logic;
	dcr         : in  std_logic;
	cpslk_mode  : in  std_logic;

	pause       : in  std_logic := '0';
	pause_out   : out std_logic;

	-- keyboard interface (use any ordinairy PS2 keyboard)
	ps2_key     : in  std_logic_vector(10 downto 0);
	kbd_reset   : in  std_logic := '0';
	sftlk_sense : out std_logic;
	cpslk_sense : out std_logic;
	d4080_sense : out std_logic;
	noscr_sense : out std_logic;

	-- external memory
	ramAddr     : out unsigned(17 downto 0);
	ramDin      : in  unsigned(7 downto 0);
	ramDout     : out unsigned(7 downto 0);
	ramCE       : out std_logic;
	ramWE       : out std_logic;

	io_cycle    : out std_logic;
	ext_cycle   : out std_logic;
	refresh     : out std_logic;

	cia_mode    : in  std_logic;
	turbo_mode  : in  std_logic_vector(1 downto 0);
	turbo_speed : in  std_logic_vector(1 downto 0);

	-- VGA/SCART interface
	ntscMode    : in  std_logic;

	vicHsync    : out std_logic;
	vicVsync    : out std_logic;
	vicR        : out unsigned(7 downto 0);
	vicG        : out unsigned(7 downto 0);
	vicB        : out unsigned(7 downto 0);

	vdcHsync    : out std_logic;
	vdcVsync    : out std_logic;
	vdcHblank   : out std_logic;
	vdcVblank   : out std_logic;
	vdcR        : out unsigned(7 downto 0);
	vdcG        : out unsigned(7 downto 0);
	vdcB        : out unsigned(7 downto 0);

	-- cartridge port
	game        : in  std_logic;
	game_mmu    : out std_logic;
	exrom       : in  std_logic;
	exrom_mmu   : out std_logic;
	io_rom      : in  std_logic;
	io_ext      : in  std_logic;
	io_data     : in  unsigned(7 downto 0);
	irq_n       : in  std_logic;
	nmi_n       : in  std_logic;
	nmi_ack     : out std_logic;
	romL        : out std_logic;
	romH        : out std_logic;
	UMAXromH 	: out std_logic;
	IOE			: out std_logic;
	IOF			: out std_logic;
	freeze_key  : out std_logic;
	mod_key     : out std_logic;
	tape_play   : out std_logic;

	-- dma access
	dma_req     : in  std_logic := '0';
	dma_cycle   : out std_logic;
	dma_addr    : in  unsigned(15 downto 0) := (others => '0');
	dma_dout    : in  unsigned(7 downto 0) := (others => '0');
	dma_din     : out unsigned(7 downto 0);
	dma_we      : in  std_logic := '0';
	irq_ext_n   : in  std_logic := '1';

	-- joystick interface
	joyA        : in  std_logic_vector(6 downto 0);
	joyB        : in  std_logic_vector(6 downto 0);
	pot1        : in  std_logic_vector(7 downto 0);
	pot2        : in  std_logic_vector(7 downto 0);
	pot3        : in  std_logic_vector(7 downto 0);
	pot4        : in  std_logic_vector(7 downto 0);

	--SID
	audio_l     : out std_logic_vector(17 downto 0);
	audio_r     : out std_logic_vector(17 downto 0);
	sid_filter  : in  std_logic_vector(1 downto 0);
	sid_ver     : in  std_logic_vector(1 downto 0);
	sid_mode    : in  unsigned(1 downto 0);
	sid_cfg     : in  std_logic_vector(3 downto 0);
	sid_ld_clk  : in  std_logic;
	sid_ld_addr : in  std_logic_vector(11 downto 0);
	sid_ld_data : in  std_logic_vector(15 downto 0);
	sid_ld_wr   : in  std_logic;

	-- USER
	pb_i        : in  unsigned(7 downto 0);
	pb_o        : out unsigned(7 downto 0);
	pa2_i       : in  std_logic;
	pa2_o       : out std_logic;
	pc2_n_o     : out std_logic;
	flag2_n_i   : in  std_logic;
	sp2_i       : in  std_logic;
	sp2_o       : out std_logic;
	sp1_i       : in  std_logic;
	sp1_o       : out std_logic;
	cnt2_i      : in  std_logic;
	cnt2_o      : out std_logic;
	cnt1_i      : in  std_logic;
	cnt1_o      : out std_logic;

	-- IEC
	iec_data_o	: out std_logic;
	iec_data_i	: in  std_logic;
	iec_clk_o	: out std_logic;
	iec_clk_i	: in  std_logic;
	iec_atn_o	: out std_logic;

	rom_addr    : in  std_logic_vector(15 downto 0);
	rom_data    : in  std_logic_vector(7 downto 0);
	rom14_wr    : in  std_logic;
	rom23_wr    : in  std_logic;
	romF1_wr    : in  std_logic;

	cass_motor  : out std_logic;
	cass_write  : out std_logic;
	cass_sense  : in  std_logic;
	cass_read   : in  std_logic;

	-- VDC
	vdcVersion  : in  unsigned(1 downto 0);
	vdc64k      : in  std_logic;
	vdcInitRam  : in  std_logic;

	-- System memory size
	sys256k     : in  std_logic;
	-- System mode
	c128_n      : out std_logic;
	z80_n       : out std_logic;

	--test
	osmode      : in  std_logic;
	cpumode     : in  std_logic

);
end fpga64_sid_iec;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_sid_iec is
-- System state machine
type sysCycleDef is (
	CYCLE_EXT0, CYCLE_EXT1, CYCLE_EXT2, CYCLE_EXT3,
	CYCLE_DMA0, CYCLE_DMA1, CYCLE_DMA2, CYCLE_DMA3,
	CYCLE_EXT4, CYCLE_EXT5, CYCLE_EXT6, CYCLE_EXT7,
	CYCLE_VIC0, CYCLE_VIC1, CYCLE_VIC2, CYCLE_VIC3,
	CYCLE_CPU0, CYCLE_CPU1, CYCLE_CPU2, CYCLE_CPU3,
	CYCLE_CPU4, CYCLE_CPU5, CYCLE_CPU6, CYCLE_CPU7,
	CYCLE_CPU8, CYCLE_CPU9, CYCLE_CPUA, CYCLE_CPUB,
	CYCLE_CPUC, CYCLE_CPUD, CYCLE_CPUE, CYCLE_CPUF
);

signal sysCycle     : sysCycleDef := sysCycleDef'low;
signal preCycle     : sysCycleDef := sysCycleDef'low;
signal sysEnable    : std_logic;
signal rfsh_cycle   : unsigned(1 downto 0);

signal dma_active   : std_logic;

signal phi0_cpu     : std_logic;
signal cpuHasBus    : std_logic;

signal baLoc        : std_logic;
signal ba_dma       : std_logic;
signal aec          : std_logic;

signal cpuactT65    : std_logic;
signal cpuactT80    : std_logic;
signal cpucycT65    : std_logic;
signal cpucycT80    : std_logic;
signal enableVic    : std_logic;
signal enableVdc    : std_logic;
signal enablePixel0 : std_logic;
signal enablePixel1 : std_logic;
signal enableSid    : std_logic;
signal enable8502   : std_logic;
signal enableZ80    : std_logic;

signal irq_cia1     : std_logic;
signal irq_cia2     : std_logic;
signal irq_vic      : std_logic;

signal systemWe     : std_logic;
signal pulseWr      : std_logic;
signal pulseWr_io   : std_logic;
signal systemAddr   : unsigned(17 downto 0);

signal cs_vic       : std_logic;
signal cs_sid       : std_logic;
signal cs_mmuH      : std_logic;
signal cs_mmuL      : std_logic;
signal cs_vdc       : std_logic;
signal cs_color     : std_logic;
signal cs_cia1      : std_logic;
signal cs_cia2      : std_logic;
signal cs_ram       : std_logic;
signal cpuWe        : std_logic;
signal cpuWe_nd     : std_logic;
signal cpuWe_T65    : std_logic;
signal cpuWe_T80    : std_logic;
signal cpuRd_T80    : std_logic;
signal cpuAddr      : unsigned(15 downto 0);
signal cpuAddr_nd   : unsigned(15 downto 0);
signal cpuAddr_T65  : unsigned(15 downto 0);
signal cpuAddr_T80  : unsigned(15 downto 0);
signal cpuDi        : unsigned(7 downto 0);
signal cpuDi_T80    : unsigned(7 downto 0);
signal cpuDo        : unsigned(7 downto 0);
signal cpuDo_nd     : unsigned(7 downto 0);
signal cpuDo_T65    : unsigned(7 downto 0);
signal cpuDo_T80    : unsigned(7 downto 0);
signal cpuPO        : unsigned(7 downto 0);
signal cpuIO_T80    : std_logic;
signal cpuM1_T80    : std_logic;
signal cpuIrq_n     : std_logic;
signal cpuBusAk_T80_n: std_logic;
signal io_data_i    : unsigned(7 downto 0);
signal ioe_i        : std_logic;
signal iof_i        : std_logic;

signal io_enable    : std_logic;
signal safe_cs      : std_logic;
signal t65_cyc      : std_logic;
signal t65_cyc_s    : std_logic_vector(1 downto 0);
signal turbo_m      : std_logic_vector(2 downto 0);

signal reset        : std_logic := '1';

-- CIA signals
signal enableCia_p  : std_logic;
signal enableCia_n  : std_logic;
signal cia1Do       : unsigned(7 downto 0);
signal cia2Do       : unsigned(7 downto 0);
signal cia1_pai     : unsigned(7 downto 0);
signal cia1_pao     : unsigned(7 downto 0);
signal cia1_pbi     : unsigned(7 downto 0);
signal cia1_pbo     : unsigned(7 downto 0);
signal cia2_pai     : unsigned(7 downto 0);
signal cia2_pao     : unsigned(7 downto 0);
signal cia2_pbi     : unsigned(7 downto 0);
signal cia2_pbo     : unsigned(7 downto 0);
signal cia2_pbe     : unsigned(7 downto 0);

signal todclk       : std_logic;

-- VIC signals
signal vicColorIndex: unsigned(3 downto 0);
signal vicBus       : unsigned(7 downto 0);
signal vicDi        : unsigned(7 downto 0);
signal vicDiAec     : unsigned(7 downto 0);
signal vicAddr      : unsigned(15 downto 0);
signal vicData      : unsigned(7 downto 0);
signal lastVicDi    : unsigned(7 downto 0);
signal vicAddr1514  : unsigned(1 downto 0);
signal colorData    : unsigned(3 downto 0);
signal colorDataAec : unsigned(3 downto 0);
signal turbo_en     : std_logic;
signal turbo_state  : std_logic;
signal vicKo        : unsigned(2 downto 0);

-- VDC signals
signal vdcRGBI      : unsigned(3 downto 0);
signal vdcData      : unsigned(7 downto 0);

-- SID signals
signal sid_do       : unsigned(7 downto 0);
signal sid_sel_l    : std_logic;
signal sid_sel_r    : std_logic;
signal pot_x1       : std_logic_vector(7 downto 0);
signal pot_y1       : std_logic_vector(7 downto 0);
signal pot_x2       : std_logic_vector(7 downto 0);
signal pot_y2       : std_logic_vector(7 downto 0);

-- MMU signals
signal mmu_we       : std_logic;
signal mmu_do       : unsigned(7 downto 0);
signal tAddr        : unsigned(15 downto 0);
signal cpuBank      : unsigned(1 downto 0);
signal vicBank      : unsigned(1 downto 0);
signal colorA10     : std_logic;
signal mmu_exrom    : std_logic;
signal mmu_game     : std_logic;
signal mmu_c128_n   : std_logic;
signal mmu_z80_n    : std_logic;
signal mmu_rombank  : unsigned(1 downto 0);
signal mmu_iosel    : std_logic;

-- Keyboard signals
signal cpslk_sense_kb  : std_logic;
signal cpslk_sense_cpu : std_logic;
signal d4080_sense_kb  : std_logic;

component sid_top
	port (
		reset         : in  std_logic;
		clk           : in  std_logic;
		ce_1m         : in  std_logic;

		cs            : in  std_logic_vector(1 downto 0);
		we            : in  std_logic;
		addr          : in  unsigned(4 downto 0);
		data_in       : in  unsigned(7 downto 0);
		data_out      : out unsigned(7 downto 0);

		pot_x_l       : in  std_logic_vector(7 downto 0) := (others => '0');
		pot_y_l       : in  std_logic_vector(7 downto 0) := (others => '0');
		pot_x_r       : in  std_logic_vector(7 downto 0) := (others => '0');
		pot_y_r       : in  std_logic_vector(7 downto 0) := (others => '0');

		audio_l       : out std_logic_vector(17 downto 0);
		audio_r       : out std_logic_vector(17 downto 0);

		filter_en     : in  std_logic_vector(1 downto 0);
		mode          : in  std_logic_vector(1 downto 0);
		cfg           : in  std_logic_vector(3 downto 0);

		ld_clk        : in  std_logic;
		ld_addr       : in  std_logic_vector(11 downto 0);
		ld_data       : in  std_logic_vector(15 downto 0);
		ld_wr         : in  std_logic
  );
end component;

component mos6526
	PORT (
		clk           : in  std_logic;
		mode          : in  std_logic := '0'; -- 0 - 6526 "old", 1 - 8521 "new"
		phi2_p        : in  std_logic;
		phi2_n        : in  std_logic;
		res_n         : in  std_logic;
		cs_n          : in  std_logic;
		rw            : in  std_logic; -- '1' - read, '0' - write
		rs            : in  unsigned(3 downto 0);
		db_in         : in  unsigned(7 downto 0);
		db_out        : out unsigned(7 downto 0);
		pa_in         : in  unsigned(7 downto 0);
		pa_out        : out unsigned(7 downto 0);
		pa_oe         : out unsigned(7 downto 0);
		pb_in         : in  unsigned(7 downto 0);
		pb_out        : out unsigned(7 downto 0);
		pb_oe         : out unsigned(7 downto 0);
		flag_n        : in  std_logic;
		pc_n          : out std_logic;
		tod           : in  std_logic;
		sp_in         : in  std_logic;
		sp_out        : out std_logic;
		cnt_in        : in  std_logic;
		cnt_out       : out std_logic;
		irq_n         : out std_logic
	);
end component;

component vdc_top
	port (
		version       : in  unsigned(1 downto 0);
		ram64k        : in  std_logic;
		initRam       : in  std_logic;

		clk           : in  std_logic;
		reset         : in  std_logic;
		init          : in  std_logic;

		enableBus     : in  std_logic;
		cs            : in  std_logic;
		we            : in  std_logic;
		lp_n			  : in  std_logic;	

		rs            : in  std_logic;
		db_in         : in  unsigned(7 downto 0);
		db_out        : out unsigned(7 downto 0);

		enablePixel0  : in  std_logic;
		enablePixel1  : in  std_logic;

		hsync         : out std_logic;
		vsync         : out std_logic;
		hblank        : out std_logic;
		vblank        : out std_logic; 
		rgbi          : out unsigned(3 downto 0)
	);
end component;

begin

-- -----------------------------------------------------------------------
-- Local signal to outside world
-- -----------------------------------------------------------------------

io_cycle <= '1' when
	(sysCycle >= CYCLE_EXT0 and sysCycle <= CYCLE_EXT3) or
	(sysCycle >= CYCLE_EXT4 and sysCycle <= CYCLE_EXT7 and rfsh_cycle /= "00")  else '0';

-- -----------------------------------------------------------------------
-- System state machine, controls bus accesses
-- and triggers enables of other components
-- -----------------------------------------------------------------------

sysCycle <= preCycle when sysEnable = '1' else CYCLE_EXT4;
pause_out <= not sysEnable;

process(clk32)
begin
	if rising_edge(clk32) then
		preCycle <= sysCycleDef'succ(preCycle);
		if preCycle = sysCycleDef'high then
			preCycle <= sysCycleDef'low;
			if sysEnable = '1' then
				rfsh_cycle <= rfsh_cycle + 1;
			end if;
		end if;

		refresh <= '0';
		if preCycle = sysCycleDef'pred(CYCLE_EXT4) and rfsh_cycle = "00" then
			sysEnable <= not pause;
			refresh <= '1';
		end if;
	end if;
end process;

process(clk32)
begin
	if rising_edge(clk32) then
		if preCycle = sysCycleDef'high then
			reset <= not reset_n;
		end if;
	end if;
end process;

-- PHI0/2-clock emulation
process(clk32)
variable ba_cnt : integer range 0 to 4 := 0;
begin
	if rising_edge(clk32) then
		if sysCycle = sysCycleDef'pred(CYCLE_CPU0) then
			phi0_cpu <= '1';
			if baLoc = '1' then
				ba_cnt := 0;
			elsif ba_cnt < 4 then
				ba_cnt := ba_cnt + 1;
			end if;
			if baLoc = '1' or 
					(cpuactT65 = '1' and cpuWe = '1' and dma_active = '0') or 
					(cpuactT80 = '1' and ba_cnt < 4 and dma_active = '0') or 
					(ba_dma = '1' and dma_active = '1') 
			then
				cpuHasBus <= '1';
			end if;
		end if;
		if sysCycle = sysCycleDef'high then
			phi0_cpu <= '0';
			cpuHasBus <= '0';
		end if;
	end if;
end process;

process(clk32)
begin
	if rising_edge(clk32) then
		enableVic <= '0';
		enableVdc <= '0';
		enableCia_n <= '0';
		enableCia_p <= '0';
		enableSid <= '0';

		case sysCycle is
		when CYCLE_VIC2 =>
			enableVic <= '1';
		when CYCLE_CPUE =>
			enableVic <= '1';
			enableVdc <= '1';
		when CYCLE_CPUC =>
			enableCia_n <= '1';
		when CYCLE_CPUF =>
			enableCia_p <= '1';
			enableSid <= '1';
		when others =>
			null;
		end case;
	end if;
end process;

-- -----------------------------------------------------------------------
-- Color RAM
-- -----------------------------------------------------------------------
colorram: entity work.spram
generic map (
	DATA_WIDTH => 4,
	ADDR_WIDTH => 11
)
port map (
	clk => clk32,
	we => cs_color and pulseWr,
	addr => colorA10 & systemAddr(9 downto 0),
	data => cpuDo(3 downto 0),
	q => colorData
);

-- -----------------------------------------------------------------------
-- MMU
-- -----------------------------------------------------------------------
mmu: entity work.mmu8722
port map (
	clk => clk32,
	reset => reset,

	cs_io => cs_mmuL,
	cs_lr => cs_mmuH,

	sys256k => sys256k, -- "1" for 256K system memory
	osmode => osmode,  -- debug
	cpumode => cpumode,  -- debug

	we => mmu_we,

	addr => cpuAddr,
	di => cpuDo,
	do => mmu_do,

	tAddr => tAddr,
	cpubank => cpubank,
	vicbank => vicbank,

	d4080 => d4080_sense_kb,

	exromi => exrom,
	exromo => mmu_exrom,

	gamei => game,
	gameo => mmu_game,

	fsdiri => '1',

	c128_n => mmu_c128_n,
	z80_n => mmu_z80_n,

	rombank => mmu_rombank,
	iosel => mmu_iosel
);

mmu_we <= pulseWr when cs_mmuH = '1' else pulseWr_io;

-- -----------------------------------------------------------------------
-- PLA and bus-switches
-- -----------------------------------------------------------------------
buslogic: entity work.fpga64_buslogic
port map (
	clk => clk32,
	reset => reset,
	dcr => dcr,
	cpslk_mode => cpslk_mode,

	cpuHasBus => cpuHasBus,
	aec => aec,

	bankSwitch => cpuPO(2 downto 0),
	c128_n => mmu_c128_n,
	z80_n => mmu_z80_n,
	z80io => cpuIO_T80,
	z80m1 => cpuM1_T80,
	mmu_rombank => mmu_rombank,
	mmu_iosel => mmu_iosel,
	tAddr => tAddr,
	cpuBank => cpuBank,
	vicBank => vicBank,
	cpslk_sense => cpslk_sense_cpu,

	game => mmu_game,
	exrom => mmu_exrom,
	io_rom => io_rom,
	io_ext => io_ext or sid_sel_r,
	io_data => io_data_i,

	ramData => ramDin,

	cpuWe => cpuWe,
	cpuAddr => cpuAddr,
	cpuData => cpuDo,
	vicAddr => vicAddr,
	vicData => vicData,
	sidData => sid_do,
	mmuData => mmu_do,
	vdcData => vdcData,
	colorData => colorData,
	cia1Data => cia1Do,
	cia2Data => cia2Do,
	lastVicData => lastVicDi,

	systemWe => systemWe,
	systemAddr => systemAddr,
	dataToCpu => cpuDi,
	dataToVic => vicDi,
	colorA10  => colorA10,

	io_enable => io_enable,

	cs_vic => cs_vic,
	cs_sid => cs_sid,
	cs_mmuH => cs_mmuH,
	cs_mmuL => cs_mmuL,
	cs_vdc => cs_vdc,
	cs_color => cs_color,
	cs_cia1 => cs_cia1,
	cs_cia2 => cs_cia2,
	cs_ram => cs_ram,
	cs_ioE => ioe_i,
	cs_ioF => iof_i,
	cs_romL => romL,
	cs_romH => romH,
	cs_UMAXromH => UMAXromH,

	rom_addr => rom_addr,
	rom_data => rom_data,
	rom14_wr => rom14_wr,
	rom23_wr => rom23_wr,
	romF1_wr => romF1_wr
);

IOE <= ioe_i;
IOF <= iof_i;

process(clk32)
begin
	if rising_edge(clk32) then
		pulseWr <= '0';
		pulseWr_io <= '0';
		if cpuWe = '1' then
			if cpuactT65 = '1' and t65_cyc = '1' then
				pulseWr <= '1';
			end if;
			if sysCycle = CYCLE_CPUC then
				pulseWr <= '1';
				pulseWr_io <= '1';
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- VIC-II video interface chip
-- -----------------------------------------------------------------------
process(clk32)
begin
	if rising_edge(clk32) then
		if phi0_cpu = '1' then
			if cpuWe = '1' and cs_vic = '1' then
				vicBus <= cpuDo;
			else
				vicBus <= x"FF";
			end if;
		end if;
	end if;
end process;

-- In the first three cycles after BA went low, the VIC reads
-- $ff as character pointers and
-- as color information the lower 4 bits of the opcode after the access to $d011.
vicDiAec <= vicBus when aec = '0' else vicDi;
colorDataAec <= cpuDi(3 downto 0) when aec = '0' else colorData;

vic: entity work.video_vicii_656x
generic map (
	registeredAddress => true,
	emulateRefresh => true,
	emulateLightpen => true,
	emulateGraphics => true
)
port map (
	clk => clk32,
	reset => reset,
	enaPixel => enablePixel1,
	enaData => enableVic,
	phi => phi0_cpu,

	baSync => '0',
	ba => baLoc,
	ba_dma => ba_dma,

	mode6569 => '0',
	mode6567old => '0',
	mode6567R8 => '0',
	mode6572 => '0',

	mode8564 => ntscMode,
	mode8566 => (not ntscMode),
	mode8569 => '0',

	turbo_en => turbo_en,
	turbo_state => turbo_state,

	cs => cs_vic,
	we => cpuWe,
	lp_n => cia1_pbi(4),

	aRegisters => tAddr(5 downto 0),
	diRegisters => cpuDo,
	di => vicDiAec,
	diColor => colorDataAec,
	do => vicData,
	ko => vicKo,

	vicAddr => vicAddr(13 downto 0),
	addrValid => aec,

	hSync => vicHsync,
	vSync => vicVsync,
	colorIndex => vicColorIndex,

	irq_n => irq_vic
);

vicColors: entity work.fpga64_rgbcolor
port map (
	index => vicColorIndex,
	r => vicR,
	g => vicG,
	b => vicB
);

process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = CYCLE_VIC3 then
			lastVicDi <= vicDi;
		end if;
	end if;
end process;

-- VIC bank to address lines
-- (C128 does not have glitch that C64C has)
process(clk32)
begin
	if rising_edge(clk32) then
		if phi0_cpu = '0' and enableVic = '1' then
			vicAddr(15 downto 14) <= not cia2_pao(1 downto 0);
		end if;
	end if;
end process;

-- Pixel timing
process(clk32)
begin
	if rising_edge(clk32) then
		enablePixel0 <= '0';
		enablePixel1 <= '0';

		case sysCycle is
		when CYCLE_EXT0 => enablePixel0 <= '1';
		when CYCLE_EXT2 => enablePixel1 <= '1';
		when CYCLE_DMA0 => enablePixel0 <= '1';
		when CYCLE_DMA2 => enablePixel1 <= '1';
		when CYCLE_EXT4 => enablePixel0 <= '1';
		when CYCLE_EXT6 => enablePixel1 <= '1';
		when CYCLE_VIC0 => enablePixel0 <= '1';
		when CYCLE_VIC2 => enablePixel1 <= '1';
		when CYCLE_CPU0 => enablePixel0 <= '1';
		when CYCLE_CPU2 => enablePixel1 <= '1';
		when CYCLE_CPU4 => enablePixel0 <= '1';
		when CYCLE_CPU6 => enablePixel1 <= '1';
		when CYCLE_CPU8 => enablePixel0 <= '1';
		when CYCLE_CPUA => enablePixel1 <= '1';
		when CYCLE_CPUC => enablePixel0 <= '1';
		when CYCLE_CPUE => enablePixel1 <= '1';
		when others     => null;
		end case;
	end if;
end process;

-- -----------------------------------------------------------------------
-- VDC 80-col video display controller
-- -----------------------------------------------------------------------

vdc: vdc_top
port map (
	version => vdcVersion,
	ram64k => vdc64k,
	initRam => vdcInitRam,

	clk => clk32,
	reset => reset,
	init => '0',

	enableBus => enableVdc,
	cs => cs_vdc,
	we => cpuWe,
	lp_n => cia1_pbi(4),

	rs => tAddr(0),
	db_in => cpuDo,
	db_out => vdcData,

	enablePixel0 => enablePixel0,
	enablePixel1 => enablePixel1,

	hsync => vdcHsync,
	vsync => vdcVsync,
	hblank => vdcHblank,
	vblank => vdcVblank,
	rgbi => vdcRGBI
);

vdcColors: entity work.rgbicolor
port map (
	rgbi => vdcRGBI,
	r => vdcR,
	g => vdcG,
	b => vdcB
);

-- -----------------------------------------------------------------------
-- SID
-- -----------------------------------------------------------------------

--	Right SID Port: Same,D420,DE00,DF00

sid_sel_l <= cs_sid when sid_mode /= 1 else (cs_sid and not tAddr(5));
sid_sel_r <= cs_sid when sid_mode = 0 else ioe_i when sid_mode = 2 else iof_i when sid_mode = 3 else (cs_sid and tAddr(5));
io_data_i <= io_data when io_ext = '1' else sid_do when sid_sel_r = '1' else (others => '1');

pot_x1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot1;
pot_y1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot2;
pot_x2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot3;
pot_y2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot4;

sid : sid_top
port map (
	reset => reset,
	clk => clk32,
	ce_1m => enableSid,
	we => pulseWr_io,
	cs => sid_sel_r & sid_sel_l,
	addr => tAddr(4 downto 0),
	data_in => cpuDo,
	data_out => sid_do,
	pot_x_l => pot_x1 and pot_x2,
	pot_y_l => pot_y1 and pot_y2,

	audio_l => audio_l,
	audio_r => audio_r,

	filter_en => sid_filter,
	mode    => sid_ver,
	cfg     => sid_cfg,

	ld_clk  => sid_ld_clk,
	ld_addr => sid_ld_addr,
	ld_data => sid_ld_data,
	ld_wr   => sid_ld_wr
);

-- -----------------------------------------------------------------------
-- CIAs
-- -----------------------------------------------------------------------
cia1: mos6526
port map (
	clk => clk32,
	mode => cia_mode,
	phi2_p => enableCia_p,
	phi2_n => enableCia_n,
	res_n => not reset,
	cs_n => not cs_cia1,
	rw => not cpuWe,

	rs => tAddr(3 downto 0),
	db_in => cpuDo,
	db_out => cia1Do,

	pa_in => cia1_pai,
	pa_out => cia1_pao,
	pb_in => cia1_pbi,
	pb_out => cia1_pbo,

	flag_n => cass_read,
	sp_in => sp1_i,
	sp_out => sp1_o,
	cnt_in => cnt1_i,
	cnt_out => cnt1_o,

	tod => todclk,

	irq_n => irq_cia1
);

cia2: mos6526
port map (
	clk => clk32,
	mode => cia_mode,
	phi2_p => enableCia_p,
	phi2_n => enableCia_n,
	res_n => not reset,
	cs_n => not cs_cia2,
	rw => not cpuWe,

	rs => tAddr(3 downto 0),
	db_in => cpuDo,
	db_out => cia2Do,

	pa_in => cia2_pai and cia2_pao,
	pa_out => cia2_pao,
	pb_in => (pb_i and not cia2_pbe) or (cia2_pbo and cia2_pbe),
	pb_out => cia2_pbo,
	pb_oe => cia2_pbe,

	flag_n => flag2_n_i,
	pc_n => pc2_n_o,

	sp_in => sp2_i,
	sp_out => sp2_o,
	cnt_in => cnt2_i,
	cnt_out => cnt2_o,

	tod => todclk,

	irq_n => irq_cia2
);

serialBus: process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = CYCLE_EXT5 then
			cia2_pai(7) <= iec_data_i and not cia2_pao(5);
			cia2_pai(6) <= iec_clk_i and not cia2_pao(4);
		end if;
	end if;
end process;

cia2_pai(5 downto 0) <= "111" & pa2_i & "11";

iec_data_o <= not cia2_pao(5);
iec_clk_o  <= not cia2_pao(4);
iec_atn_o  <= not cia2_pao(3);

pb_o  <= cia2_pbo;
pa2_o <= cia2_pao(2);

process(clk32)
variable sum: integer range 0 to 33000000;
begin
	if rising_edge(clk32) then
		if reset = '1' then
			todclk <= '0';
			sum := 0;
		elsif ntscMode = '1' then
			sum := sum + 120;
			if sum >= 32727266 then
				sum := sum - 32727266;
				todclk <= not todclk;
			end if;
		else
			sum := sum + 100;
			if sum >= 31527954 then
				sum := sum - 31527954;
				todclk <= not todclk;
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- CPU / DMA
-- -----------------------------------------------------------------------
cpuIrq_n <= irq_cia1 and irq_vic and irq_n and irq_ext_n;

cpu_6510: entity work.cpu_6510
port map (
	clk => clk32,
	reset => reset,
	enable => cpuactT65 and cpucycT65 and not dma_active,
	nmi_n => irq_cia2 and nmi_n,
	nmi_ack => nmi_ack,
	irq_n => cpuIrq_n,
	rdy => baLoc and not cpuactT80,

	di => cpuDi,
	addr => cpuAddr_T65,
	do => cpuDo_T65,
	we => cpuWe_T65,

	diIO => cpuPO(7) & cpslk_sense_kb & cpuPO(5) & cass_sense & cpuPO(3) & "111",
	doIO => cpuPO
);

cpslk_sense_cpu <= cpuPO(6);
cass_motor <= cpuPO(5);
cass_write <= cpuPO(3);

cpu_z80: entity work.cpu_z80
port map (
	clk => clk32,
	reset => reset,
	enable => cpucycT80 and not dma_active,
	busrq_n => baLoc and cpuactT80,
	busak_n => cpuBusAk_T80_n,
	irq_n => cpuIrq_n,

	di => cpuDi_T80,
	addr => cpuAddr_T80,
	do => cpuDo_T80,
	rd => cpuRd_T80,
	we => cpuWe_T80,
	io => cpuIO_T80,
	m1 => cpuM1_T80
);

process(clk32)
variable We : std_logic;
begin
	if rising_edge(clk32) then
		if sysCycle = sysCycleDef'high then
			if cpuRd_T80 = '1' then
				cpuDi_T80 <= cpuDi;
			end if;
		end if;
	end if;
end process;

ramDout <= cpuDo;
ramAddr <= systemAddr;
ramWE   <= systemWe when sysCycle >= CYCLE_CPU0 else '0';
ramCE   <= cs_ram when 
   		  sysCycle = CYCLE_VIC0 or 
			  (cpuactT65 = '1' and t65_cyc = '1') or 
			  (cpuactT65 = '0' and sysCycle = CYCLE_CPUC) else '0';
safe_cs <= cs_ram or cs_color or cs_mmuH;  -- safe to access in 8502 turbo mode
t65_cyc <= '1' when
				(sysCycle = CYCLE_CPU0 and turbo_m(0) = '1' and safe_cs = '1' ) or
				(sysCycle = CYCLE_CPU4 and turbo_m(1) = '1' and safe_cs = '1' ) or
				(sysCycle = CYCLE_CPU8 and turbo_m(2) = '1' and safe_cs = '1' ) or
				(sysCycle = CYCLE_CPUC and (io_enable = '1'  or safe_cs = '1')) else '0';
cpucycT80 <= '1' when sysCycle = CYCLE_CPU0 else '0';

process(clk32)
begin
	if rising_edge(clk32) then
		t65_cyc_s <= t65_cyc_s(0) & t65_cyc;
		cpucycT65 <= t65_cyc_s(1);

		-- IO enable
		if cpuactT65 = '1' then
			io_enable <= io_enable and not cpucycT65;
		end if;		
		if sysCycle = CYCLE_EXT0 then
			io_enable <= '1';
		end if;

		-- CPU selection
		if (sysCycle = sysCycleDef'pred(CYCLE_CPU0)) then
			cpuactT65 <= mmu_z80_n and not cpuBusAk_T80_n;
			cpuactT80 <= not mmu_z80_n;
		end if; 

		-- 2 points to register DMA request before CPU cycles.
		if sysCycle = CYCLE_EXT1 or sysCycle = CYCLE_EXT5 then
			dma_active <= dma_req;
			turbo_en <= turbo_mode(0);
			turbo_m <= "000";
			if dma_req = '0' then
				if ((turbo_mode(0) and turbo_state) = '1' or turbo_mode(1) = '1') then
					case turbo_speed is
						when "00" => turbo_m <= "010";
						when "01" => turbo_m <= "110";
						when "10" => turbo_m <= "111";
						when "11" => turbo_m <= "111"; -- unused
					end case;
				end if;
			end if;
		end if;
	end if;
end process;

cpuAddr_nd <= cpuAddr_T65 when cpuactT65 = '1' else cpuAddr_T80;
cpuDo_nd   <= cpuDo_T65   when cpuactT65 = '1' else cpuDo_T80;
cpuWe_nd   <= cpuWe_T65   when cpuactT65 = '1' else cpuWe_T80;

cpuAddr <= cpuAddr_nd when dma_active = '0' else dma_addr;
cpuDo   <= cpuDo_nd   when dma_active = '0' else dma_dout;
cpuWe   <= cpuWe_nd   when dma_active = '0' else dma_we;

ext_cycle <= '1' when (sysCycle >= CYCLE_DMA0 and sysCycle <= CYCLE_DMA3) else '0';
dma_cycle <= '1' when (sysCycle >= CYCLE_CPU0 and sysCycle <= CYCLE_CPUF) and cpuHasBus = '1' and dma_active = '1' else '0';
dma_din   <= cpuDi;

c128_n <= mmu_c128_n;
z80_n <= mmu_z80_n;

exrom_mmu <= mmu_exrom;
game_mmu <= mmu_game;

-- -----------------------------------------------------------------------
-- Keyboard
-- -----------------------------------------------------------------------
cpslk_sense <= cpslk_sense_kb;
d4080_sense <= d4080_sense_kb;

Keyboard: entity work.fpga64_keyboard
port map (
	clk => clk32,

	reset => kbd_reset,
	ps2_key => ps2_key,

	joyA => not unsigned(joyA(6 downto 0)),
	joyB => not unsigned(joyB(6 downto 0)),
	pai => cia1_pao,
	pbi => cia1_pbo,
	pao => cia1_pai,
	pbo => cia1_pbi,
	ki => vicKo,

	restore_key => freeze_key,
	tape_play => tape_play,
	mod_key => mod_key,
	
	sftlk_sense => sftlk_sense,
	cpslk_sense => cpslk_sense_kb,
	d4080_sense => d4080_sense_kb,
	noscr_sense => noscr_sense,

	backwardsReadingEnabled => '1'
);

end architecture;
