library IEEE;
use IEEE.std_logic_1164.all;

-- Checks the primary's MISC_D source: a one-clock pulse at COUNT = 0 and
-- COUNT = 128, i.e. one pulse per 128-count (25 us) carrier period.
entity tb_carrier_sync is
end entity;

architecture sim of tb_carrier_sync is
    constant T : time := 20 ns;
    signal clk : std_logic := '0';
    signal count : std_logic_vector(7 downto 0);
    signal sync : std_logic;
    signal done : boolean := false;
    signal pulse_count : integer := 0;
begin
    clk <= not clk after T/2 when not done else '0';

    dut : entity work.Counter
        generic map (COUNTER_BITS => 8)
        port map (clk_in => clk, sync_reset => '0',
                  clk_out => count, carrier_sync => sync);

    monitor : process (clk)
        variable prev : std_logic := '0';
        variable cycle : integer := 0;
        variable last : integer := -1000;
        variable pulses : integer := 0;
    begin
        if rising_edge(clk) then
            cycle := cycle + 1;
            assert not (sync = '1' and prev = '1')
                report "carrier_sync is wider than one clock"
                severity failure;
            if sync = '1' and prev = '0' then
                pulses := pulses + 1;
                pulse_count <= pulse_count + 1;
                if last > 0 then
                    assert cycle - last = 128
                        report "carrier_sync period is " &
                               integer'image(cycle - last) & ", expected 128"
                        severity failure;
                end if;
                last := cycle;
            end if;
            prev := sync;
        end if;
    end process;

    stimulus : process
    begin
        wait for 600 * T;
        assert pulse_count >= 4
            report "too few carrier_sync pulses"
            severity failure;
        done <= true;
        report "TEST PASSED: tb_carrier_sync" severity note;
        wait;
    end process;
end architecture;
