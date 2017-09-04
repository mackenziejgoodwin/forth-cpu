-------------------------------------------------------------------------------
--| @file tb.vhd
--| @brief Main test bench.
--|
--| @author         Richard James Howe.
--| @copyright      Copyright 2013,2017 Richard James Howe.
--| @license        MIT
--| @email          howe.r.j.89@gmail.com
--|
--| This test bench does quite a lot. It is not like normal VHDL test benches
--| in the fact that it uses configurable variables that it read in from a
--| file, which it does in an awkward but usable fashion.
--|
--| It also tests multiple modules.
--|
--| @todo Optionally, read in from standard input and send the character
--| over the UART, then print out any received characters to standard out.
-------------------------------------------------------------------------------

library ieee,work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use work.util.all;
use work.core_pkg.all;
use work.vga_pkg.all;
use work.uart_pkg.uart_core;

entity tb is
end tb;

architecture testing of tb is
	constant clock_frequency:         positive := 100_000_000;
	constant number_of_interrupts:    positive := 8;
	constant uart_baud_rate:          positive := 115200;
	constant configuration_file_name: string   := "tb.cfg";
	constant clk_period:              time     := 1000 ms / clock_frequency;
	constant uart_tx_time:            time     := (10*1000 ms) / 115200;

	-- Test bench configurable options --

	type configurable_items is record
		number_of_iterations: positive;
		verbose:              boolean;
		report_number:        natural;
		interactive:          boolean;
	end record;

	function set_configuration_items(ci: configuration_items) return configurable_items is
		variable r: configurable_items;
	begin
		r.number_of_iterations := ci(0).value;
		r.verbose              := ci(1).value > 0;
		r.interactive          := ci(2).value > 0;
		r.report_number        := ci(3).value;
		return r;
	end function;

	constant configuration_default: configuration_items(0 to 3) := (
		(name => "Cycles  ", value => 1000),
		(name => "Verbose ", value => 1),
		(name => "Interact", value => 0),
		(name => "LogFor  ", value => 256));

	-- Test bench configurable options --

	signal stop:  std_logic :=  '0';
	signal debug: cpu_debug_interface;

	signal clk:   std_logic := '0';
	signal rst:   std_logic := '0';

--	signal  cpu_wait: std_logic := '0'; -- CPU wait flag

	-- Basic I/O
	signal btnu:  std_logic := '0';  -- button up
	signal btnd:  std_logic := '0';  -- button down
	signal btnc:  std_logic := '0';  -- button centre
	signal btnl:  std_logic := '0';  -- button left
	signal btnr:  std_logic := '0';  -- button right
	signal sw:    std_logic_vector(7 downto 0) := (others => '0'); -- switches
	signal an:    std_logic_vector(3 downto 0) := (others => '0'); -- anodes   8 segment display
	signal ka:    std_logic_vector(7 downto 0) := (others => '0'); -- kathodes 8 segment display
	signal ld:    std_logic_vector(7 downto 0) := (others => '0'); -- leds

	-- VGA
	signal o_vga: vga_physical_interface;
	signal hsync_gone_high: boolean := false;
	signal vsync_gone_high: boolean := false;

	-- HID
	signal ps2_keyboard_data: std_logic := '0';
	signal ps2_keyboard_clk:  std_logic := '0';

	-- UART
	signal rx:                 std_logic := '0';
	signal tx:                 std_logic := '0';
	signal dout_ack, dout_stb: std_logic := '0';
	signal din_ack, din_stb:   std_logic := '0';
	signal dout:               std_logic_vector(7 downto 0) := (others => '0');
	signal din:                std_logic_vector(7 downto 0) := (others => '0');

	-- Wave form generator
	signal gen_dout:     std_logic_vector(15 downto 0) := (others => '0');

	shared variable cfg: configurable_items := set_configuration_items(configuration_default);

	signal configured: boolean := false;

	signal RamCS:     std_logic := 'X';
	signal MemOE:     std_logic := 'X'; -- negative logic
	signal MemWR:     std_logic := 'X'; -- negative logic
	signal MemAdv:    std_logic := 'X'; -- negative logic
	signal MemWait:   std_logic := 'X'; -- positive!
	signal FlashCS:   std_logic := 'X';
	signal FlashRp:   std_logic := 'X';
	signal MemAdr:    std_logic_vector(26 downto 1) := (others => 'X');
	signal MemDB:     std_logic_vector(15 downto 0) := (others => 'X');

begin
---- Units under test ----------------------------------------------------------

	MemDB <= (others => '0') when MemOE = '1' else (others => 'Z');

	uut: entity work.top
	generic map(
		clock_frequency      => clock_frequency,
		uart_baud_rate       => uart_baud_rate)
	port map(
		debug       => debug,
		clk         => clk,
		-- rst      => rst,
		btnu        => btnu,
		btnd        => btnd,
		btnc        => btnc,
		btnl        => btnl,
		btnr        => btnr,
		sw          => sw,
		an          => an,
		ka          => ka,
		ld          => ld,
		rx          => rx,
		tx          => tx,
		o_vga       => o_vga,

		ps2_keyboard_data => ps2_keyboard_data,
		ps2_keyboard_clk  => ps2_keyboard_clk,

		RamCS    =>  RamCS,
		MemOE    =>  MemOE,
		MemWR    =>  MemWR,
		MemAdv   =>  MemAdv,
		MemWait  =>  MemWait,
		FlashCS  =>  FlashCS,
		FlashRp  =>  FlashRp,
		MemAdr   =>  MemAdr,
		MemDB    =>  MemDB);

	uut_util: work.util.util_tb generic map(clock_frequency => clock_frequency);

	-- The "io_pins_tb" works correctly, however GHDL 0.29, compiled under
	-- Windows, cannot fails to simulate this component correctly, and it
	-- crashes. This does not affect the Linux build of GHDL. It has
	-- something to do with 'Z' values for std_logic types.
	--

	uut_io_pins: work.util.io_pins_tb      generic map(clock_frequency => clock_frequency);

	uut_uart: work.uart_pkg.uart_core
		generic map(
			baud_rate            =>  uart_baud_rate,
			clock_frequency      =>  clock_frequency)
		port map(
			clk       =>  clk,
			rst       =>  rst,
			din       =>  din,
			din_stb   =>  din_stb,
			din_ack   =>  din_ack,
			tx        =>  rx,
			rx        =>  tx,
			dout_ack  =>  dout_ack,
			dout_stb  =>  dout_stb,
			dout      =>  dout);

