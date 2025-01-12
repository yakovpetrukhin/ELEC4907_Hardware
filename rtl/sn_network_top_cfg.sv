/*
    sn_network_top:
        Module used as the DUT for simulation. Contains all the network and peripheral logic.
*/
module sn_network_top_cfg 
    #(
      parameter P_NUM_NEURONS=5, // Includes inputs and outputs.
      parameter P_NUM_INPUTS=2,
      parameter P_NUM_OUTPUTS=1,
      parameter integer P_TABLE_NUM_ROWS_ARRAY [P_NUM_NEURONS-P_NUM_INPUTS:1] = {'0},
      parameter P_TABLE_MAX_NUM_ROWS=10,
      parameter integer P_NEUR_CONST_CURRENT_ARRAY [P_NUM_NEURONS-P_NUM_INPUTS:1] = {'0},
      parameter integer P_NEUR_CNTR_VAL_ARRAY [P_NUM_NEURONS:1] = {'0},
      parameter P_TABLE_DFLT_NUM_ROWS=4,
      parameter P_TABLE_WEIGHT_BW=7,
      parameter P_TABLE_WEIGHT_PRECISION=2,
      parameter P_NEUR_CURRENT_BW=P_TABLE_WEIGHT_BW+2, // Must be more than P_TABLE_WEIGHT_BW
      parameter P_NEUR_MODEL_PRECISION=10,
      parameter P_NEUR_IZH_HIGH_PREC_EN=0,
      parameter P_DFLT_CNTR_VAL=40,
      parameter P_NEUR_STEP_CNTR_BW=$clog2(P_DFLT_CNTR_VAL),
      parameter P_MAX_NUM_PERIODS=500,
      parameter P_NEUR_MODEL_CFG=0, // 0 for Izhikevich, 1 for integrate and fire.
      parameter P_UART_CLKS_PER_BIT=10, // Number of prot_clk clock cycles per bit on the UART interface. Depends on baudrate.
      parameter P_UART_BITS_PER_PKT=10, // Total number of bits per UART packet, including the start and end bits.
      parameter P_PROT_WATCHDOG_TIME=100, // Number of cycles until the HW watchdog timer expires.
      parameter P_USE_PROTOCOL2 = 1,
      parameter P_CLK_GEN_EN=1,
      localparam L_TABLE_IDX_BW=$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)
    )
    (
     // Top clock and reset.
     input clk_in1_p,
     input clk_in1_n,
     input rst,
     // UART signals
     input rx_input,
     output tx_output,
     // Simulation Signals (only used in simulation).
     input v_clk,
     output nc_evaluate_out,
     output logic [P_NUM_NEURONS:1] [P_NEUR_MODEL_PRECISION+(P_NEUR_MODEL_CFG==0?8:9)-1:0] v_out,
     output logic [P_NUM_NEURONS:1] [P_NEUR_MODEL_PRECISION+8-1:0] u_out,
     // CFG:
     input [P_NUM_NEURONS-P_NUM_INPUTS:1] [P_TABLE_MAX_NUM_ROWS-1:0] [P_TABLE_WEIGHT_BW+L_TABLE_IDX_BW-1:0] cfg_table_contents
    );

    // Declarations
    //-------------------
    // Clock
    logic clk;
    // Protocol interface
    logic prot_enable; // Enable all <prot_*> signals
    logic prot_r0w1; // 0=read operation, 1=write operation
    logic [7-1:0] prot_addr; // Register address for reading or writing
    logic [8-1:0] prot_wdata; // Data for writing
    logic [8-1:0] prot_rdata; // Data returned during a read. Valid when prot_enable=1 (i.e. no read latency).
    
    generate
        if (P_CLK_GEN_EN==1) begin: gen_clk_wiz
            // Clock Generation
            //-------------------
            clk_wiz_0 clk_wiz_0_i
            (
                .clk_in1_p(clk_in1_p),
                .clk_in1_n(clk_in1_n),
                .reset(rst),
                .clk(clk)
            );
        end else begin: gen_top_clk
            assign clk=v_clk;
        end
    endgenerate
    
    // Network
    //-------------------
    sn_network_cfg
    #(
        .P_NUM_NEURONS(P_NUM_NEURONS),
        .P_NUM_INPUTS(P_NUM_INPUTS),
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
        .P_TABLE_NUM_ROWS_ARRAY(P_TABLE_NUM_ROWS_ARRAY),
        .P_TABLE_MAX_NUM_ROWS(P_TABLE_MAX_NUM_ROWS),
        .P_NEUR_CONST_CURRENT_ARRAY(P_NEUR_CONST_CURRENT_ARRAY),
        .P_NEUR_CNTR_VAL_ARRAY(P_NEUR_CNTR_VAL_ARRAY),
        .P_TABLE_DFLT_NUM_ROWS(P_TABLE_DFLT_NUM_ROWS),
        .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
        .P_TABLE_WEIGHT_PRECISION(P_TABLE_WEIGHT_PRECISION),
        .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
        .P_NEUR_MODEL_PRECISION(P_NEUR_MODEL_PRECISION),
        .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN),
        .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
        .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
        .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS),
        .P_NEUR_MODEL_CFG(P_NEUR_MODEL_CFG)
    ) network_i (
        .clk(clk),
        .rst(rst),
        // Protocol Interface
        .prot_enable(prot_enable),
        .prot_r0w1(prot_r0w1),
        .prot_addr(prot_addr),
        .prot_wdata(prot_wdata),
        .prot_rdata(prot_rdata),
        // Simulation Signals (only used in simulation).
        .nc_evaluate_out(nc_evaluate_out),
        .v_out(v_out),
        .u_out(u_out),
        // CFG
        .cfg_table_contents(cfg_table_contents)
    );

    // Protocol Manager
    //-------------------
