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

entity hsd_thr_ilv_native is
generic (
    ILV_G                    : INTEGER := 4;
    BASELINE                 : AdcWord);
port (
    ap_clk   : IN STD_LOGIC;
    ap_rst_n : IN STD_LOGIC;
    sync     : IN  STD_LOGIC;
    x        : in  AdcWordArray(ILV_G*ROW_SIZE-1 downto 0);
    tin      : in  Slv2Array   (      ROW_SIZE-1 downto 0);
    y        : out Slv16Array  (ILV_G*ROW_SIZE+ILV_G-1 downto 0);
    tout     : out Slv2Array   (      ROW_SIZE   downto 0);
    yv       : out slv         (      ROW_IDXB-1 downto 0);
    axilReadMaster  : in  AxiLiteReadMasterType;
    axilReadSlave   : out AxiLiteReadSlaveType;
    axilWriteMaster : in  AxiLiteWriteMasterType;
    axilWriteSlave  : out AxiLiteWriteSlaveType );

end;

architecture behav of hsd_thr_ilv_native is
  
  type RegType is record
    xlo        : AdcWord;           -- low threshold
    xhi        : AdcWord;           -- high threshold
    tpre       : slv( 3 downto 0);  -- number of rows to readout before crossing
    tpost      : slv( 3 downto 0);  -- number of rows to readout after crossing
    sync       : sl;
    
    count      : slv(12 downto 0);
    count_last : slv(12 downto 0);
    nopen      : slv(4 downto 0);   -- number of readout streams open
    lskip      : sl;
    tskip      : slv( 1 downto 0);
    
    waddr      : slv( 3 downto 0);  -- index into row buffer
    raddr      : slv( 3 downto 0);
    akeep      : slv(15 downto 0);  -- mask of rows which require readout
    keepm      : slv(15 downto 0);  -- mask of rows to add to akeep when a
                                    -- threshold crossing is found
    
    y          : Slv16Array(ILV_G*ROW_SIZE+ILV_G-1 downto 0); -- readout
    t          : Slv2Array (      ROW_SIZE downto 0);
    yv         : slv       (      ROW_IDXB-1 downto 0);  -- number of valid
                                                         -- readout samples
    
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
    tskip      => "00",
    
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

  signal xsave : AdcWordArray(ILV_G*ROW_SIZE-1 downto 0);
  signal tsave : Slv2Array   (      ROW_SIZE-1 downto 0);

