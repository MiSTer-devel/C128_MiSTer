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
generic (
   VDC_ADDR_BITS : integer := 16
);
port(
   clk32       : in  std_logic;
   clk_vdc     : in  std_logic;
   reset_n     : in  std_logic;

   pause       : in  std_logic := '0';
   pause_out   : out std_logic;

   -- keyboard interface (use any ordinairy PS2 keyboard)
   ps2_key     : in  std_logic_vector(10 downto 0);
   kbd_reset   : in  std_logic := '0';
   shift_mod   : in  std_logic_vector(1 downto 0);
   azerty      : in  std_logic;
   cpslk_mode  : in  std_logic;
   sftlk_sense : out std_logic;
   cpslk_sense : out std_logic;
   d4080_sense : out std_logic;
   noscr_sense : out std_logic;
   go64        : in  std_logic;

   -- external memory
   ramAddr     : out unsigned(17 downto 0);
   ramDin      : in  unsigned(7 downto 0);
   ramDinFloat : in  std_logic;
   ramDout     : out unsigned(7 downto 0);
   ramCE       : out std_logic;
   ramWE       : out std_logic;

   io_cycle    : out std_logic;
   ext_cycle   : out std_logic;
   refresh     : out std_logic;

   cia_mode    : in  std_logic;
   turbo_mode  : in  std_logic_vector(2 downto 0);

   -- VGA/SCART interface
   vic_variant : in  std_logic_vector(1 downto 0);
   ntscMode    : in  std_logic;
   vicJailbars : in  std_logic_vector(1 downto 0);

   vicHsync    : out std_logic;
   vicVsync    : out std_logic;
   vicR        : out unsigned(7 downto 0);
   vicG        : out unsigned(7 downto 0);
   vicB        : out unsigned(7 downto 0);

   vdcHsync    : out std_logic;
   vdcVsync    : out std_logic;
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
   romFL       : out std_logic;
   romFH       : out std_logic;
   romL        : out std_logic;
   romH        : out std_logic;
   UMAXromH 	: out std_logic;
   IOE			: out std_logic;
   IOF			: out std_logic;
   freeze_key  : out std_logic;
   mod_key     : out std_logic;
   tape_play   : out std_logic;

   -- system ROMs
   sysRom      : out std_logic;
   sysRomBank  : out unsigned(4 downto 0);

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
	sid_mode    : in  unsigned(2 downto 0);
	sid_cfg     : in  std_logic_vector(3 downto 0);
	sid_fc_off_l: in  std_logic_vector(12 downto 0);
	sid_fc_off_r: in  std_logic_vector(12 downto 0);
	sid_ld_clk  : in  std_logic;
	sid_ld_addr : in  std_logic_vector(11 downto 0);
	sid_ld_data : in  std_logic_vector(15 downto 0);
	sid_ld_wr   : in  std_logic;
	sid_digifix : in  std_logic;

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
   iec_srq_n_o : out std_logic;
   iec_srq_n_i : in  std_logic;
   iec_atn_o	: out std_logic;

   cass_motor  : out std_logic;
   cass_write  : out std_logic;
   cass_sense  : in  std_logic;
   cass_read   : in  std_logic;

   -- VDC
   vdcVersion  : in  std_logic;
   vdc64k      : in  std_logic;
   vdcInitRam  : in  std_logic;
   vdcPalette  : in  unsigned(3 downto 0);
   vdcDebug    : in  std_logic;

   -- D7xx port
   d7port      : out unsigned(7 downto 0);
   d7port_trig : out std_logic;

   -- System memory size
   sys256k     : in  std_logic;

   -- System mode
   force64     : in  std_logic;
   pure64      : in  std_logic;
   d4080_sel   : in  std_logic;
   c128_n      : out std_logic;
   z80_n       : out std_logic
);
end fpga64_sid_iec;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_sid_iec is
-- System state machine
type sysCycleDef is (
   CYCLE_EXT0, CYCLE_EXT1, CYCLE_EXT2, CYCLE_EXT3,  -- MiSTer external I/O
   CYCLE_VIC0, CYCLE_VIC1, CYCLE_VIC2, CYCLE_VIC3,  -- VIC
   CYCLE_EXT4, CYCLE_EXT5, CYCLE_EXT6, CYCLE_EXT7,  -- MiSTer external I/O
   CYCLE_DMA0, CYCLE_DMA1, CYCLE_DMA2, CYCLE_DMA3,  -- DMA (REU)
   CYCLE_CPU0, CYCLE_CPU1, CYCLE_CPU2, CYCLE_CPU3,  -- 8502 x4, Z80 normal
   CYCLE_CPU4, CYCLE_CPU5, CYCLE_CPU6, CYCLE_CPU7,  -- 8502 normal, Z80 normal, VIC badline
   CYCLE_CPU8, CYCLE_CPU9, CYCLE_CPUA, CYCLE_CPUB,  -- 8502 x3, Z80 x2
   CYCLE_CPUC, CYCLE_CPUD, CYCLE_CPUE, CYCLE_CPUF   -- 8502 fast/x2, Z80 x2
);

