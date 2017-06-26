-------------------------------------------------------------------------------
--| @file vga.vhd
--| @brief      Monochrome Text Mode Video Controller VHDL Module
--| @author     Javier Valcarce Garc�a
--| @copyright  Copyright 2007 Javier Valcarce Garc�a
--| @license    LGPL version 3
--| @email      javier.valcarce@gmail.com
--| @note       (Modifications and repackaging by Richard James Howe)
--|
--| @todo A mode where the cursor follows the text-address automatically
--| would be useful.
-------------------------------------------------------------------------------

----- VGA Package -------------------------------------------------------------
library ieee,work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vga_pkg is
	type vga_physical_interface is record
		red:   std_logic_vector(2 downto 0);
		green: std_logic_vector(2 downto 0);
		blue:  std_logic_vector(1 downto 0);
		hsync: std_logic;
		vsync: std_logic;
	end record;

	type vga_control_registers_we_interface is record
		crx: std_logic; -- Write enable for cursor X position register
		ctl: std_logic; -- Write enable for cursor Y position register
		cry: std_logic; -- Write enable for VGA control register
	end record;

	type vga_control_registers_interface is record
		crx:    std_logic_vector(6 downto 0); -- Cursor position X
		cry:    std_logic_vector(5 downto 0); -- Cursor position Y
		ctl:    std_logic_vector(7 downto 0); -- Control register
	end record;

-- 	type vga_ram_registers is record
-- 		din:     std_logic_vector(15 downto 0);
-- 		addr:    std_logic_vector(12 downto 0);
-- 	end record;
--
-- 	type vga_ram_interface is record
-- 		ram_we:  std_logic; -- Write enable RAM
-- 		addr_we: std_logic; -- Write enable address
-- 		din_we:  std_logic; -- Write enable data
-- 		reg:     vga_ram_registers;
-- 	end record;

	constant vga_control_registers_initialize: vga_control_registers_interface := (
			cry => (others => '0'),
			crx => (others => '0'),
			ctl => (others => '0'));

	constant vga_control_registers_we_initialize: vga_control_registers_we_interface := (
			cry => '0',
			crx => '0',
			ctl => '0');


	component vga_top is
	port(
		clk:         in  std_logic;
		clk25MHz:    in  std_logic;
		rst:         in  std_logic;

		-- VGA Text buffer interface
		vga_we_ram:  in  std_logic; -- Write enable RAM
		vga_addr_we: in  std_logic; -- Write enable address
		vga_din_we:  in  std_logic; -- Write enable data
		vga_din:     in  std_logic_vector(15 downto 0);
		vga_addr:    in  std_logic_vector(12 downto 0);
		vga_dout:    out std_logic_vector(15 downto 0):= (others => '0');

		-- VGA control registers
		i_vga_control_we: in vga_control_registers_we_interface;
		i_vga_control:    in vga_control_registers_interface;

		o_vga:    out vga_physical_interface);
	end component;

	component vga_core is
	port (
		rst:      in  std_logic;
		clk25MHz: in  std_logic;
		text_a:   out std_logic_vector(11 downto 0); -- text buffer
		text_d:   in  std_logic_vector(7 downto 0);
		font_a:   out std_logic_vector(11 downto 0); -- font buffer
		font_d:   in  std_logic_vector(7 downto 0);
		 --
		ocrx:     in  std_logic_vector(6 downto 0);
		ocry:     in  std_logic_vector(5 downto 0);
		octl:     in  std_logic_vector(6 downto 0);
		--
		R:        out std_logic;
		G:        out std_logic;
		B:        out std_logic;
		hsync:    out std_logic;
		vsync:    out std_logic);
	end component;

	component losr is
	generic (N : integer := 4);
	port
	(
		rst:  in  std_logic;
		clk:  in  std_logic;
		load: in  std_logic;
		ce:   in  std_logic;
		do:   out std_logic := '0';
		di:   in  std_logic_vector(N - 1 downto 0));
	end component;

	component ctrm is
		generic (M : integer := 8);
		port (
			rst: in  std_logic; -- asynchronous rst
			clk: in  std_logic;
			ce:  in  std_logic; -- enable counting
			rs:  in  std_logic; -- synchronous rst
			do:  out integer range (M-1) downto 0 := 0
		);
	end component;

