library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity Counter is
	 generic(COUNTER_BITS: integer := 8);
    port (
        clk_in : in  STD_LOGIC;
		  sync_reset : in STD_LOGIC;
        clk_out: out STD_LOGIC_VECTOR (COUNTER_BITS-1 downto 0);
		  -- One clk_in-wide pulse at the start of every carrier period.
		  carrier_sync : out STD_LOGIC := '0'
	 );
end Counter;

architecture Behavioral of Counter is
    signal sCounter : STD_LOGIC_VECTOR (COUNTER_BITS-1 downto 0) := (others => '0');
	 signal prev_res : STD_LOGIC := '0';
begin
    pCounter: process (clk_in) begin
        if rising_edge(clk_in) then
				prev_res <= sync_reset;
				if (sync_reset = '1' and prev_res = '0') then
					sCounter <= (others => '0');
				else
					sCounter <= sCounter + 1;
				end if;
        end if;
    end process;

    clk_out <= sCounter;

	 -- The carrier is 16 steps x 8 clk8 = 128 counts, so the phase-0 slot
	 -- begins whenever the low seven bits are zero (counts 0 and 128 of the
	 -- 8-bit counter).  This is the timing reference sent to the secondary:
	 -- an exact one-clock pulse at a known counter value, unlike the old
	 -- COUNT[6] square wave whose rising edge sat in the middle of a period.
	 carrier_sync <= '1' when sCounter(6 downto 0) = "0000000" else '0';
end Behavioral;