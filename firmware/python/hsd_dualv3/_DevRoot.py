#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# This file is part of the 'Camera link gateway'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'Camera link gateway', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------
import pyrogue as pr
import pyrogue.utilities.fileio
import rogue
import click
import time

import axipcie
import lcls2_pgp_fw_lib.hardware.shared as shared
import hsd_dualv3                       as dev

rogue.Version.minVersion('5.1.0')
# rogue.Version.exactVersion('5.1.0')

class DevRoot(shared.Root):

    def __init__(self,
                 dev            = '/dev/datadev_0',# path to PCIe device
                 enLclsI        = True,
                 enLclsII       = False,
                 startupMode    = False, # False = LCLS-I timing mode, True = LCLS-II timing mode
                 pollEn         = True,  # Enable automatic polling registers
                 initRead       = True,  # Read all registers at start of the system
                 numLanes       = 2,     # Number of DMA lanes
                 devTarget      = dev.Pc820,
                 **kwargs):

        # Set the firmware Version lock = firmware/targets/shared_version.mk
        self.FwVersionLock = 0x00000001

        # Set local variables
        self.dev            = dev
        self.startupMode    = startupMode

        # Check for simulation
        if dev == 'sim':
            kwargs['timeout'] = 100000000 # 100 s
        else:
            kwargs['timeout'] = 5000000 # 5 s

        # Pass custom value to parent via super function
        super().__init__(
            dev         = dev,
            pollEn      = pollEn,
            initRead    = initRead,
            numLanes    = numLanes,
            **kwargs)

        # Unhide the RemoteVariableDump command
        self.RemoteVariableDump.hidden = False

        # Create memory interface
        self.memMap = axipcie.createAxiPcieMemMap(dev, 'localhost', 8000)

        # Instantiate the top level Device and pass it the memory map
        self.add(devTarget(
            name     = 'DevPcie',
            memBase  = self.memMap,
            numLanes = numLanes,
            enLclsI  = enLclsI,
            enLclsII = enLclsII,
            expand   = True,
        ))

        # Add a data writer
        dataWriter = pr.utilities.fileio.StreamWriter()
        self.add(dataWriter)
#        for i in range(numLanes):
        for i in range(1):
            # Setup the DMA channel
            attr = f'dmaLane{i}'
            setattr(self,attr,rogue.hardware.axi.AxiStreamDma(dev,256*i+0,True))
            pyrogue.streamConnect(getattr(self,attr), dataWriter.getChannel(i))

        self.add(pr.LocalVariable(
            name        = 'RunState',
            description = 'Run state status, which is controlled by the StopRun() and StartRun() commands',
            mode        = 'RO',
            value       = False,
        ))

        @self.command(description  = 'Stops the triggers and blows off data in the pipeline')
        def StopRun():
            print ('ClinkDev.StopRun() executed')

            self.DevPcie.Application.TriggerEventManager.TriggerEventBuffer[0].MasterEnable.set(0)

            # Update the run state status variable
            self.RunState.set(False)

        @self.command(description  = 'starts the triggers and allow steams to flow to DMA engine')
        def StartRun():
            print ('ClinkDev.StartRun() executed')

            self.DevPcie.Application.TriggerEventManager.TriggerEventBuffer[0].MasterEnable.set(1)

            # Update the run state status variable
            self.RunState.set(True)

        @self.command(description = 'enable ADC test pattern',value='')
        def TestPattern(arg):
            self.DevPcie.I2cBus.set_i2c_mux('PrimaryFmc')
            self.DevPcie.I2cBus.FmcSpi.adc_disable_test()
            self.DevPcie.I2cBus.FmcSpi.adc_enable_test(arg)

    def start(self, **kwargs):
        super().start(**kwargs)

        # Hide all the "enable" variables
        for enableList in self.find(typ=pr.EnableVariable):
            # Hide by default
            enableList.hidden = True

        # Check if simulation
        if (self.dev=='sim'):
            pass

        else:

            # Check for PCIe FW version
            fwVersion = self.DevPcie.AxiPcieCore.AxiVersion.FpgaVersion.get()
            if (fwVersion != self.FwVersionLock):
                errMsg = f"""
                    PCIe.AxiVersion.FpgaVersion = {fwVersion:#04x} != {self.FwVersionLock:#04x}
                    Please update PCIe firmware using software/scripts/updatePcieFpga.py
                    """
                click.secho(errMsg, bg='red')
                # raise ValueError(errMsg)

            # Read all the variables
            self.ReadAll()
            self.ReadAll()

            # Load the YAML configurations
            #print(f'Loading {defaultFile} Configuration File...')
            #self.LoadConfig(defaultFile)

            # Set the VC data tap
            #vcDataTap = self.find(typ=dev.VcDataTap)
            #for devPtr in vcDataTap:
            #    devPtr.Tap.set(self.dataVc)

            # Start the I2c monitoring devices
            self.DevPcie.I2cBus.start_env()

            # Initialize the timing link
            self.DevPcie.I2cBus.setClk_119M()
            time.sleep(0.1)
            self.DevPcie.TimingFrameRx.C_RxPllReset()
            time.sleep(1.0)
            self.DevPcie.TimingFrameRx.C_BypassRst()
            self.DevPcie.Application.Base.resetFbPLL()
            time.sleep(1.0)
            self.DevPcie.Application.Base.resetFb()
            #self.DevPcie.Application.Base.resetDma()
            self.DevPcie.Application.Base.fmc0Rst()
            self.DevPcie.Application.Base.fmc1Rst()
            self.DevPcie.Application.Base.inhibit.set(0)
            time.sleep(1.0)
            self.DevPcie.TimingFrameRx.countReset()
            time.sleep(0.1)
            
            #fmc_init()
            self.DevPcie.I2cBus.set_i2c_mux('PrimaryFmc')
            self.DevPcie.I2cBus.FmcSpi.cpld_init()
            self.DevPcie.I2cBus.FmcSpi.clocktree_init('EXTREF',0,'_119M')

            #train_io(8)
            self.DevPcie.I2cBus.FmcSpi.adc_enable_test('Flash11')
            self.DevPcie.Application.AdcCore[0].train(8)
            self.DevPcie.I2cBus.FmcSpi.adc_disable_test()

            self.DevPcie.I2cBus.FmcSpi.adc_enable_test('Flash11')
            self.DevPcie.Application.AdcCore[0].loop_checking()
            self.DevPcie.I2cBus.FmcSpi.adc_disable_test()

            print('DevRoot start complete')
            

    # Function calls after loading YAML configuration
    def initialize(self):
        super().initialize()
        self.StopRun()
        self.CountReset()