end package;

----- VGA Package -------------------------------------------------------------

----- VGA Top Level Component -------------------------------------------------
library ieee,work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity vga_top is
	port(
		clk:              in  std_logic;
		clk25MHz:         in  std_logic;
		rst:              in  std_logic;

		-- VGA Text buffer interface
		vga_we_ram:       in  std_logic; -- Write enable RAM
		vga_addr_we:      in  std_logic; -- Write enable address
		vga_din_we:       in  std_logic; -- Write enable data
		vga_din:          in  std_logic_vector(15 downto 0);
		vga_addr:         in  std_logic_vector(12 downto 0);
		vga_dout:         out std_logic_vector(15 downto 0) := (others => '0');

		-- VGA control registers
		i_vga_control_we: in vga_control_registers_we_interface;
		i_vga_control:    in vga_control_registers_interface;

		o_vga:            out vga_physical_interface);
end;

architecture behav of vga_top is

	-- Setup for text buffer memory
	constant text_addr_length: positive := 13;
	constant text_data_length: positive := 16;
	constant text_file_name:   string   := "text.bin";
	constant text_file_type:   string   := "bin";

	-- Setup for font buffer memory
	constant font_addr_length: positive := 12;
	constant font_data_length: positive := 8;
	constant font_file_name:   string   := "font.bin";
	constant font_file_type:   string   := "bin";

	-- Internal signals for mapping output <--> VGA module
	signal  R_internal:      std_logic := '0';
	signal  G_internal:      std_logic := '0';
	signal  B_internal:      std_logic := '0';

	-- Text RAM signals, RAM <--> VGA module
	signal  text_dout:       std_logic_vector(15 downto 0) := (others => '0');
	signal  text_din:        std_logic_vector(15 downto 0) := (others => '0');
	signal  text_addr:       std_logic_vector(11 downto 0) := (others => '0');
	signal  text_addr_full:  std_logic_vector(12 downto 0) := (others => '0');

	-- Font ROM signals, ROM<-->VGA module
	signal  font_addr:       std_logic_vector(11 downto 0) := (others => '0');
	signal  font_dout:       std_logic_vector( 7 downto 0) := (others => '0');

	signal  control_c, control_n: vga_control_registers_interface := vga_control_registers_initialize;

	-- Internal registers for buffering write operation to RAM memory
	signal  din_c,  din_n:   std_logic_vector(15 downto 0) := (others => '0');
	signal  addr_c, addr_n:  std_logic_vector(12 downto 0) := (others => '0');