begin

  axilWriteSlave <= r.writeSlave;
  axilReadSlave  <= r.readSlave;

  --
  --  Buffer of sample and trigger data
  --    Necessary for prepending samples when a threshold crossing
  --    is found within the trigger window.
  --
  GEN_RAM : for i in 0 to ROW_SIZE-1 generate
    U_RAMB : block is
      signal din,dout : slv(ILV_G*AdcWord'length+1 downto 0);
    begin
      GEN_DIN : for j in 0 to ILV_G-1 generate
        din((j+1)*AdcWord'length-1 downto j*AdcWord'length) <= x(i*ILV_G+j);
        xsave(i*ILV_G+j) <= dout((j+1)*AdcWord'length-1 downto j*AdcWord'length);
      end generate;
      din(ILV_G*AdcWord'length+1 downto ILV_G*AdcWord'length) <= tin(i);
      tsave(i) <= dout(ILV_G*AdcWord'length+1 downto ILV_G*AdcWord'length);
      
      U_RAM : entity surf.SimpleDualPortRam
        generic map ( DATA_WIDTH_G => ILV_G*AdcWord'length+2,
                      ADDR_WIDTH_G => 4 )
        port map ( clka                => ap_clk,
                   wea                 => '1',
                   addra               => r.waddr,
                   dina                => din,
                   clkb                => ap_clk,
                   addrb               => r.raddr,
                   doutb               => dout );
    end block;
  end generate;
  
  comb : process ( ap_rst_n, r, x, tin, xsave, tsave,
                   axilWriteMaster, axilReadMaster ) is
    variable v      : RegType;
    variable ep     : AxiLiteEndPointType;
    variable tsum   : slv(1 downto 0);
    variable iopen  : integer;
    variable lout   : sl;
    variable lkeep  : sl;
    variable dcount : slv(12 downto 0);
    constant ILVB   : integer := bitSize(ILV_G-1);
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
    for i in 0 to r.keepm'left-1 loop
      if (i < (conv_integer(r.tpre)+conv_integer(r.tpost)+1)) then
        v.keepm(i+1) := '1';
      end if;
    end loop;

    --  test threshold crossing anywhere in the row
    lkeep := '0';
    for i in 0 to ILV_G*ROW_SIZE-1 loop
      if ((x(i) < r.xlo) or (x(i) > r.xhi)) then
        lkeep := '1';
      end if;
    end loop;

    v.akeep := '0' & v.akeep(r.akeep'left downto 1);
    if lkeep = '1' then
      v.akeep := v.akeep or r.keepm;
    end if;

--    lout := lkeep or r.akeep(0);  -- xsave row needs readout
    lout := r.akeep(0);  -- xsave row needs readout
    
    -- default response
    for i in 0 to ILV_G*ROW_SIZE-1 loop
      v.y(i) := resize(xsave(i),16);
    end loop;
    for i in 0 to ILV_G-1 loop
      v.y(i+ILV_G*ROW_SIZE) := x"8000";
    end loop;
    v.t     := "00" & tsave;

    -- check for trigger window opening/closing
    --   only one may open/close within a row, but multiple
    --   windows may remain open
    tsum := "00";
    iopen := ROW_SIZE-1;
    for i in ROW_SIZE-1 downto 0 loop
      tsum := tsum or tsave(i);
      if tsave(i)(0) = '1' then
        iopen := i;
      end if;
    end loop;

    --  samples/ILV_G since last readout
    dcount := r.count - r.count_last;

    -- window is open and this row needs readout
    if (((r.nopen/=0) or (tsum(0)='1')) and lout='1') then
      if r.lskip = '1' then --  samples have been skipped
        -- skip to the first position
        v.y(0) := '1' & resize(dcount-1,15-ILVB) & toSlv(0,ILVB);
        for i in 1 to ILV_G-1 loop
          v.y(i) := '1' & toSlv(0,15);
        end loop;
        v.t(0)  := r.tskip;
        v.tskip := "00";
        -- and readout the row
        for i in 0 to ROW_SIZE-1 loop
          for j in 0 to ILV_G-1 loop
            v.y((i+1)*ILV_G+j) := resize(xsave(i*ILV_G+j),16);
          end loop;
          v.t(i+1) := tsave(i);
        end loop;
        v.yv   := toSlv(ROW_SIZE+1,ROW_IDXB);
      else  -- no skip needed
        for i in 0 to ROW_SIZE-1 loop
          for j in 0 to ILV_G-1 loop
            v.y(i*ILV_G+j) := resize(xsave(i*ILV_G+j),16);
          end loop;
          v.t(i) := tsave(i);
        end loop;
        v.yv   := toSlv(ROW_SIZE,ROW_IDXB);
      end if;
      v.count_last := r.count+ROW_SIZE-1;
      v.lskip      := '0';
    -- a window opened/closed or enough samples skipped, but no readout
    elsif (tsum/="00" or dcount(dcount'left) ='1') then
      -- skip to the opening position
      v.y(0) := '1' & resize(dcount+iopen,15-ILVB) & toSlv(0,ILVB);
      for i in 1 to ILV_G-1 loop
        v.y(i) := '1' & toSlv(0,15);
      end loop;
      v.t(0)  := r.tskip;
      v.tskip := tsum;  -- save trigger bits for next readout/skip
      --if tsum/="00" then
      --  v.yv    := toSlv(1,ROW_IDXB);
      --else
      --  v.yv    := toSlv(0,ROW_IDXB);
      --end if;
      v.yv    := toSlv(1,ROW_IDXB);
      v.count_last := r.count + iopen;
      if iopen < ROW_SIZE-1 then
        v.lskip := '1';
      else
        v.lskip := '0';
      end if;
    -- no readout
    else
      v.yv    := toSlv(0,ROW_IDXB);
      v.lskip := '1';
    end if;

    if r.sync = '1' then
      v.waddr := r.tpre+1;
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