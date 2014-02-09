-------------------------------------------------------------------------------
--! @file h2.vhd
--! @brief The H2 Processor:
--! J1 processor translation and extension. Moved bit 12 to bit 4 to
--!  allow for more ALU instructions, added more ALU instructions and
--!  changed a few things around.
--! @author         Richard James Howe.
--! @copyright      Copyright 2013 Richard James Howe.
--! @license        LGPL      
--! @email          howe.r.j.89@gmail.com
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--! TODO:
--!  * Interrupt handling needs to be improved, ie - simultaneous interrupts
--!  * Carry Flag: Test it and move around instructions.
--!  * Rotate through carry?
--!  * Make CPU more generic:
--!    - instead of (15 downto 0) have (15_bit downto 0_bit)
--!      where 15_bit and 0_bit are constants that can be moved
--!      up and down relative to each other.
-------------------------------------------------------------------------------

library ieee,work,std;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;

entity h2 is
    generic(
        number_of_interrupts: positive := 4
    );
    port(
        clk:        in  std_logic;
        rst:        in  std_logic;
        -- IO interface
        io_wr:      out std_logic;
        io_re:      out std_logic;
        io_din:     in  std_logic_vector(15 downto 0);
        io_dout:    out std_logic_vector(15 downto 0);
        io_daddr:   out std_logic_vector(15 downto 0);
        -- Interrupts
        irq:        in  std_logic;
        irc:        in  std_logic_vector(number_of_interrupts - 1 downto 0);

        -- RAM interface, Dual port
        pco:        out std_logic_vector(12 downto 0);
        insn:       in  std_logic_vector(15 downto 0);

        dwe:        out std_logic; -- data write enable, read enable not need.
        din:        in  std_logic_vector(15 downto 0);
        dout:       out std_logic_vector(15 downto 0);
        daddr:      out std_logic_vector(12 downto 0);

        -- Data pointer
        dptr:       out std_logic_vector(15 downto 0)
    );
end;

architecture behav of h2 is

    -- Program counter.
    signal pc_c:                std_logic_vector(12 downto 0) := (others => '0');
    signal pc_n:                std_logic_vector(12 downto 0) := (others => '0');
    -- Stack Type!
    type   stk  is array (31 downto 0) of std_logic_vector(15 downto 0);
    -- Variable stack (RAM Template)
    signal vstkp_c:             std_logic_vector(4 downto 0)  := (others => '0');
    signal vstkp_n:             std_logic_vector(4 downto 0)  := (others => '0');
    signal vstk_ram:            stk := (others => (others => '0'));
    -- Return stack (RAM Template)
    signal rstkp_c:             std_logic_vector(4 downto 0)  := (others => '0');
    signal rstkp_n:             std_logic_vector(4 downto 0)  := (others => '0');
    signal rstk_ram:            stk := (others => (others => '0'));
    -- Stack deltas
    signal dd:                  std_logic_vector(4 downto 0)  := (others => '0');
    signal rd:                  std_logic_vector(4 downto 0)  := (others => '0');
    -- is_instr_x signals, booleans, does the instruction have a certain property.
    signal is_instr_alu:        std_logic                     :=  '0';
    signal is_instr_lit:        std_logic                     :=  '0';
    signal is_instr_jmp:        std_logic                     :=  '0';
    signal is_instr_cjmp:       std_logic                     :=  '0';
    signal is_instr_call:       std_logic                     :=  '0';
    signal is_instr_interrupt:  std_logic                     :=  '0';

    -- Comparisions on stack items
    signal comp_more_signed:    std_logic                     :=  '0';
    signal comp_more:           std_logic                     :=  '0';
    signal comp_equal:          std_logic                     :=  '0';
    signal comp_negative:       std_logic                     :=  '0';
    signal comp_zero:           std_logic                     :=  '0';

    -- Interrupt enable register (for when interrupts are implemented)
    signal int_en_c, int_en_n:  std_logic                     :=  '0';
    signal irq_c, irq_n:        std_logic                     :=  '0';
    signal irc_c, irc_n:        std_logic_vector(3 downto 0)  :=  (others => '0');

    -- Top of stack, and next on stack.
    signal tos_c:               std_logic_vector(16 downto 0) := (others => '0');
    signal tos_n:               std_logic_vector(16 downto 0) := (others => '0');
    signal nos:                 std_logic_vector(15 downto 0) := (others => '0');
    -- Top of return stack.
    signal rtos_c:              std_logic_vector(15 downto 0) := (others => '0');
    -- aluop is what is fed into the alu.
    signal aluop:               std_logic_vector(4 downto 0)  := (others => '0');
    -- pc_plus_1, forces fewer adders.
    signal pc_plus_one:         std_logic_vector(12 downto 0) := (others => '0');
    -- Stack signals
    signal dstkW:               std_logic                     := '0';
    signal rstkD:               std_logic_vector(15 downto 0) := (others => '0');
    signal rstkW:               std_logic                     := '0';
    -- data pointer
    signal dptr_c:              std_logic_vector(15 downto 0) := (others => '0');
    signal dptr_n:              std_logic_vector(15 downto 0) := (others => '0');