begin
	-- Output assignments, syncs elsewhere
	o_vga.red   <=  (others => R_internal);
	o_vga.green <=  (others => G_internal);
	o_vga.blue  <=  (others => B_internal);

	-- Internal control registers
	-- Next state on clk edge rising
	vga_ns: process(clk, rst)
	begin
		if rst = '1' then
			control_c   <= vga_control_registers_initialize;
			din_c       <= (others => '0');
			addr_c      <= (others => '0');
		elsif rising_edge(clk) then
			control_c   <= control_n;
			din_c       <= din_n;
			addr_c      <= addr_n;
		end if;
	end process;

	-- Internal control register
	-- We write into the registers here.
	vga_creg_we: process(
		control_c,
		i_vga_control,
		i_vga_control_we,

		din_c, addr_c,
		vga_addr_we, vga_din,
		vga_din_we, vga_addr)
	begin
		control_n <= control_c;

		din_n  <= din_c;
		addr_n <= addr_c;
		
		if i_vga_control_we.crx = '1' then control_n.crx <= i_vga_control.crx; end if;
		if i_vga_control_we.cry = '1' then control_n.cry <= i_vga_control.cry; end if;
		if i_vga_control_we.ctl = '1' then control_n.ctl <= i_vga_control.ctl; end if;
		if vga_din_we = '1'           then din_n         <= vga_din;           end if;
		if vga_addr_we = '1'          then addr_n        <= vga_addr;          end if;

	end process;

	-- The actual VGA module
	u_vga : work.vga_pkg.vga_core port map (
		rst       => rst,
		clk25MHz  => clk25MHz,

		text_a    => text_addr,
		text_d    => text_dout(7 downto 0),

		font_a    => font_addr,
		font_d    => font_dout,

		ocrx      => control_c.crx,
		ocry      => control_c.cry,
		octl      => control_c.ctl(6 downto 0),

		R         => R_internal,
		G         => G_internal,
		B         => B_internal,
		hsync     => o_vga.hsync,
		vsync     => o_vga.vsync);

	text_addr_full <= control_c.ctl(7) & text_addr;

	--| @brief This RAM module holds the text we want to display on to the
	--| monitor. The text buffer holds at least 80*40 characters.
	u_text: entity work.dual_port_block_ram
	generic map(
	    addr_length   => text_addr_length,
	    data_length   => text_data_length,
	    file_name     => text_file_name,
	    file_type     => text_file_type)
	port map (
		a_clk  => clk,
		-- External interface
		a_dwe  => vga_we_ram,
		a_dre  => '1',
		a_addr => addr_c,
		a_din  => din_c,
		a_dout => vga_dout,
		-- Internal interface
		b_clk  => clk25MHz,
		b_dwe  => '0',
		b_dre  => '1',
		b_addr => text_addr_full,
		b_din  => (others => '0'),
		b_dout => text_dout);

	--| VGA Font memory
	u_font: entity work.single_port_block_ram
	generic map(
		addr_length   => font_addr_length,
		data_length   => font_data_length,
		file_name     => font_file_name,
		file_type     => font_file_type)
	port map (
		clk  => clk25MHz,
		dwe  => '0',
		dre  => '1',
		addr => font_addr,
		din  => (others => '0'),
		dout => font_dout);
	
end architecture;

----- VGA Top Level Component -------------------------------------------------

----- VGA Core ----------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.ctrm;
use work.vga_pkg.losr;


entity vga_core is
	port (
		rst:      in  std_logic;
		clk25MHz: in  std_logic;
		text_a:   out std_logic_vector(11 downto 0); -- text buffer
		text_d:   in  std_logic_vector(7 downto 0);
		font_a:   out std_logic_vector(11 downto 0); -- font buffer
		font_d:   in  std_logic_vector(7 downto 0);
		 --
		ocrx:     in  std_logic_vector(6 downto 0);
		ocry:     in  std_logic_vector(5 downto 0);
		octl:     in  std_logic_vector(6 downto 0);
		--
		R:        out std_logic;
		G:        out std_logic;
		B:        out std_logic;
		hsync:    out std_logic;
		vsync:    out std_logic);
end entity;

architecture rtl of vga_core is

	signal R_int:     std_logic := '0';
	signal G_int:     std_logic := '0';
	signal B_int:     std_logic := '0';
	signal hsync_int: std_logic := '1';
	signal vsync_int: std_logic := '1';
	
	signal blank: std_logic := '0';
	signal hctr:  integer range 793 downto 0 := 0;
	signal vctr:  integer range 524 downto 0 := 0;

	-- character/pixel position on the screen
	signal scry:  integer range 39 downto 0 := 0;  -- chr row   < 40 (6 bits)
	signal scrx:  integer range 79 downto 0 := 0;  -- chr col   < 80 (7 bits)
	signal chry:  integer range 11 downto 0 := 0;  -- chr high  < 12 (4 bits)
	signal chrx:  integer range 7  downto 0 := 0;  -- chr width < 08 (3 bits)
	
	signal losr_ce: std_logic := '0';
	signal losr_ld: std_logic := '0';
	signal losr_do: std_logic := '0';
	signal y:       std_logic := '0';  -- character luminance pixel value (0 or 1)

	-- control io register
	signal ctl:       std_logic_vector(7 downto 0):= (others =>'0');
	signal vga_en:    std_logic := '0';
	signal cur_en:    std_logic := '0';
	signal cur_mode:  std_logic := '0';
	signal cur_blink: std_logic := '0';
	signal ctl_r:     std_logic := '0';
	signal ctl_g:     std_logic := '0';
	signal ctl_b:     std_logic := '0';

