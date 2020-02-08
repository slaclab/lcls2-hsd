-- ==============================================================
-- RTL generated by Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC
-- Version: 2016.4
-- Copyright (C) 1986-2017 Xilinx, Inc. All Rights Reserved.
-- 
-- ===========================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use work.FmcPkg.all;
use work.QuadAdcPkg.all;

entity hsd_thr_native is
generic (
    C_S_AXI_BUS_A_ADDR_WIDTH : INTEGER := 6;
    C_S_AXI_BUS_A_DATA_WIDTH : INTEGER := 32;
    BASELINE                 : AdcWord);
port (
    ap_clk   : IN STD_LOGIC;
    ap_rst_n : IN STD_LOGIC;
    sync     : IN  STD_LOGIC;
    x        : in  AdcWordArray(ROW_SIZE-1 downto 0);
    tin      : in  Slv2Array   (ROW_SIZE-1 downto 0);
    y        : out Slv16Array  (ROW_SIZE   downto 0);
    tout     : out Slv2Array   (ROW_SIZE   downto 0);
    yv       : out slv         (ROW_IDXB-1 downto 0);
    axilReadMaster  : in  AxiLiteReadMasterType;
    axilReadSlave   : out AxiLiteReadSlaveType;
    axilWriteMaster : in  AxiLiteWriteMasterType;
    axilWriteSlave  : out AxiLiteWriteSlaveType );

end;

architecture behav of hsd_thr_native is
  
  type RegType is record
    xlo        : AdcWord;
    xhi        : AdcWord;
    tpre       : slv( 3 downto 0);
    tpost      : slv( 3 downto 0);
    sync       : sl;
    
    count      : slv(14 downto 0);
    count_last : slv(14 downto 0);
    nopen      : slv(4 downto 0);
    lskip      : sl;

    waddr      : slv( 3 downto 0);
    raddr      : slv( 3 downto 0);
    akeep      : slv(15 downto 0);
    keepm      : slv(15 downto 0);
    
    y          : Slv16Array(ROW_SIZE downto 0);
    t          : Slv2Array (ROW_SIZE downto 0);
    yv         : slv       (ROW_IDXB-1 downto 0);
    readSlave  : AxiLiteReadSlaveType;
    writeSlave : AxiLiteWriteSlaveType;
  end record;

  constant REG_INIT_C : RegType := (
    xlo        => BASELINE,
    xhi        => BASELINE,
    tpre       => toSlv(  1,4),
    tpost      => toSlv(  1,4),
    sync       => '1',
    
    count      => (others=>'0'),
    count_last => (others=>'0'),
    nopen      => (others=>'0'),
    lskip      => '0',

    waddr      => (others=>'0'),
    raddr      => (others=>'0'),
    akeep      => (others=>'0'),
    keepm      => (others=>'0'),
    
    y          => (others=>(others=>'0')),
    t          => (others=>(others=>'0')),
    yv         => (others=>'0'),
    readSlave  => AXI_LITE_READ_SLAVE_INIT_C,
    writeSlave => AXI_LITE_WRITE_SLAVE_INIT_C );

  signal r    : RegType := REG_INIT_C;
  signal r_in : RegType;

  signal xsave : AdcWordArray(ROW_SIZE-1 downto 0);
  signal tsave : Slv2Array   (ROW_SIZE-1 downto 0);
  