signal sysCycle     : sysCycleDef := sysCycleDef'low;
signal preCycle     : sysCycleDef := sysCycleDef'low;
signal sysEnable    : std_logic;
signal rfsh_cycle   : unsigned(1 downto 0);

signal dma_pending  : std_logic;
signal dma_active   : std_logic;

signal phi0_cpu     : std_logic;
signal cpuCycle     : std_logic;
signal vicCycle     : std_logic;
signal cpuHasBus    : std_logic;

signal baLoc        : std_logic;
signal ba_dma       : std_logic;
signal aec          : std_logic;
signal vicRefresh   : std_logic;

signal cpuActT65    : std_logic;
signal cpuCycT65    : std_logic;
signal cpuCycT80    : std_logic;
signal cpuLatT80    : std_logic;

signal enableMmu    : std_logic;
signal enableVic    : std_logic;
signal enableVdc    : std_logic;
signal enableVdc_sl : std_logic_vector(1 downto 0);
signal enablePixel  : std_logic;
signal enableSid    : std_logic;
signal enable8502   : std_logic;
signal enableZ80    : std_logic;

signal irq_cia1     : std_logic;
signal irq_cia2     : std_logic;
signal irq_vic      : std_logic;

signal systemWe     : std_logic;
signal pulseWr_io   : std_logic;
signal systemAddr   : unsigned(17 downto 0);

signal cs_vic       : std_logic;
signal cs_sid       : std_logic;
signal cs_mmuL      : std_logic;
signal cs_vdc       : std_logic;
signal cs_color     : std_logic;
signal cs_cia1      : std_logic;
signal cs_cia2      : std_logic;
signal cs_mmuH      : std_logic;
signal cs_ram       : std_logic;
signal cpuWe        : std_logic;
signal cpuWe_T65    : std_logic;
signal cpuWe_T80    : std_logic;
signal cpuAddr      : unsigned(15 downto 0);
signal cpuAddr_T65  : unsigned(15 downto 0);
signal cpuAddr_T80  : unsigned(15 downto 0);
signal cpuDi        : unsigned(7 downto 0);
signal cpuDo        : unsigned(7 downto 0);
signal cpuDo_T65    : unsigned(7 downto 0);
signal cpuDo_T80    : unsigned(7 downto 0);
signal cpuData      : unsigned(7 downto 0);
signal cpuData_l    : unsigned(7 downto 0);
signal cpuLastData  : unsigned(7 downto 0);
signal cpuPacc      : std_logic;
signal cpuPO        : unsigned(7 downto 0);
signal cpuIO_T80    : std_logic;
signal cpuM1_T80    : std_logic;
signal cpuIrq_n     : std_logic;
signal cpuBusAk_T80_n: std_logic;
signal io_data_i    : unsigned(7 downto 0);
signal io7_i        : std_logic;
signal ioe_i        : std_logic;
signal iof_i        : std_logic;

signal io_enable    : std_logic;
signal cs_enable    : std_logic;
signal cs_io        : std_logic;
signal cs_io_l      : std_logic;
signal t65_cyc      : std_logic;
signal t65_cyc_s    : std_logic;
signal t65_turbo_m  : std_logic_vector(2 downto 0);
signal t80_cyc      : std_logic;
signal t80_cyc_s    : std_logic;
signal t80_turbo_m  : std_logic;
signal turbo_std    : std_logic;