begin

	-- hsync generator, initialized with '1'
	process (rst, clk25MHz)
	begin
		if rst = '1' then
			hsync_int <= '1';
		elsif rising_edge(clk25MHz) then
			if (hctr > 663) and (hctr < 757) then
				hsync_int <= '0';
			else
				hsync_int <= '1';
			end if;
		end if;
	end process;


	-- vsync generator, initialized with '1'
	process (rst, clk25MHz)
	begin
		if rst = '1' then
			vsync_int <= '1';
		elsif rising_edge(clk25MHz) then
			if (vctr > 499) and (vctr < 502) then
				vsync_int <= '0';
			else
				vsync_int <= '1';
			end if;
		end if;
	end process;

	-- Blank signal, 0 = no draw, 1 = visible/draw zone

	-- Proboscide99 31/08/08
	blank <= '0' when (hctr < 8) or (hctr > 647) or (vctr > 479) else '1';

	-- flip-flips for sync of R, G y B signal, initialized with '0'
	process (rst, clk25MHz)
	begin
		if rst = '1' then
			R <= '0';
			G <= '0';
			B <= '0';
		elsif rising_edge(clk25MHz) then
			R <= R_int;
			G <= G_int;
			B <= B_int;
		end if;
	end process;

	-- Control register. Individual control signal

	-- @note This has been reorganized from the original
	vga_en    <= octl(6);
	cur_en    <= octl(5);
	cur_blink <= octl(4);
	cur_mode  <= octl(3);
	ctl_r     <= octl(2);
	ctl_g     <= octl(1);
	ctl_b     <= octl(0);

	-- counters, hctr, vctr, srcx, srcy, chrx, chry
	counters: block

		signal hctr_ce: std_logic;
		signal hctr_rs: std_logic;
		signal vctr_ce: std_logic;
		signal vctr_rs: std_logic;

		signal chrx_ce: std_logic;
		signal chrx_rs: std_logic;
		signal chry_ce: std_logic;
		signal chry_rs: std_logic;
		signal scrx_ce: std_logic;
		signal scrx_rs: std_logic;
		signal scry_ce: std_logic;
		signal scry_rs: std_logic;

		signal hctr_639: std_logic;
		signal vctr_479: std_logic;
		signal chrx_007: std_logic;
		signal chry_011: std_logic;

		-- RAM read, ROM read
		signal ram_tmp: integer range 3200 downto 0;  --12 bits
		signal rom_tmp: integer range 3071 downto 0;

	begin
	
		u_hctr: work.vga_pkg.ctrm generic map (M => 794) port map (rst, clk25MHz, hctr_ce, hctr_rs, hctr);
		u_vctr: work.vga_pkg.ctrm generic map (M => 525) port map (rst, clk25MHz, vctr_ce, vctr_rs, vctr);

		hctr_ce <= '1';
		hctr_rs <= '1' when hctr = 793 else '0';
		vctr_ce <= '1' when hctr = 663 else '0';
		vctr_rs <= '1' when vctr = 524 else '0';

		u_chrx: work.vga_pkg.ctrm generic map (M => 8)  port map (rst, clk25MHz, chrx_ce, chrx_rs, chrx);
		u_chry: work.vga_pkg.ctrm generic map (M => 12) port map (rst, clk25MHz, chry_ce, chry_rs, chry);
		u_scrx: work.vga_pkg.ctrm generic map (M => 80) port map (rst, clk25MHz, scrx_ce, scrx_rs, scrx);
		u_scry: work.vga_pkg.ctrm generic map (M => 40) port map (rst, clk25MHz, scry_ce, scry_rs, scry);

		hctr_639 <= '1' when hctr = 639 else '0';
		vctr_479 <= '1' when vctr = 479 else '0';
		chrx_007 <= '1' when chrx = 7 else '0';
		chry_011 <= '1' when chry = 11 else '0';

		chrx_rs <= chrx_007 or hctr_639;
		chry_rs <= chry_011 or vctr_479;
		scrx_rs <= hctr_639;
		scry_rs <= vctr_479;

		chrx_ce <= '1' and blank;
		scrx_ce <= chrx_007;
		chry_ce <= hctr_639 and blank;
		scry_ce <= chry_011 and hctr_639;

		ram_tmp <=  to_integer(to_unsigned(scry,12) sll 4) +
				to_integer(to_unsigned(scry,12) sll 6) +
				scrx;

		text_a <= std_logic_vector(to_unsigned(ram_tmp, 12));

		rom_tmp <= to_integer(unsigned(text_d)) * 12 + chry;

		font_a <= std_logic_vector(to_unsigned(rom_tmp, 12));

	end block;

	u_losr: work.vga_pkg.losr generic map (N => 8)
	port map (rst, clk25MHz, losr_ld, losr_ce, losr_do, FONT_D);

	losr_ce <= blank;
	losr_ld <= '1' when (chrx = 7) else '0';

	-- video out, vga_en control signal enable/disable vga signal
	R_int <= (ctl_r and y) and blank;
	G_int <= (ctl_g and y) and blank;
	B_int <= (ctl_b and y) and blank;

	hsync <= hsync_int and vga_en;
	vsync <= vsync_int and vga_en;
	
	-- Hardware Cursor
	hw_cursor: block
		signal small:   std_logic;
		signal curen2:  std_logic;
		signal slowclk: std_logic;
		signal curpos:  std_logic;
		signal yint:    std_logic;
		signal crx_tmp: integer range 79 downto 0;
		signal cry_tmp: integer range 39 downto 0;
		signal crx:     integer range 79 downto 0;
		signal cry:     integer range 39 downto 0;
		signal counter: unsigned(22 downto 0);
	begin

		-- slowclk for blink hardware cursor
		counter <= counter + 1 when rising_edge(clk25MHz);
		slowclk <= counter(22); --2.98Hz

		crx <= to_integer(unsigned(ocrx(6 downto 0)));
		cry <= to_integer(unsigned(ocry(5 downto 0)));

		--
		curpos <= '1' when (scry = cry) and (scrx = crx) else '0';
		small  <= '1' when (chry > 8)                    else '0';
		curen2 <= (slowclk or (not cur_blink)) and cur_en;
		yint   <= '1' when cur_mode = '0'                else small;
		y      <= (yint and curpos and curen2) xor losr_do;
		
	end block;
	