begin

    -- is_instr_x, what kind of instruction do we have?
    is_instr_alu        <=  '1' when insn(15 downto 13) = "011" else '0';
    is_instr_lit        <=  '1' when insn(15) = '1' else '0';
    is_instr_jmp        <=  '1' when insn(15 downto 13) = "000" else '0';
    is_instr_cjmp       <=  '1' when insn(15 downto 13) = "001" else '0';
    is_instr_call       <=  '1' when insn(15 downto 13) = "010" else '0';
    is_instr_interrupt  <=  '1' when irq_c = '1' else '0';

    irq_n <= '1' when irq = '1' else '0';
    irc_n <= irc when irq = '1' else (others => '0');

    comp_more_signed    <= '1' when signed(tos_c(15 downto 0)) > signed(nos) 
                           else '0';
    comp_more           <= '1' when tos_c(15 downto 0) > nos else '0';
    comp_equal          <= '1' when tos_c(15 downto 0) = nos else '0';
    comp_negative       <= tos_c(15);
    comp_zero           <= '1' when unsigned(tos_c(15 downto 0)) = 0 else '0';

    -- Stack assignments
    nos                 <=  vstk_ram(to_integer(unsigned(vstkp_c)));
    rtos_c              <=  rstk_ram(to_integer(unsigned(rstkp_c)));

    -- I/O assignments
    pco                 <=  pc_n;
    dout                <=  nos;
    daddr               <=  tos_c(12 downto 0);
    dwe                 <=  insn(5) when is_instr_alu = '1' 
                            and tos_c(14 downto 13) /= "11" else '0';


    -- io_wr are handled in the ALU, 
    --  this makes things slower but we have
    --  run out of instruction bits to use.
    io_dout             <=  nos;
    io_daddr            <=  tos_c(15 downto 0);
    io_wr               <=  insn(5) when is_instr_alu = '1' 
                            and tos_c(14 downto 13) = "11" else '0';

    -- misc
    pc_plus_one         <=  std_logic_vector(unsigned(pc_c) + 1);

    -- Signed addition!
    dd                  <=  insn(1) & insn(1) & insn(1) & insn(1) & insn(0);
    rd                  <=  insn(3) & insn(3) & insn(3) & insn(3) & insn(2);

    dstkW               <= '1' when is_instr_lit = '1' 
                           or (is_instr_alu = '1' 
                           and insn(7) = '1') 
                        else '0';

    dptr                <= dptr_c;

    stackWrite: process(
        clk
    )
    begin        
        if rising_edge(clk) then
            if dstkW = '1' then
                    vstk_ram(to_integer(unsigned(vstkp_n))) <=  tos_c(15 downto 0);
            end if;

            if rstkW = '1' then
                    rstk_ram(to_integer(unsigned(rstkp_n))) <=  rstkD;
            end if;
        end if;
    end process;

    alu_sel: process(
        insn,
        is_instr_interrupt,
        int_en_c
    )
    begin
      if is_instr_interrupt = '1' and int_en_c = '1' then -- same as call or ubranch
        aluop <= (others => '0');
      else
        case insn(14 downto 13) is
            when "00" => aluop <= (others => '0');            -- ubranch
            when "01" => aluop <= (others => '0');            -- call
            when "10" => aluop <= (0 => '1', others => '0');  -- 0branch
            when "11" => aluop <= insn(12 downto 8);          -- alu operation.
            when others => aluop <= "XXXXX";
        end case;
      end if;
    end process;

    -- ALU
    alu: process(
        is_instr_lit, 
        tos_c, nos, rtos_c, 
        din, insn, aluop, 
        io_din,
        vstkp_c, rstkp_c,
        comp_more,comp_more_signed,
        comp_equal,comp_negative,comp_zero,
        dptr_c,
        int_en_c
    )
    begin
        io_re          <=  '0'; -- hardware *READS* can have side effects
        tos_n          <=  tos_c;
        int_en_n       <=  int_en_c;
        dptr_n         <=  dptr_c;
        if is_instr_lit = '1' then
            tos_n   <=  "00" & insn(14 downto 0);
        else 
            case aluop is -- ALU operation, 12 downto 8
                when "00000" =>  tos_n  <=  tos_c;
                when "00001" =>  tos_n  <=  tos_c(16) & nos;
                when "00010" =>  tos_n  <=  tos_c(16) & rtos_c;
                when "00011" =>  
                  -- 0x6000 - 0x7FFF is external input
                  if tos_c(14 downto 13) = "11" then 
                    tos_n <= "0" & io_din; 
                    io_re <= '1';
                  else 
                    tos_n <= "0" & din;  
                  end if;
                when "00100" =>  tos_n  <=  tos_c(16) & vstkp_c & "000000" & rstkp_c;
                when "00101" =>  tos_n  <=  "0" & (tos_c(15 downto 0) or nos);
                when "00110" =>  tos_n  <=  "0" & (tos_c(15 downto 0) and nos);
                when "00111" =>  tos_n  <=  "0" & (tos_c(15 downto 0) xor nos);
                when "01000" =>  tos_n  <=  "0" & (tos_c(15 downto 0) xnor nos);
                when "01001" =>  tos_n  <=  not tos_c;
                when "01010" =>  tos_n  <=  std_logic_vector(unsigned(tos_c)+unsigned(nos));
                when "01011" =>  tos_n  <=  std_logic_vector(unsigned(nos)-unsigned(tos_c));
                when "01100" =>
                    tos_n   <=  "0" & std_logic_vector(unsigned(nos) sll to_integer(unsigned(tos_c(3 downto 0))));
                when "01101" =>  
                    tos_n   <=  "0" & std_logic_vector(unsigned(nos) srl to_integer(unsigned(tos_c(3 downto 0))));
                when "01110" => 
                    tos_n   <=  "0" & std_logic_vector(unsigned(nos) rol to_integer(unsigned(tos_c(3 downto 0))));
                when "01111" =>
                    tos_n   <=  "0" & std_logic_vector(unsigned(nos) ror to_integer(unsigned(tos_c(3 downto 0))));
                when "10000" => 
                -- SLOW Instructions: These (This) instruction(s) (are/is) slow to execute so (it has / have) been commented out ---
                --  tos_n   <=  "0" & std_logic_vector(unsigned(nos(7 downto 0)) * to_integer(unsigned(tos_c(7 downto 0))));
                -- SLOW Instructions ---
                when "10001" => tos_n  <=  (0 => comp_more_signed, others => '0');
                when "10010" => tos_n  <=  (0 => comp_more, others => '0');
                when "10011" => tos_n  <=  (0 => comp_equal, others => '0');
                when "10100" => tos_n  <=  (0 => comp_negative, others => '0');
                when "10101" => tos_n  <=  (0 => comp_zero, others => '0');
                when "10110" => tos_n  <=  
                  tos_c(16) & tos_c(7 downto 0) & tos_c(15 downto 8);
                when "10111" => int_en_n <= int_en_c xor '1'; -- toggle interrupts
                when "11000" => tos_n  <=  std_logic_vector(unsigned(tos_c)-1); 
                when "11001" => tos_n  <=  (others => '0'); -- clear all
                when "11010" => tos_n(16) <= tos_c(0); -- carry flag, set
                when "11011" => 
                   tos_n(7 downto 0) <= "0" & tos_c(16) & int_en_c 
                   & comp_more_signed & comp_more & comp_equal & 
                   comp_negative & comp_zero; -- depth of stacks 

                   tos_n(15 downto 8) <= (others => '0');
                   tos_n(16) <= tos_c(16);
                when "11100" => dptr_n <= tos_c(15 downto 0);
                when "11101" => 
                when "11110" => 
                when "11111" => -- set depth
                when others => tos_n    <=  (others => 'X');
            end case;
        end if;
    end process;

    -- Reset and state-machine clock.
    nextState: process(clk,rst)
    begin
        if rst='1' then
            vstkp_c     <=  (others => '0');
            rstkp_c     <=  (others => '0');
            pc_c        <=  (others => '0');
            tos_c       <=  (others => '0');
            int_en_c    <=  '0';
            irq_c       <=  '0';
            irc_c       <=  (others => '0');
        elsif rising_edge(clk) then
            vstkp_c     <=  vstkp_n;
            rstkp_c     <=  rstkp_n;
            pc_c        <=  pc_n;
            tos_c       <=  tos_n;
            int_en_c    <=  int_en_n;
            irq_c       <=  irq_n;
            irc_c       <=  irc_n;
        end if;
    end process;

    stackUpdate: process(
            pc_c, 
            insn,
            vstkp_c, vstk_ram, dd,
            rstkp_c, rstk_ram, rd,
            tos_c,
            is_instr_jmp, is_instr_cjmp, is_instr_call, is_instr_lit, is_instr_alu,
            is_instr_interrupt, int_en_c,
            pc_plus_one
        )
    begin
        vstkp_n   <=  vstkp_c;
        rstkp_n   <=  rstkp_c;

        -- main control
        if is_instr_interrupt = '1' and int_en_c = '1' then -- Interrupts are similar to a call
            rstkp_n <=  std_logic_vector(unsigned(rstkp_c) + 1);
            rstkW   <=  '1';
            rstkD   <=  "000" & pc_c; 
        elsif is_instr_lit = '1' then
            vstkp_n <=  std_logic_vector(unsigned(vstkp_c)+1);
            rstkW   <=  '0';
            rstkD   <=  "000" & pc_plus_one; 
        elsif is_instr_alu = '1' then 
            rstkW   <=  insn(6);
            rstkD   <=  tos_c(15 downto 0);
            -- Signed addition, trust me, it's signed.
            vstkp_n <=  std_logic_vector(unsigned(vstkp_c) + unsigned(dd));
            rstkp_n <=  std_logic_vector(unsigned(rstkp_c) + unsigned(rd));
        else
            if is_instr_cjmp = '1' then
                vstkp_n <=  std_logic_vector(unsigned(vstkp_c) - 1);
            end if;

            if is_instr_call = '1' then -- A call!
                rstkp_n <=  std_logic_vector(unsigned(rstkp_c) + 1);
                rstkW   <=  '1';
                rstkD   <=  "000" & pc_plus_one; 
            else
                rstkW   <=  '0';
                rstkD   <=  "000" & pc_plus_one; 
            end if;
        end if;
    end process;

    pcUpdate: process(
        pc_c,insn,rtos_c,pc_plus_one, 
        is_instr_jmp,is_instr_cjmp,is_instr_call,is_instr_alu, 
        is_instr_interrupt, int_en_c,
        irc_c,
        comp_zero
    )
    begin
        pc_n    <=  pc_c;
        if is_instr_interrupt = '1' and int_en_c = '1' then -- Update PC on interrupt
          -- Prioritory encoded, MSB has higher prioritory, should change this
          interrupts: for i in 1 to number_of_interrupts loop 
            if irc_c(i-1) = '1' then
              pc_n <= std_logic_vector(to_unsigned(i-1,pc_n'length));
            end if;
          end loop;
        else -- Update PC on normal operations
          if is_instr_jmp = '1' or (is_instr_cjmp = '1' and comp_zero = '1') or is_instr_call = '1' then
              pc_n    <=  insn(12 downto 0);
          elsif is_instr_alu = '1' and insn(4) = '1' then
              pc_n    <=  rtos_c(12 downto 0);
          else
              pc_n    <=  pc_plus_one;
          end if;
        end if;
    end process;
end architecture;
