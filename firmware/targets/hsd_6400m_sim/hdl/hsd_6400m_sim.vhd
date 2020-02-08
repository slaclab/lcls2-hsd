-----------------------------------------------------------------------------
-- Title      : 
-------------------------------------------------------------------------------
-- File       : hsd_dualv2_sim.vhd
-- Author     : Matt Weaver <weaver@slac.stanford.edu>
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2015-07-10
-- Last update: 2020-02-07
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- This file is part of 'LCLS2 DAQ Software'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'LCLS2 DAQ Software', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;
use ieee.std_logic_unsigned.all;

use STD.textio.all;
use ieee.std_logic_textio.all;


library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.Pgp3Pkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;
use lcls_timing_core.TPGPkg.all;

library l2si_core;
use l2si_core.XpmPkg.all;
use work.QuadAdcPkg.all;
use surf.SsiPkg.all;
use surf.AxiPkg.all;
use work.FmcPkg.all;

library unisim;
use unisim.vcomponents.all;

entity hsd_6400m_sim is
end hsd_6400m_sim;

architecture top_level_app of hsd_6400m_sim is

   constant NCHAN_C : integer := 2;
   constant NFMC_C  : integer := 2;

   signal rst      : sl;
   
    -- AXI-Lite and IRQ Interface
   signal regClk    : sl;
   signal regRst    : sl;
   signal axilWriteMaster     : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
   signal axilWriteSlave      : AxiLiteWriteSlaveType;
   signal axilReadMaster      : AxiLiteReadMasterType := AXI_LITE_READ_MASTER_INIT_C;
   signal axilReadSlave       : AxiLiteReadSlaveType;
    -- DMA
   signal dmaClk            : sl;
   signal dmaRst            : slv(NFMC_C-1 downto 0);
   signal dmaIbMaster       : AxiStreamMasterArray(NFMC_C-1 downto 0);
   signal dmaIbSlave        : AxiStreamSlaveArray (NFMC_C-1 downto 0) := (others=>AXI_STREAM_SLAVE_FORCE_C);

   signal dbgWriteSlave      : AxiLiteWriteSlaveType;
   signal dbgReadSlave       : AxiLiteReadSlaveType;

   signal dbgClk            : sl;
   signal phyClk            : sl;
   signal refTimingClk      : sl;
   signal adcO              : AdcDataArray(3 downto 0);
   signal adcI              : AdcDataArray(4*NFMC_C-1 downto 0);
   signal trigIn            : slv(ROW_SIZE-1 downto 0);
   signal trigSel           : slv(1 downto 0);
   signal trigSlot          : slv(1 downto 0);
   