signal reset        : std_logic := '1';
signal reset_t80    : std_logic := '1';

-- CIA signals
signal enableCia_p  : std_logic;
signal enableCia_n  : std_logic;
signal cia1Do       : unsigned(7 downto 0);
signal cia2Do       : unsigned(7 downto 0);
signal cia1_pai     : unsigned(7 downto 0);
signal cia1_pao     : unsigned(7 downto 0);
signal cia1_pbi     : unsigned(7 downto 0);
signal cia1_pbo     : unsigned(7 downto 0);
signal cia1_sp_i    : std_logic;
signal cia1_sp_o    : std_logic;
signal cia1_cnt_i   : std_logic;
signal cia1_cnt_o   : std_logic;
signal cia1_flag_n  : std_logic;
signal cia2_pai     : unsigned(7 downto 0);
signal cia2_pao     : unsigned(7 downto 0);
signal cia2_pbi     : unsigned(7 downto 0);
signal cia2_pbo     : unsigned(7 downto 0);
signal cia2_pbe     : unsigned(7 downto 0);

signal todclk       : std_logic;

-- IEC Fast Serial
signal fclk_o       : std_logic;
signal fs_i         : std_logic;
signal fs_o         : std_logic;

-- VIC signals
signal vicColorIndex: unsigned(3 downto 0);
signal vicInvertV   : std_logic;
signal vicDi        : unsigned(7 downto 0);
signal vicDiAec     : unsigned(7 downto 0);
signal vicAddr      : unsigned(15 downto 0);
signal vicData      : unsigned(7 downto 0);
signal vicHS        : std_logic;
signal vicRo        : unsigned(7 downto 0);
signal vicGo        : unsigned(7 downto 0);
signal vicBo        : unsigned(7 downto 0);
signal lastVicDi    : unsigned(7 downto 0);
signal vicAddr1514  : unsigned(1 downto 0);
signal colorData    : unsigned(3 downto 0);
signal colorDataAec : unsigned(3 downto 0);
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
signal fsdir_n      : std_logic;

-- Keyboard signals
signal cpslk_sense_kb  : std_logic;
signal cpslk_sense_cpu : std_logic;

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

		ext_in_l      : in  std_logic_vector(17 downto 0);
		ext_in_r      : in  std_logic_vector(17 downto 0);

		fc_offset_l   : in  std_logic_vector(12 downto 0);
		fc_offset_r   : in  std_logic_vector(12 downto 0);

		filter_en     : in  std_logic_vector(1 downto 0);
		mode          : in  std_logic_vector(1 downto 0);
		cfg           : in  std_logic_vector(3 downto 0);

      ld_clk        : in  std_logic;
      ld_addr       : in  std_logic_vector(11 downto 0);
      ld_data       : in  std_logic_vector(15 downto 0);
      ld_wr         : in  std_logic
  );
end component;

