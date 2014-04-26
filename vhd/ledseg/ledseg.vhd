--------------------------------------------------------------------------------
--! @file ledseg.vhd
--! @brief controls a number of led displays, 8 segment LEDs, there
--! is no enable, just write 0 to the displays to turn them off.
--!
--! @author     Richard James Howe.
--! @copyright  Copyright 2013 Richard James Howe.
--! @license    LGPL    
--! @email      howe.r.j.89@gmail.com
--------------------------------------------------------------------------------

library ieee,work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ledseg is
  generic(
    number_of_segments: positive := 4;        -- not used at the moment
    clk_freq:           positive := 100000000 -- --""--
  );
  port(
    clk:        in   std_logic;
    rst:        in   std_logic;

    -- 16 bit CPU interface; the data
    led_0_1:    in   std_logic_vector(15 downto 0); -- leds 0 and 1
    led_2_3:    in   std_logic_vector(15 downto 0); -- leds 2 and 3

    -- Write enable
    led_0_1_we: in   std_logic;
    led_2_3_we: in   std_logic;

    -- Physical outputs
    an:         out  std_logic_vector(3 downto 0); -- anodes, controls on/off
    ka:         out  std_logic_vector(7 downto 0) -- cathodes, data on display
  );
end;

architecture behav of ledseg is
  constant highest_counter_bit: integer := 21;
  signal led_0_1_c, led_0_1_n: std_logic_vector(15 downto 0):= (others => '0');
  signal led_2_3_c, led_2_3_n: std_logic_vector(15 downto 0):= (others => '0');

  signal ka_c, ka_n: std_logic_vector(7 downto 0);

  signal counter:    unsigned(highest_counter_bit downto 0);
  signal counter_hb: std_logic;
  signal shift_reg:  std_logic_vector(3 downto 0) := (0 => '1', others => '0');
begin
  counter_hb <= counter(highest_counter_bit);
  an <= shift_reg;

  process(clk,rst)
  begin
    if rst = '1' then
      led_0_1_c <= (others => '0');    
      led_2_3_c <= (others => '0');    
      ka_c      <= (others => '0');
      counter   <= (others => '0');
    elsif rising_edge(clk) then
      led_0_1_c <= led_0_1_n;
      led_2_3_c <= led_2_3_n;
      ka_c      <= ka_n;
      counter   <= counter + 1;
    end if;
  end process;

  process(counter_hb)
  begin
    if rising_edge(counter_hb) then
      shift_reg <= shift_reg(2 downto 0) & shift_reg(3);
    else
      shift_reg <= shift_reg;
    end if;
  end process;

  process(
    led_0_1_c, led_0_1_we, led_0_1,
    led_2_3_c, led_2_3_we, led_2_3,
    ka_c
  )
  begin
    led_0_1_n <= led_0_1_c;
    led_2_3_n <= led_2_3_c;
    ka_n <= ka_n;

    if '1' = led_0_1_we then
      led_0_1_n <= led_0_1;
    end if;  

    if '1' = led_2_3_we then
      led_2_3_n <= led_2_3;
    end if;
  end process;

end architecture;