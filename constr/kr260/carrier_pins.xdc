# ============================================================================
# kr260/carrier_pins.xdc -- PHYSICAL pin constraints for the KR260 rig.
# TEMPLATE: fill every PACKAGE_PIN below from AMD's official sources -- do
# not trust forum numbers blindly. Two files are authoritative:
#
#   XTP685 -- Kria K26 SOM master XDC (SOM connector -> XCK26 package pins)
#            download: "xtp685-kria-k26-som-xdc.zip" from the AMD
#            documentation portal (Kria K26 SOM board page)
#   XTP743 -- KR260 carrier card schematic (SFP+ cages, LEDs, buttons)
#   Also useful: the KR260 "carrier card XDC" files on the same portal, and
#   Vivado Board Awareness (board part xilinx.com:kr260_som:part0:1.1)
#
# Reported (verify!): the SFP+ GTH reference clock is 156.25 MHz on
# MGTREFCLK0_224 (package pins ~Y5/Y6 on XCK26). Confirm against XTP685
# for your carrier revision before locking.
# ============================================================================

# ---- SFP+ #0 (node-to-node Aurora link, GTH quad 224) -----------------------
# TX/RX lane pairs and reference clock: see XTP685 som240 connector map
# set_property PACKAGE_PIN <Y?>  [get_ports {aur_tx_p}]
# set_property PACKAGE_PIN <Y?>  [get_ports {aur_tx_n}]
# set_property PACKAGE_PIN <Y?>  [get_ports {aur_rx_p}]
# set_property PACKAGE_PIN <Y?>  [get_ports {aur_rx_n}]
# set_property PACKAGE_PIN Y6    [get_ports {aur_refclk_p}]   ;# MGTREFCLK0_224P (verify)
# set_property PACKAGE_PIN Y5    [get_ports {aur_refclk_n}]   ;# MGTREFCLK0_224N (verify)

# ---- PL clocks (if driven from carrier oscillators instead of PS FCLKs) ----
# set_property PACKAGE_PIN <> [get_ports clk_dsp_p]
# set_property PACKAGE_PIN <> [get_ports clk_dsp_n]

# ---- LEDs (heartbeat / status: pick from KR260 carrier XDC) ------------------
# set_property PACKAGE_PIN <> [get_ports {led[0]}]
# set_property PACKAGE_PIN <> [get_ports {led[1]}]
# set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]