end;
----- VGA Core ----------------------------------------------------------------

-------------------------------------------------------------------------------
--| @file ctrm.vhd
--| @brief Counter, asynchronous *and* synchronous reset, up only.
--|        (ctrm.vhd, original filename)
--| @author         Javier Valcarce García
--| @copyright      Copyright 2007 Javier Valcarce García
--| @license        LGPL version 3
--| @email          javier.valcarce@gmail.com
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ctrm is
	generic (M : integer := 8);
	port (
		rst: in  std_logic; -- asynchronous rst
		clk: in  std_logic;
		ce:  in  std_logic; -- enable counting
		rs:  in  std_logic; -- synchronous rst
		do:  out integer range (M-1) downto 0 := 0
	);
end ctrm;

architecture rtl of ctrm is
	signal c : integer range (M-1) downto 0:= 0;
begin
	do <= c;
	process(rst, clk)
	begin
		if rst = '1' then
			c <= 0;
		elsif rising_edge(clk) then
			if ce = '1' then
				if rs = '1' then
					c <= 0;
				else
					c <= c + 1;
				end if;
			end if;
		end if;
	end process;
end;

-------------------------------------------------------------------------------
--| @file util.vhd
--| @brief Shift register N-bit, asynchronous reset, synchronous load,
--|        and enable
--| @author         Javier Valcarce García
--| @copyright      Copyright 2007 Javier Valcarce García
--| @license        LGPL version 3
--| @email          javier.valcarce@gmail.com
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity losr is
	generic (N : integer := 4);
	port
	(
		rst:  in  std_logic;
		clk:  in  std_logic;
		load: in  std_logic;
		ce:   in  std_logic;
		do:   out std_logic := '0';
		di:   in  std_logic_vector(N - 1 downto 0));
end losr;

architecture rtl of losr is
begin

	process(rst, clk)
		variable data : std_logic_vector(N - 1 downto 0) := (others => '0');
	begin
		if rst = '1' then
			data := (others => '0');
		elsif rising_edge(clk) then
			if load = '1' then
				data := di;
			elsif ce = '1' then
				data := data(N-2 downto 0) & "0";
			end if;
		end if;

		do <= data(N-1);
	end process;
end;