component mos6526_8520
   PORT (
      clk           : in  std_logic;
      mode          : in  unsigned(1 downto 0) := "00"; -- 0 - 6526, 1 - 8521, 2 - 8520
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
   generic (
      RAM_ADDR_BITS : integer
   );
   port (
      version       : in  std_logic;
      ram64k        : in  std_logic;
      initRam       : in  std_logic;
      debug         : in  std_logic;

      clk           : in  std_logic;
      reset         : in  std_logic;
      init          : in  std_logic;

      enableBus     : in  std_logic;
      cs            : in  std_logic;
      we            : in  std_logic;
      rs            : in  std_logic;
      db_in         : in  unsigned(7 downto 0);
      db_out        : out unsigned(7 downto 0);

      lp_n			  : in  std_logic;

      hsync         : out std_logic;
      vsync         : out std_logic;
      rgbi          : out unsigned(3 downto 0)
   );
end component;

component video_vicIIe_jb
   PORT (
      clk           : in  std_logic;
      mode          : in  std_logic_vector(1 downto 0);

      hsync         : in  std_logic;
      Ri            : in  unsigned(7 downto 0);
      Gi            : in  unsigned(7 downto 0);
      Bi            : in  unsigned(7 downto 0);

      Ro            : out unsigned(7 downto 0);
      Go            : out unsigned(7 downto 0);
      Bo            : out unsigned(7 downto 0)
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
         reset_t80 <= not reset_n and cpuBusAk_T80_n;
      end if;
   end if;
end process;

-- phi0 & bus arbitration

phi0_cpu <= '1' when (sysCycle >= CYCLE_EXT4 and sysCycle <= CYCLE_CPU7) else '0';
vicCycle <= '1' when ((sysCycle >= CYCLE_VIC0 and sysCycle <= CYCLE_VIC3)
                   or (sysCycle >= CYCLE_CPU4 and sysCycle <= CYCLE_CPU7)) else '0';
cpuCycle <= '1' when (sysCycle >= CYCLE_CPU0 and sysCycle <= CYCLE_CPUF) else '0';

cpuHasBus <= not (aec and vicCycle);

process(clk32)
begin
   if rising_edge(clk32) then
      enableVic <= '0';
      enableCia_n <= '0';
      enableCia_p <= '0';
      enableSid <= '0';
      enableMmu <= '0';

      case sysCycle is
      when CYCLE_VIC2 =>
         enableVic <= '1';
      when CYCLE_CPU0 =>
         enableCia_n <= '1';
         enableMmu <= '1';
      when CYCLE_CPU4 | CYCLE_CPU8 | CYCLE_CPUC =>
         enableMmu <= '1';
      when CYCLE_CPU6 =>
         enableVic <= '1';
      when CYCLE_CPU7 =>
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
   we => cs_color and pulseWr_io,
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
   enable => enableMmu,

   cs_io => cs_mmuL and cs_enable,
   cs_lr => cs_mmuH,

   osmode => force64,
   cpumode => force64,
   sys256k => sys256k, -- "1" for 256K system memory

   we => cpuWe,

   addr => cpuAddr,
   di => cpuDo,
   do => mmu_do,

   tAddr => tAddr,
   cpubank => cpubank,
   vicBank => vicBank,

   d4080i => d4080_sel,

   exromi => exrom,
   exromo => mmu_exrom,

   gamei => game,
   gameo => mmu_game,

   fsdiro => fsdir_n,

   c128_n => mmu_c128_n,
   z80_n => mmu_z80_n,

   rombank => mmu_rombank,
   iosel => mmu_iosel
);

-- -----------------------------------------------------------------------
-- PLA and bus-switches
-- -----------------------------------------------------------------------
buslogic: entity work.fpga64_buslogic
port map (
   clk => clk32,
   reset => reset,
   pure64 => pure64,
   cpslk_mode => cpslk_mode,

   cpuHasBus => cpuHasBus,
   aec => aec,
   dma_active => dma_active,

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
   ramDataFloat => ramDinFloat,

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
   colorA10  => colorA10,

   cs_vic => cs_vic,
   cs_sid => cs_sid,
   cs_mmuH => cs_mmuH,
   cs_mmuL => cs_mmuL,
   cs_vdc => cs_vdc,
   cs_io7 => io7_i,
   cs_color => cs_color,
   cs_cia1 => cs_cia1,
   cs_cia2 => cs_cia2,
   cs_ram => cs_ram,
   cs_ioE => ioe_i,
   cs_ioF => iof_i,
   cs_romFL => romFL,
   cs_romFH => romFH,
   cs_romL => romL,
   cs_romH => romH,
   cs_UMAXromH => UMAXromH,
   cs_sysRom => sysRom,
   sysRomBank => sysRomBank
);

IOE <= ioe_i and cs_enable and vicCycle;
IOF <= iof_i and cs_enable and vicCycle;
cs_io <= cs_vic or cs_sid or cs_mmuL or cs_vdc or io7_i or cs_color or cs_cia1 or cs_cia2 or ioe_i or iof_i;
cs_enable <= io_enable and (baLoc or cpuWe);

process(clk32)
begin
	if rising_edge(clk32) then
		pulseWr_io <= '0';
		if cpuWe = '1' then
			if sysCycle = CYCLE_CPU4 then
				pulseWr_io <= '1';
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- VIC-II video interface chip
-- -----------------------------------------------------------------------
vicDi <= ramDin;
vicDiAec <= vicDi when aec = '1' else cpuLastData;
colorDataAec <= colorData when aec = '1' else cpuLastData(3 downto 0);

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
	enaPixel => enablePixel,
   enaData => enableVic,
   phi => phi0_cpu,

   baSync => '0',
   ba => baLoc,
   ba_dma => ba_dma,

	mode6569 => not ntscMode,
	mode6567old => '0',
	mode6567R8 => ntscMode,
	mode6572 => '0',
   variant => vic_variant,
   vic2e => not pure64,

   turbo_en => not pure64,
   turbo_state => turbo_state,

   cs => cs_vic and cs_enable,
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
   vicRefresh => vicRefresh,

   hSync => vicHS,
   vSync => vicVsync,
   colorIndex => vicColorIndex,
   invertV => vicInvertV,

   irq_n => irq_vic
);

