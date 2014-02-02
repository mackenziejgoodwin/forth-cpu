--------------------------------------------------------------------------------- 
--! @file ps2.vhd
--! @brief ps2.vhd, implements a not-fully-compliant PS/2
--!  keyboard driver
--! @author     Richard James Howe.
--! @copyright  Copyright 2013 Richard James Howe.
--! @license    LGPL    
--! @email      howe.r.j.89@gmail.com
--------------------------------------------------------------------------------- 

library ieee,work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2 is
  port
  (
    clk:      in  std_logic := '0';  -- clock
    rst:      in  std_logic := '0';  -- reset pin

    ps2_clk:  in  std_logic := '0';  -- PS/2 Keyboard Clock
    ps2_data: in  std_logic := '0';  -- PS/2 Keyboard Data
    ack_in:   in  std_logic := '0';  -- external component signals data read

    stb_out:  out std_logic := '0';  -- recieved data, waiting to be read
    scanCode: out std_logic_vector(7 downto 0); -- actual data we want
    scanError:out std_logic := '0'   -- an error has occured, woops.
  );
end entity;

architecture rtl of ps2 is
begin

end architecture;