--   constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(16);
   constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(32);

   signal dmaData           : slv(31 downto 0);
   signal dmaUser           : slv( 1 downto 0);

   signal axilDone : sl := '0';

   signal config  : QuadAdcConfigType := (
     enable    => toSlv(1,8),
     partition => (others=>'0'),
     intlv     => "00",
     samples   => toSlv(0,18),
     prescale  => toSlv(0,6),
     offset    => toSlv(0,20),
     acqEnable => '1',
     rateSel   => (others=>'0'),
     destSel   => (others=>'0'),
     inhibit   => '0',
     dmaTest   => '0',
     trigShift => (others=>'0'),
     localId   => (others=>'0') );

   constant DBG_AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(ROW_SIZE*2);
   signal dbgIbMaster : AxiStreamMasterType;
   signal evtId   : slv(31 downto 0) := (others=>'0');
   signal fexSize : slv(30 downto 0) := (others=>'0');
   signal fexOvfl : sl := '0';
   signal fexOffs : slv(15 downto 0) := (others=>'0');
   signal fexIndx : slv(15 downto 0) := (others=>'0');

   signal tpgConfig : TPGConfigType := TPG_CONFIG_INIT_C;

   -- Timing Interface (timingClk domain) 
   signal xData     : TimingRxType  := TIMING_RX_INIT_C;
   signal timingBus : TimingBusType := TIMING_BUS_INIT_C;
   signal recTimingClk : sl;
   signal recTimingRst : sl;

   signal timingFb          : TimingPhyType;

   constant DMA_AXIS_CONFIG_C : AxiStreamConfigType := (
     TSTRB_EN_C    => false,
     TDATA_BYTES_C => ROW_SIZE*2,
     TDEST_BITS_C  => 4,
     TID_BITS_C    => 0,
     TKEEP_MODE_C  => TKEEP_FIXED_C,
     TUSER_BITS_C  => 2,
     TUSER_MODE_C  => TUSER_FIRST_LAST_C);

   signal dsRxClk      : slv(XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsRxRst      : slv(XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsRxData     : Slv16Array(XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsRxDataK    : Slv2Array (XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsRxData_0   : slv(15 downto 0);
   signal dsRxDataK_0  : slv( 1 downto 0);
   signal dsTxClk      : slv(XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsTxRst      : slv(XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsTxData     : Slv16Array(XPM_MAX_DS_LINKS_C-1 downto 0);
   signal dsTxDataK    : Slv2Array (XPM_MAX_DS_LINKS_C-1 downto 0);

   signal fmcClk  : slv(NFMC_C-1 downto 0);
   signal pgpRxOut       : Pgp3RxOutType;

begin

   dmaData <= dmaIbMaster(0).tData(dmaData'range);
   dmaUser <= dmaIbMaster(0).tUser(dmaUser'range);

   U_ClkSim : entity work.ClkSim
     generic map ( VCO_HALF_PERIOD_G => 21.0 ps,
                   TIM_DIVISOR_G     => 64,
                   PHY_DIVISOR_G     => 2 )
     port map ( phyClk   => phyClk,
                evrClk   => refTimingClk );

   U_QIN : entity work.AdcRamp
     generic map ( DATA_LO_G => x"0000",
                   DATA_HI_G => x"0200" )
     port map ( rst      => rst,
                phyClk   => phyClk,
                dmaClk   => dmaClk,
                ready    => axilDone,
                adcOut   => adcO,
                trigSel  => trigSel(0),
                trigOut  => trigIn );

   adcI(7 downto 4) <= adcO;
   adcI(3 downto 0) <= adcO;
   
   process is
   begin 
     dbgClk <= '1';
     wait for 1.2 ns;
     dbgClk <= '0';
     wait for 1.2 ns;
   end process;
  
   process is
   begin
     rst <= '1';
     wait for 100 ns;
     rst <= '0';
     wait;
   end process;
   
   regRst       <= rst;
   recTimingRst <= rst;
   
   process is
   begin
     regClk <= '0';
     wait for 3.2 ns;
     regClk <= '1';
     wait for 3.2 ns;
   end process;
     
   recTimingClk <= dsTxClk  (0);
   xData.data   <= dsTxData (0);
   xData.dataK  <= dsTxDataK(0);
   dsRxClk      <= (others=>recTimingClk);
   dsRxRst      <= dsTxRst;
   dsRxData_0   <= timingFb.data;
   dsRxDataK_0  <= timingFb.dataK;
   dsRxData (0) <= dsRxData_0;
   dsRxDataK(0) <= dsRxDataK_0;
   
   U_XPM : entity l2si_core.XpmSim
     generic map ( USE_TX_REF        => true,
                   ENABLE_DS_LINKS_G => toSlv(1,XPM_MAX_DS_LINKS_C),
                   RATE_DIV_G        => 1 )
     port map ( txRefClk  => refTimingClk,
                dsTxClk   => dsTxClk,
                dsTxRst   => dsTxRst,
                dsTxData  => dsTxData,
                dsTxDataK => dsTxDataK,
                dsRxClk   => dsRxClk,
                dsRxRst   => dsRxRst,
                dsRxData  => dsRxData,
                dsRxDataK => dsRxDataK,
                --
                --bpTxClk    => recTimingClk,
                --bpTxLinkUp => '1',
                --bpTxData   => xData.data,
                --bpTxDataK  => xData.dataK,
                bpTxLinkUp => '0',
                bpRxClk    => '0',
                bpRxClkRst => '0',
                bpRxLinkUp => (others=>'0'),
                bpRxLinkFull => (others=>(others=>'0')) );

   timingBus.modesel <= '1';
   U_RxLcls : entity lcls_timing_core.TimingFrameRx
     port map ( rxClk               => recTimingClk,
                rxRst               => recTimingRst,
                rxData              => xData,
                messageDelay        => (others=>'0'),
                messageDelayRst     => '0',
                timingMessage       => timingBus.message,
                timingMessageStrobe => timingBus.strobe,
                timingMessageValid  => timingBus.valid,
                timingExtension     => timingBus.extension );

  fmcClk <= (others=>phyClk);
  
  U_Core : entity work.DualAdcCore
    generic map ( DMA_STREAM_CONFIG_G => AXIS_CONFIG_C )
    port map (
      axiClk              => regClk,
      axiRst              => regRst,
      axilWriteMaster     => axilWriteMaster,
      axilWriteSlave      => axilWriteSlave ,
      axilReadMaster      => axilReadMaster ,
      axilReadSlave       => axilReadSlave  ,
      -- DMA
      dmaClk              => dmaClk,
      dmaRst              => dmaRst,
      dmaRxIbMaster       => dmaIbMaster,
      dmaRxIbSlave        => dmaIbSlave ,
      -- EVR Ports
      evrClk              => recTimingClk,
      evrRst              => recTimingRst,
      evrBus              => timingBus,
      timingFbClk         => recTimingClk,
      timingFbRst         => recTimingRst,
      timingFb            => timingFb,
      -- ADC
      gbClk               => '0', -- unused
      adcClk              => dmaClk,
      adcRst              => dmaRst(0),
      adc                 => adcI,
      adcValid            => "11",
      fmcClk              => fmcClk,
      --
      trigSlot            => trigSlot,
      trigOut             => trigSel,
      trigIn(19 downto 10)=> trigIn,
      trigIn( 9 downto 0) => trigIn );

   process is
     procedure wreg(addr : integer; data : slv(31 downto 0)) is
     begin
       wait until regClk='0';
       axilWriteMaster.awaddr  <= toSlv(addr,32);
       axilWriteMaster.awvalid <= '1';
       axilWriteMaster.wdata   <= data;
       axilWriteMaster.wvalid  <= '1';
       axilWriteMaster.bready  <= '1';
       wait until regClk='1';
       wait until axilWriteSlave.bvalid='1';
       wait until regClk='0';
       wait until regClk='1';
       wait until regClk='0';
       axilWriteMaster.awvalid <= '0';
       axilWriteMaster.wvalid  <= '0';
       axilWriteMaster.bready  <= '0';
       wait for 50 ns;
     end procedure;
     variable a : integer;
   begin
    wait until regRst='0';

    --  Address map change
    --  DualAdcCore: 0000_0000  (ChipAdcCore[0])
    --                    0000  ChipAdcReg
    --                    1000  (ChipAdcEvent)
    --                    1000  QuadAdcInterleavePacked
    --                    1100  hsd_fex_packed[0]
    --                    1200  hsd_fex_packed[1]
    --               0000_2000  (ChipAdcCore[1])
    --               0000_4000  TriggerEventManager
    --                    4000  (XpmMessageAligner)
    --                    4000  partitionDelays[0..7]
    --                    4020  xpmId (feedbackId)
    --                    4100  (TriggerEventBuffer[0])
    --                    4100  enable
    --                    4104  partition
    --                    4108  overflows,fifoWrCnt
    --                    410c  linkAddress (received)
    --                    4110  l0Count
    --                    4114  l1aCount
    --                    411c  l1rCount
    --                    4120  triggerDelay
    --                    4134  transitionCount
    --                    4138  validCount
    --                    413c  triggerCount
    --                    4140  message.partitionAddr (unlatched)
    --                    4144  message.partitionWord[0] (unlatched)
    --                    414c  resetCounters
    --                    4150  fullToTrig
    --                    4154  nfullToTrig
    --                    4200  (TriggerEventBuffer[1])
    
    --  ChipAdcReg
    wait for 20 ns;
    for i in 0 to 1 loop
      a := 1024*8*i;
      wreg(a+16,x"000000ff");  -- assert DMA rst
    end loop;
    
    wait for 1200 ns;
    for i in 0 to 1 loop
      a := 1024*8*i;
      wreg(a+16,x"00000000");  -- release DMA rst
      wreg(a+20,x"40000000");  -- 1MHz, dont-care
      wreg(a+24,x"00000001");  -- enable 1 channel
--      wreg(a+24,x"00000003");  -- enable 2 channels
      wreg(a+28,x"00000100");  -- 256 samples
    end loop;

    -- QuadAdcInterleavePacked
    wait for 1200 ns;
    for i in 0 to 1 loop
      a := 1024*8*i + 1024*4;
      wreg(a+16,x"00000003"); -- prescale
      wreg(a+20,x"00640004"); -- fexLength/Delay
      wreg(a+24,x"00040C00"); -- almostFull
      wreg(a+32,x"00000000"); -- prescale
      wreg(a+36,x"00640004"); -- fexLength/Delay
      wreg(a+40,x"00040C00"); -- almostFull
      wreg(a+48,x"00000000"); -- prescale
      wreg(a+52,x"00640004"); -- fexLength/Delay
      wreg(a+56,x"00040C00"); -- almostFull
--      wreg(a+256*2+16,x"00000000");  -- xlo
--      wreg(a+256*2+24,x"00000fff");  -- xhi
      wreg(a+256*2+16,x"00000040");  -- xlo
      wreg(a+256*2+24,x"00000bc0");  -- xhi
      wreg(a+256*2+32,x"00000001");  -- tpre
      wreg(a+256*2+40,x"00000002");  -- tpost
      --wreg(a+256*3+16,x"00000040");
      --wreg(a+256*3+24,x"000003c0");
      --wreg(a+256*3+32,x"00000003");
      --wreg(a+256*3+40,x"00000002");
      wreg(a+ 0,x"00000041"); -- fexEnable
    end loop;
    wait for 600 ns;

    -- ChipAdcReg
    a := 0;
    wreg(a+16,x"c0000000");  -- enable
    a := 1024*8;
    wreg(a+16,x"c0000000");  -- enable

    -- XpmMessageAligner
    a := 1024*16+32;
    wreg(a,x"0a0b0c0d"); -- feedback Id

    -- TriggerEventBuffer
    for i in 0 to 1 loop
      a := 1024*16+256*(i+1);
      wreg(a+ 4,x"00000000"); -- partition
      wreg(a+ 8,x"00100000"); -- fifoPauseThresh
      wreg(a+32,x"00000000"); -- triggerDelay
      wreg(a+ 0,x"00000003"); -- enable
    end loop;

    axilDone <= '1';
    
    wait;
  end process;

  U_XTC : entity work.HsdXtc
    generic map ( filename => "hsd.xtc" )
    port map ( axisClk    => dmaClk,
               axisMaster => dmaIbMaster(0),
               axisSlave  => dmaIbSlave (0) );

  throttle_p : process ( dmaClk ) is
    variable count     : slv(7 downto 0) := (others=>'0');
    constant RELEASE_C : slv(7 downto 0) := toSlv(63,count'length);
  begin
    if rising_edge(dmaClk) then
      if count = RELEASE_C then
        count      := (others=>'0');
        for i in 0 to NFMC_C-1 loop
          dmaIbSlave(i).tReady <= '1';
        end loop;
      else
        count      := count+1;
        for i in 0 to NFMC_C-1 loop
          dmaIbSlave(i).tReady <= '0';
        end loop;
      end if;
    end if;
  end process;

  U_PgpFb : entity l2si_core.DtiPgp3Fb
    port map ( pgpClk       => dmaClk,
               pgpRst       => dmaRst(0),
               pgpRxOut     => pgpRxOut,
               rxLinkId     => open,
               rxAlmostFull => open );
    
end top_level_app;