create_clock -period 10.000 -name clk_100mhz [get_ports CLK100MHZ]

create_clock -period 40.000 -name eth_rx_clk [get_ports eth_rx_clk]
create_clock -period 40.000 -name eth_tx_clk [get_ports eth_tx_clk]

set_input_delay -clock eth_rx_clk -max 30.000 [get_ports {eth_rxd[*] eth_rx_dv eth_rxerr}]
set_input_delay -clock eth_rx_clk -min 10.000 [get_ports {eth_rxd[*] eth_rx_dv eth_rxerr}]

set_false_path -to   [get_ports {eth_ref_clk eth_rstn eth_mdc eth_mdio uart_rxd_out led[*]}]
set_output_delay 0   [get_ports {eth_ref_clk eth_rstn eth_mdc eth_mdio uart_rxd_out led[*]}]
set_false_path -from [get_ports {ck_rst eth_mdio eth_col eth_crs}]
set_input_delay 0    [get_ports {ck_rst eth_mdio eth_col eth_crs}]

set_false_path -to   [get_ports {eth_txd[*] eth_tx_en}]