------ Simulation only processes ----------------------------------------------
	clk_process: process
	begin
		while stop = '0' loop
			clk <= '1';
			wait for clk_period / 2;
			clk <= '0';
			wait for clk_period / 2;
		end loop;
		wait;
	end process;

	output_process: process
		variable oline: line;
		variable c: character;
		variable have_char: boolean := true;
	begin
		wait until configured;

		if not cfg.interactive then
			wait;
		end if;

		report "WRITING TO STDOUT";
		while stop = '0' loop
			wait until (dout_stb = '1' or stop = '1');
			if stop = '0' then
				c := character'val(to_integer(unsigned(dout)));
				write(oline, c);
				have_char := true;
				if dout = x"0d" then
					writeline(output, oline);
					have_char := false;
				end if;
				wait for clk_period;
				dout_ack <= '1';
				wait for clk_period;
				dout_ack <= '0';
			end if;
		end loop;
		if have_char then
			writeline(output, oline);
		end if;
		wait;
	end process;


	-- @note The Input and Output mechanism that allows the tester to
	-- interact with the running simulation needs more work, it is buggy
	-- and experimental, but demonstrates the principle - that a VHDL
	-- test bench can be interacted with at run time.
	input_process: process
		variable c: character := ' ';
		variable iline: line;
		-- variable oline: line;
		variable good: boolean := true;
	begin
		din_stb <= '0';
		din     <= x"00";
		wait until configured;
		if not cfg.interactive then
			din_stb <= '1';
			din     <= x"AA";
			wait;
		end if;

		report "READING FROM STDIN";
		while (not endfile(input)) and stop = '0' loop
			readline(input, iline);
			good := true;
			while good and stop = '0' loop
				read(iline, c, good);
				if good then
					report "" & c;
				end if;
				din <=
				std_logic_vector(to_unsigned(character'pos(c), din'length));
				din_stb <= '1';
				wait for clk_period;
				din_stb <= '0';
				assert din_ack = '1' severity warning;
				-- wait for 100 us;
				wait for 10 ms;
			end loop;
		end loop;
		-- stop <= '1';
		wait;
	end process;

	hsync_gone_high <= true when o_vga.hsync = '1' else hsync_gone_high;
	vsync_gone_high <= true when o_vga.vsync = '1' else vsync_gone_high;

	-- I/O settings go here.
	stimulus_process: process
		variable w: line;
		variable count: integer := 0;

		function stringify(slv: std_logic_vector) return string is
		begin
			return integer'image(to_integer(unsigned(slv)));
		end stringify;

		procedure element(l: inout line; we: boolean; name: string; slv: std_logic_vector) is
		begin
			if we then
				write(l, name & "(" & stringify(slv) & ") ");
			end if;
		end procedure;

		procedure element(l: inout line; name: string; slv: std_logic_vector) is
		begin
			element(l, true, name, slv);
		end procedure;

		function reportln(debug: cpu_debug_interface; cycles: integer) return line is
			variable l: line;
		begin
			write(l, integer'image(cycles) & ": ");
			element(l, "pc",    debug.pc);
			element(l, "insn",  debug.insn);
			element(l, "daddr", debug.daddr);
			element(l, "dout",  debug.dout);
			return l;
		end function;

		variable configuration_values: configuration_items(configuration_default'range) := configuration_default;
	begin
		-- write_configuration_tb(configuration_file_name, configuration_default);
		read_configuration_tb(configuration_file_name, configuration_values);
		cfg := set_configuration_items(configuration_values);
		configured <= true;

		rst  <= '1';
		wait for clk_period * 2;
		rst  <= '0';
		for i in 0 to cfg.number_of_iterations loop
			if cfg.verbose then
				if count < cfg.report_number then
					w := reportln(debug, count);
					writeline(OUTPUT, w);
					count := count + 1;
				elsif count < cfg.report_number + 1 then
					report "Simulation continuing: Reporting turned off";
					count := count + 1;
				end if;
			end if;
			wait for clk_period * 1;
		end loop;

		-- It would be nice to test the other peripherals as
		-- well, the CPU-ID should be written to the LED 7 Segment
		-- displays, however we only get the cathode and anode
		-- values out of the unit.

		assert hsync_gone_high report "HSYNC not active - H2 failed to initialize VGA module";
		assert vsync_gone_high report "VSYNC not active - H2 failed to initialize VGA module";

		stop   <=  '1';
		wait;
	end process;

end architecture;
------ END ---------------------------------------------------------------------