begin

  axilWriteSlave <= r.writeSlave;
  axilReadSlave  <= r.readSlave;
  
  GEN_RAM : for i in 0 to ROW_SIZE-1 generate
    U_RAM : entity surf.SimpleDualPortRam
      generic map ( DATA_WIDTH_G => AdcWord'length+2,
                    ADDR_WIDTH_G => 4 )
      port map ( clka                => ap_clk,
                 wea                 => '1',
                 addra               => r.waddr,
                 dina(AdcWord'range) => x(i),
                 dina(AdcWord'length+1 downto
                      AdcWord'length)=> tin(i),
                 clkb                => ap_clk,
                 addrb               => r.raddr,
                 doutb(AdcWord'range) => xsave(i),
                 doutb(AdcWord'length+1 downto
                       AdcWord'length)=> tsave(i) );
  end generate;
  
  comb : process ( ap_rst_n, r, x, tin, xsave, tsave,
                   axilWriteMaster, axilReadMaster ) is
    variable v      : RegType;
    variable ep     : AxiLiteEndPointType;
    variable tsum   : slv(1 downto 0);
    variable iopen  : integer;
    variable lout   : sl;
    variable lkeep  : sl;
    variable dcount : slv(14 downto 0);
  begin
    v := r;

    -- AxiLite accesses
    axiSlaveWaitTxn( ep,
                     axilWriteMaster, axilReadMaster,
                     v.writeSlave, v.readSlave );

    v.readSlave.rdata := (others=>'0');
      
    axiSlaveRegister ( ep, x"10", 0, v.xlo   );
    axiSlaveRegister ( ep, x"18", 0, v.xhi   );
    axiSlaveRegister ( ep, x"20", 0, v.tpre  );
    axiSlaveRegister ( ep, x"28", 0, v.tpost );

    v.sync := '0';
    axiWrDetect(ep, x"20", v.sync);
    axiWrDetect(ep, x"28", v.sync);
    
    axiSlaveDefault( ep, v.writeSlave, v.readSlave );

    v.keepm := (others=>'0');
    for i in r.keepm'range loop
      if (i < (conv_integer(r.tpre)+conv_integer(r.tpost))) then
        v.keepm(i) := '1';
      end if;
    end loop;

    lkeep := '0';
    for i in 0 to ROW_SIZE-1 loop
      if ((x(i) < r.xlo) or (x(i) > r.xhi)) then
        lkeep := '1';
      end if;
    end loop;

    if lkeep = '1' then
      v.akeep := v.akeep or r.keepm;
    end if;
    v.akeep := '0' & v.akeep(r.akeep'left downto 1);

    lout := lkeep or r.akeep(0);
    
    -- default response
    for i in 0 to ROW_SIZE-1 loop
--      v.y(i) := resize(x(i),16);
      v.y(i) := resize(xsave(i),16);
    end loop;
    v.y(8) := x"8000";
--    v.t    := "00" & tin;
    v.t    := "00" & tsave;
    
    tsum := "00";
    iopen := 0;
    for i in 0 to ROW_SIZE-1 loop
--      tsum := tsum or tin(i);
      tsum := tsum or tsave(i);
--      if tin(i)(0) = '1' then
      if tsave(i)(0) = '1' then
        iopen := i;
      end if;
    end loop;

    dcount := r.count - r.count_last;

    if (((r.nopen/=0) or (tsum(0)='1')) and lout='1') then
      if r.lskip = '1' then
        -- skip to the first position
        v.y(0) := '1' & dcount;
        v.t(0) := "00";
        for i in 0 to ROW_SIZE-1 loop
          v.y(i+1) := resize(xsave(i),16);
          v.t(i+1) := tsave(i);
        end loop;
        v.yv   := toSlv(ROW_SIZE+1,ROW_IDXB);
      else
        for i in 0 to ROW_SIZE-1 loop
          v.y(i) := resize(xsave(i),16);
          v.t(i) := tsave(i);
        end loop;
        v.yv   := toSlv(ROW_SIZE,ROW_IDXB);
      end if;
      v.count_last := r.count+ROW_SIZE-1;
      v.lskip      := '0';
    elsif (tsum/="00" or dcount(dcount'left)='1') then
      -- skip to the opening position
      v.y(0) := '1' & dcount+iopen;
      v.t(0) := tsum;
      for i in 0 to ROW_SIZE-1 loop
        v.y(i+1) := resize(xsave(i),16);
        v.t(i+1) := tsave(i);
      end loop;
      --  If no gate is open, do we need a skip character
      --if tsum/="00" then
      --  v.yv   := toSlv(1,ROW_IDXB);
      --else
      --  v.yv   := toSlv(0,ROW_IDXB);
      --end if;
      v.yv    := toSlv(1,ROW_IDXB);
      v.count_last := r.count + iopen;
      if iopen < ROW_SIZE-1 then
        v.lskip := '1';
      else
        v.lskip := '0';
      end if;
    else
      -- skip to the first position
      v.y(0) := '1' & resize(dcount-1,15);
      v.t(0) := tsum;
      for i in 0 to ROW_SIZE-1 loop
        v.y(i+1) := resize(xsave(i),16);
        v.t(i+1) := tsave(i);
      end loop;
      v.yv   := toSlv(0,ROW_IDXB);
      v.lskip := '1';
    end if;

    if r.sync = '1' then
      v.waddr := r.tpre;
      v.raddr := (others=>'0');
    else
      v.waddr := r.waddr + 1;
      v.raddr := r.raddr + 1;
    end if;
    
    if tsum = "01" then
      v.nopen := r.nopen+1;
    elsif tsum = "10" then
      v.nopen := r.nopen-1;
    end if;

    v.count := r.count + ROW_SIZE;

    y    <= r.y;
    yv   <= r.yv;
    tout <= r.t;
    
    if ap_rst_n = '0' then
      v := REG_INIT_C;
    end if;

    r_in <= v;
  end process comb;

  seq : process ( ap_clk ) is
  begin
    if rising_edge(ap_clk) then
      r <= r_in;
    end if;
  end process seq;

end behav;