vicHsync <= vicHS;

vicColors: entity work.fpga64_rgbcolor
port map (
   index => vicColorIndex,
   invertV => vicInvertV,
   r => vicRo,
   g => vicGo,
   b => vicBo
);

vicJailbarAdjust: video_vicIIe_jb
port map (
   clk => clk32,
   mode => vicJailbars,

   hsync => vicHS,
   Ri => vicRo,
   Gi => vicGo,
   Bi => vicBo,

   Ro => vicR,
   Go => vicG,
   Bo => vicB
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
--
-- The glue logic on a C64C will generate a glitch during 10 <-> 01
-- generating 00 (in other words, bank 3) for one cycle.
--
-- When using the data direction register to change a single bit 0->1
-- (in other words, decreasing the video bank number by 1 or 2),
-- the bank change is delayed by one cycle. This effect is unstable.
process(clk32)
begin
   if rising_edge(clk32) then
      if sysCycle = CYCLE_VIC3 then
			vicAddr1514 <= not cia2_pao(1 downto 0);
      end if;
   end if;
end process;

-- emulate only the first glitch (enough for Undead from Emulamer)
vicAddr(15 downto 14) <= "11" when (pure64 = '1' and (vicAddr1514 xor not cia2_pao(1 downto 0)) = "11") and (cia2_pao(0) /= cia2_pao(1)) else not unsigned(cia2_pao(1 downto 0));

-- Pixel timing
process(clk32)
begin
   if rising_edge(clk32) then
		enablePixel <= '0';
		if sysCycle = CYCLE_VIC2
		or sysCycle = CYCLE_EXT2
		or sysCycle = CYCLE_DMA2
		or sysCycle = CYCLE_EXT6
		or sysCycle = CYCLE_CPU2
		or sysCycle = CYCLE_CPU6
		or sysCycle = CYCLE_CPUA
		or sysCycle = CYCLE_CPUE then
			enablePixel <= '1';
		end if;
   end if;
end process;

-- -----------------------------------------------------------------------
-- VDC 80-col video display controller
-- -----------------------------------------------------------------------

process(clk32)
begin
   if rising_edge(clk32) then
      if sysCycle = CYCLE_CPU0 and cs_enable = '1' then
         enableVdc <= '1';
      end if;

      if enableVdc_sl(0) = '1' then
         enableVdc <= '0';
      end if;
   end if;
end process;

process(clk_vdc)
begin
   if rising_edge(clk_vdc) then
      enableVdc_sl <= enableVdc_sl(0) & enableVdc;
   end if;
end process;

vdc: vdc_top
generic map (
   RAM_ADDR_BITS => VDC_ADDR_BITS
)
port map (
   version => vdcVersion,
   ram64k => vdc64k,
   initRam => vdcInitRam,
   debug => vdcDebug,

   clk => clk_vdc,
   reset => reset,
   init => '0',

   enableBus => enableVdc_sl(0) and not enableVdc_sl(1),
   cs => cs_vdc,
   we => cpuWe,
   rs => tAddr(0),
   db_in => cpuDo,
   db_out => vdcData,

   lp_n => cia1_pbi(4),

   hsync => vdcHsync,
   vsync => vdcVsync,

   rgbi => vdcRGBI
);

vdcColors: entity work.rgbicolor
port map (
   palette => vdcPalette,
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
   cs => (sid_sel_r and cs_enable) & (sid_sel_l and cs_enable),
   addr => tAddr(4 downto 0),
   data_in => cpuDo,
   data_out => sid_do,
   pot_x_l => pot_x1 and pot_x2,
   pot_y_l => pot_y1 and pot_y2,

   audio_l => audio_l,
   audio_r => audio_r,

	ext_in_l(17) => sid_ver(0) and sid_digifix,
	ext_in_l(16 downto 0) => (others => '0'),

	ext_in_r(17) => sid_ver(1) and sid_digifix,
	ext_in_r(16 downto 0) => (others => '0'),

	filter_en => sid_filter,
	mode    => sid_ver,
	cfg     => sid_cfg,

	fc_offset_l => sid_fc_off_l,
	fc_offset_r => sid_fc_off_r,

   ld_clk  => sid_ld_clk,
   ld_addr => sid_ld_addr,
   ld_data => sid_ld_data,
   ld_wr   => sid_ld_wr
);

-- -----------------------------------------------------------------------
-- CIAs
-- -----------------------------------------------------------------------
cia1: mos6526_8520
port map (
   clk => clk32,
   mode => '0' & cia_mode,
   phi2_p => enableCia_p,
   phi2_n => enableCia_n,
   res_n => not reset,
   cs_n => not (cs_cia1 and cs_enable),
   rw => not cpuWe,

   rs => tAddr(3 downto 0),
   db_in => cpuDo,
   db_out => cia1Do,

   pa_in => cia1_pai,
   pa_out => cia1_pao,
   pb_in => cia1_pbi,
   pb_out => cia1_pbo,

   flag_n => cia1_flag_n,
   sp_in => cia1_sp_i,
   sp_out => cia1_sp_o,
   cnt_in => cia1_cnt_i,
   cnt_out => cia1_cnt_o,

   tod => todclk,

   irq_n => irq_cia1
);

cia2: mos6526_8520
port map (
   clk => clk32,
   mode => '0' & cia_mode,
   phi2_p => enableCia_p,
   phi2_n => enableCia_n,
   res_n => not reset,
   cs_n => not (cs_cia2 and cs_enable),
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

fs_o        <= fsdir_n;
fclk_o      <= cia1_cnt_o or not fs_o;
iec_data_o  <= not cia2_pao(5) and (cia1_sp_o or not fs_o);
iec_clk_o   <= not cia2_pao(4);
iec_atn_o   <= not cia2_pao(3);
iec_srq_n_o <= fclk_o;

fs_i        <= not (fsdir_n or mmu_c128_n);
cia1_flag_n <= iec_srq_n_i and fclk_o and cass_read;
cia1_cnt_i  <= (iec_srq_n_i or not fs_i) and cnt1_i;
cia1_sp_i   <= (iec_data_i  or not fs_i) and sp1_i;

cnt1_o <= cia1_cnt_o and cia1_cnt_i;
sp1_o  <= cia1_sp_o  and cia1_sp_i;

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
-- D7xx port
-- -----------------------------------------------------------------------

process(clk32)
begin
   if rising_edge(clk32) then
      d7port_trig <= '0';

      if reset = '1' then
         d7port <= X"00";
      elsif sysCycle = CYCLE_CPU6 then
         if io7_i = '1' and cs_enable = '1' then
            d7port <= cpuDo;
            d7port_trig <= cpuWe;
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
   mode => not pure64,

   clk => clk32,
   reset => reset,
   enable => cpuCycT65,
   nmi_n => irq_cia2 and nmi_n,
   nmi_ack => nmi_ack,
   irq_n => cpuIrq_n,
   rdy => baLoc and not dma_active and cpuActT65,

   di => cpuDi,
   addr => cpuAddr_T65,
   do => cpuDo_T65,
   we => cpuWe_T65,

   IOacc => cpuPacc,
   diIO => cpuPO(7) & cpslk_sense_kb & cpuPO(5) & cass_sense & cpuPO(3) & "111",
   doIO => cpuPO
);

cpslk_sense_cpu <= cpuPO(6) or pure64;
cass_motor <= cpuPO(5);
cass_write <= cpuPO(3);

cpu_z80: entity work.cpu_z80
port map (
   clk => clk32,
   reset => reset_t80,
   enable => cpuCycT80,
   latch => cpuLatT80,
   busrq_n => not pure64 and baLoc and not mmu_z80_n,
   busak_n => cpuBusAk_T80_n,
   irq_n => cpuIrq_n,

   di => cpuDi,
   addr => cpuAddr_T80,
   do => cpuDo_T80,
   we => cpuWe_T80,
   io => cpuIO_T80,
   m1 => cpuM1_T80
);

turbo_std <= not (turbo_mode(1) or turbo_mode(0));

ramDout <= cpuDo;
ramAddr <= systemAddr;
ramWE   <= systemWe;
ramCE   <= cs_ram when
           sysCycle = CYCLE_VIC0 or
           (aec = '1' and sysCycle = CYCLE_CPU4) or
           (cpuactT65 = '1' and t65_cyc = '1') or
           (cpuactT65 = '0' and t80_cyc = '1') else '0';
t65_cyc <= (not t65_cyc_s) when
           (sysCycle = CYCLE_CPU0 and t65_turbo_m(0) = '1' and dma_pending = '0' and cs_ram = '1') or
           (sysCycle = CYCLE_CPU4 and (io_enable = '1' or cs_ram = '1')) or
           (sysCycle = CYCLE_CPU8 and t65_turbo_m(1) = '1' and dma_pending = '0' and cs_ram = '1') or
           (sysCycle = CYCLE_CPUC and t65_turbo_m(2) = '1' and dma_pending = '0' and ((turbo_std = '1' and aec = '0' and vicRefresh = '0') or (turbo_std = '0' and cs_ram = '1'))) else '0';
t80_cyc <= (not t80_cyc_s) when
           (sysCycle = CYCLE_CPU0 and (io_enable = '1' or cs_ram = '1')) or
           (sysCycle = CYCLE_CPU8 and t80_turbo_m = '1' and dma_pending = '0' and cs_ram = '1') else '0';

cpuActT65 <= mmu_z80_n and not cpuBusAk_T80_n;

-- Last data bus activity of the CPU
cpuLastData <= cpuData when cpuCycle = '1' else cpuData_l;
cpuData <= cpuDo when cpuWe = '1' else cpuDi;

process(clk32)
begin
   if rising_edge(clk32) then
      if sysCycle = CYCLE_CPUF then
         cpuData_l <= cpuData;
      end if;
   end if;
end process;

process(clk32)
begin
   if rising_edge(clk32) then
      cpuCycT65 <= '0';
      case sysCycle is
         when CYCLE_CPU0 | CYCLE_CPU4 | CYCLE_CPU8 | CYCLE_CPUC
            => if t65_cyc = '1' then
                  t65_cyc_s <= '1';
               end if;

         when CYCLE_CPU2 | CYCLE_CPU6 | CYCLE_CPUA | CYCLE_CPUE
            => if sysCycle = CYCLE_CPU6 or cs_io = '0' then
                  t65_cyc_s <= '0';
                  cpuCycT65 <= t65_cyc_s;
               end if;

         when CYCLE_CPU3 | CYCLE_CPU7 | CYCLE_CPUB | CYCLE_CPUF
            => if cpuCycT65 = '1' and cpuActT65 = '1' then
                  if turbo_std = '0' then
                     io_enable <= '0';
                  end if;
               end if;

         when others => null;
      end case;

      cpuCycT80 <= '0';
      cpuLatT80 <= '0';
      case sysCycle is
         when CYCLE_CPU0 | CYCLE_CPU8
            => t80_cyc_s <= t80_cyc;
               
         when CYCLE_CPU2 | CYCLE_CPUA
            => if phi0_cpu = '1' or cs_io = '0' then
                  cpuCycT80 <= t80_cyc_s;
               end if;

         when CYCLE_CPU4 | CYCLE_CPUC
            => if phi0_cpu = '1' or cs_io = '0' then
                  cpuCycT80 <= t80_cyc_s;
               end if;

         when CYCLE_CPU6 | CYCLE_CPUE
            => if phi0_cpu = '1' or cs_io = '0' then
                  cpuLatT80 <= t80_cyc_s;
               end if;

         when CYCLE_CPU7 | CYCLE_CPUF
            => if phi0_cpu = '1' or cs_io = '0' then
                  t80_cyc_s <= '0';
                  if t80_cyc_s = '1' then
                     io_enable <= '0';
                  end if;
               end if;

         when others => null;
      end case;

      if sysCycle = CYCLE_CPU7 then
         io_enable <= '1';
      end if;
   end if;
end process;

process(clk32)
begin
   if rising_edge(clk32) then
      case sysCycle is
         when CYCLE_EXT1 | CYCLE_EXT5
            => dma_active <= dma_req;
               dma_pending <= '0';

         when sysCycleDef'pred(CYCLE_CPU0)
            => dma_cycle <= dma_active and (baLoc or ba_dma);

         when CYCLE_CPU7
            => if dma_active = '1' then
                  t65_turbo_m <= turbo_state & "00";
                  t80_turbo_m <= '0';
               else
                  case turbo_mode(1 downto 0) is
                     when "00" => t65_turbo_m <= turbo_state & "00";
                     when "01" => t65_turbo_m <= "100";
                     when "10" => t65_turbo_m <= "110";
                     when "11" => t65_turbo_m <= "111";
                  end case;
                  t80_turbo_m <= turbo_mode(2);
               end if;

         when CYCLE_CPUF
            => dma_cycle <= '0';

         when others => null;
      end case;

      if sysCycle = CYCLE_CPU3 or sysCycle = CYCLE_CPU7 or sysCycle = CYCLE_CPUB or sysCycle = CYCLE_CPUF then
         dma_pending <= dma_req and not dma_active;
      end if;
   end if;
end process;

cpuAddr <= dma_addr    when dma_active = '1' else
           cpuAddr_T65 when mmu_z80_n = '1' else
           cpuAddr_T80 when cpuBusAk_T80_n = '1' else vicAddr;

cpuDo   <= dma_dout    when dma_active = '1' else
           cpuDo_T65   when (mmu_z80_n = '1' and cpuPacc = '0') else
           cpuDo_T80   when cpuBusAk_T80_n = '1' else lastVicDi;

cpuWe   <= dma_we      when dma_active = '1' else
           cpuWe_T65   when mmu_z80_n = '1' else
           cpuWe_T80   when cpuBusAk_T80_n = '1' else '0';

ext_cycle <= '1' when (sysCycle >= CYCLE_DMA0 and sysCycle <= CYCLE_DMA3) else '0';
dma_din   <= cpuDi;

c128_n <= mmu_c128_n;
z80_n <= mmu_z80_n;

exrom_mmu <= mmu_exrom;
game_mmu <= mmu_game;

-- -----------------------------------------------------------------------
-- Keyboard
-- -----------------------------------------------------------------------
cpslk_sense <= cpslk_sense_kb;

Keyboard: entity work.fpga64_keyboard
port map (
   clk => clk32,
   reset => kbd_reset,
   pure64 => pure64,
   c128_n => mmu_c128_n,

   ps2_key => ps2_key,
   go64 => go64,

   joyA => not unsigned(joyA(6 downto 0)),
   joyB => not unsigned(joyB(6 downto 0)),
   pai => cia1_pao,
   pbi => cia1_pbo,
   pao => cia1_pai,
   pbo => cia1_pbi,
   ki => vicKo,

   alt_crsr => not mmu_z80_n,
   shift_mod => shift_mod,
   azerty => azerty,

   restore_key => freeze_key,
   tape_play => tape_play,
   mod_key => mod_key,

   sftlk_sense => sftlk_sense,
   cpslk_sense => cpslk_sense_kb,
   d4080_sense => d4080_sense,
   noscr_sense => noscr_sense,

   backwardsReadingEnabled => '1'
);

end architecture;