generate
    if (P_USE_PROTOCOL2==0) begin: gen_orig_prot
    
        sn_io_protocol
        #(
            .P_CLKS_PER_BIT(P_UART_CLKS_PER_BIT),
            .P_BITS_TO_SEND(P_UART_BITS_PER_PKT),
            .P_BITS_TO_RECEIVE(P_UART_BITS_PER_PKT),
            .P_PROT_WATCHDOG_TIME(P_PROT_WATCHDOG_TIME)
        ) io_protocol_i (
            .clk(clk),
            .rst(rst),
            // Input UART Interface
            .uart_rx(rx_input),
            .uart_tx(tx_output),
            // Protocol Interface
            .prot_enable(prot_enable),
            .prot_r0w1(prot_r0w1),
            .prot_addr(prot_addr),
            .prot_wdata(prot_wdata),
            .prot_rdata(prot_rdata)
        );
        
    end else begin: gen_prot2
        
        sn_io_protocol2
        #(
            .P_CLKS_PER_BIT(P_UART_CLKS_PER_BIT),
            .P_BITS_TO_SEND(P_UART_BITS_PER_PKT),
            .P_BITS_TO_RECEIVE(P_UART_BITS_PER_PKT),
            .P_NUM_NEURONS(P_NUM_NEURONS),
            .P_NUM_INPUTS(P_NUM_INPUTS),
            .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
            .P_PROT_WATCHDOG_TIME(P_PROT_WATCHDOG_TIME)
        ) io_protocol2_i (
            .clk(clk),
            .rst(rst),
            // Input UART Interface
            .uart_rx(rx_input),
            .uart_tx(tx_output),
            // Protocol Interface
            .prot_enable(prot_enable),
            .prot_r0w1(prot_r0w1),
            .prot_addr(prot_addr),
            .prot_wdata(prot_wdata),
            .prot_rdata(prot_rdata)
        );
        
    end
endgenerate

endmodule