`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/05/2023 09:44:45 AM
// Design Name: 
// Module Name: sn_io_protocol
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sn_io_protocol2
    #(
      parameter P_CLKS_PER_BIT=10, // Number of prot_clk clock cycles per bit on the UART interface. Depends on baudrate.
      parameter P_BITS_TO_SEND=10,
      parameter P_BITS_TO_RECEIVE=10,
      parameter P_PROT_WATCHDOG_TIME=100, // Number of cycles until the HW watchdog timer expires.
      parameter P_NUM_NEURONS=100,
      parameter P_NUM_INPUTS=23,
      parameter P_NUM_OUTPUTS=3
    )
    (
     // Top clock and reset.
     input clk,
     input rst,
     // UART signals
     output logic uart_tx,
     input uart_rx,
     //input cts_input,
     //output logic rts_output,
     // Protocol interface
     output logic prot_enable, // Enable all <prot_*> signals
     output logic prot_r0w1, // 0=read operation, 1=write operation
     output logic [7-1:0] prot_addr, // Register address for reading or writing
     output logic [8-1:0] prot_wdata, // Data for writing
     input [8-1:0] prot_rdata // Data returned during a read. Valid when prot_enable=1 (i.e. no read latency).
    );
    
    localparam byte L_TX_TO_START    = 8'hFF;
    localparam byte L_TX_TO_CONTINUE = 8'hFF;
    localparam byte L_TX_TO_STOP     = 8'h00;
    localparam byte L_TX_TO_LOAD_TIMESTEP = 8'h55; //0101_0101
    // IO for the instantiated modules uart_rx.sv and uart_tx.sv:
    logic [7:0] rx_word; // Output from uart_rx.sv
    logic [7:0] tx_word; // input into uart_tx.sv (output from a MUX whose inputs are prot_rdata and rx_word_r).
    logic rx_enable, tx_enable; // Inputs into uart_rx.sv and uart_tx.sv
    logic rx_done, tx_done; // Outputs from uart_rx.sv and uart_tx.sv telling the state machine when they are done tx/rx.
    
    sn_uart_rx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_RECEIVE(P_BITS_TO_RECEIVE))
    uart_rx_i (
        .clk(clk),
        .rst(rst),
        .rx_enable(rx_enable),
        .rx_input(uart_rx),
        .received_word(rx_word),
        .rx_done(rx_done));
     
     sn_uart_tx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_SEND(P_BITS_TO_SEND))
    uart_tx_i (
        .clk(clk),
        .rst(rst),
        .tx_enable(tx_enable),
        .data_to_pc(tx_word),
        .tx_output(uart_tx),
        .tx_done(tx_done));
    
    // Watchdog timer:
    logic watchdog_en;
    logic [$clog2(P_PROT_WATCHDOG_TIME+1)-1:0] watchdog_cnt;
    // Buffer for received_word from uart_rx.sv. This is used as a source for prot_r0w1 and prot_addr.
    // Input counter for the Write Inputs (WI) state loop.
    logic [$clog2(P_NUM_INPUTS+1)-1:0] input_cnt,input_cnt_nxt;
    // Output counter for the Read Outputs (RO) state loop.
    logic [$clog2(P_NUM_OUTPUTS)-1:0] output_cnt,output_cnt_nxt;
    // FSM states:
    typedef enum bit [$clog2(13)-1:0] {IDLE,
                            // Writing timestep (WT):
                            WT_MSB,WT_LSB,
                            // Write Input (WI) states:
                            WI_ADDR_MSB,WI_ADDR_LSB,
                            WI_DATA_2,WI_DATA_1,WI_DATA_0,
                            WI_WRITE,
                            // Execute and Poll (EP) states:
                            EP_START_EXE,
                            EP_READ_START,
                            // Read Outputs (RO) states:
                            RO_CNTR_SEL,
                            RO_TX_CNTR
                            // Read Debug Monitor (RM) states:
                            // TODO
                            } state_t; 
    state_t s, s_nxt;
    
    // All registers:
    //===============
    always_ff @(posedge clk) begin
        if (rst) begin
            s <= IDLE;
            watchdog_cnt <= '0;
            input_cnt <= 'd1;
            output_cnt <= '0;
        end else begin
            s <= s_nxt;
            if (watchdog_en)
                watchdog_cnt <= watchdog_cnt + $bits(watchdog_cnt)'(1'd1);
            else
                watchdog_cnt <= '0;
            input_cnt <= input_cnt_nxt;
            output_cnt <= output_cnt_nxt;
        end
    end
    
    // Next State Comb Logic:
    //========================
    always_comb begin
        // Default/else for all wires. They might be overridden later in the always_comb block.
        s_nxt = s;

        if (watchdog_cnt == $bits(watchdog_cnt)'(P_PROT_WATCHDOG_TIME))
            s_nxt <= IDLE;
        else case (s)
            // IDLE state. Waiting to start.
            IDLE:
                if (rx_done) begin
                    if (rx_word == L_TX_TO_START) s_nxt = WI_ADDR_MSB;
                    else if (rx_word == L_TX_TO_LOAD_TIMESTEP) s_nxt = WT_MSB;
                end

            // WT_MSB: wait for a transmission holding the MSB of the requested max timestep.
            WT_MSB:
                if (rx_done) s_nxt = WT_LSB;

            // WT_LSB: wait for a transmission holding the LSB of the requested max timestep.
            WT_LSB:
                s_nxt = IDLE;

            // WI_ADDR_MSB: write msb of address, which is the lsb of the input counter.
            WI_ADDR_MSB:
                s_nxt = WI_ADDR_LSB;
            
            // WI_ADDR_LSB: write lsb of address, which is the lsb of the input counter.
            WI_ADDR_LSB:
                s_nxt = WI_DATA_2;
            
            // WI_DATA_2: waiting for RX from computer that holds the MSB of the input current data.
            WI_DATA_2:
                if (rx_done) s_nxt = WI_DATA_1;
            
            // WI_DATA_1: waiting for RX from computer that holds the middle byte of the input current data.
            WI_DATA_1:
                if (rx_done) s_nxt = WI_DATA_0;
            
            // WI_DATA_0: waiting for RX from computer that holds the LSB of the input current data.
            //            if we're concluding the last input, then go to Execute and Poll states, otherwise
            //            restart the Write Inputs states.
            WI_DATA_0:
                if (rx_done) s_nxt = WI_WRITE;
            
            WI_WRITE:
                if (input_cnt == $bits(input_cnt)'(P_NUM_INPUTS)) s_nxt = EP_START_EXE;
                else s_nxt = WI_ADDR_MSB;
            
            // EP_START_EXE: write 1 to the start register to start execution and immediately go to EP_READ_START to poll.
            EP_START_EXE:
                s_nxt = EP_READ_START;
                
            // EP_READ_START: Wait for transmission from computer signalling that it wants to read the state of the start register.
            EP_READ_START:
                if (rx_done) begin
                    if (rx_word == L_TX_TO_CONTINUE && prot_rdata == 8'd0) s_nxt = RO_CNTR_SEL;
                    else if (rx_word == L_TX_TO_STOP) s_nxt = IDLE;
                end
            
            // RO_CNTR_SEL: Wait for transmission to continue from computer before reading a counter.
            //              In the background, when tx received, protocol interface sets the output counter to target.
            //              Revised to send a stream of output counters with no handshake: just go straight to RO_TX_CNTR when tx is done.
            RO_CNTR_SEL:
                if (tx_done) s_nxt = RO_TX_CNTR;
            
            // RO_TX_CNTR: Transmit the counter then immediately go to RO_READ_CNTR or IDLE depending on if it's the last counter.
            RO_TX_CNTR: 
                if (output_cnt == $bits(output_cnt)'(P_NUM_OUTPUTS-1)) s_nxt = IDLE;
                else s_nxt = RO_CNTR_SEL;
            default:;
        endcase
    end
    
    // Output/Internal Signal per-state logic:
    //=========================================
    always_comb begin
        // Default/else
        // ------------
        // Internal signals:
        //      Register next values:
        input_cnt_nxt = input_cnt;
        output_cnt_nxt = output_cnt;
        //      Comb logic:
        watchdog_en = 1'b0;
        tx_word = prot_rdata;
        rx_enable = 1'b1;
        tx_enable = 1'b0;
        // Protocol interface:
        prot_enable = 1'b0;
        prot_r0w1 = 1'b0;
        prot_addr = rx_word;
        prot_wdata = rx_word;
        
        case(s)
            // IDLE state. Waiting to start.
            IDLE:;

            // WT_MSB: wait for a transmission holding the MSB of the requested max timestep.
            WT_MSB:
                if (rx_done) begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd3;
                end else watchdog_en = 1'b1;

            // WT_LSB: wait for a transmission holding the LSB of the requested max timestep.
            WT_LSB:
                if (rx_done) begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd4;
                end else watchdog_en = 1'b1;
            
            // WI_ADDR_MSB: write MSB of address from the counter value.
            WI_ADDR_MSB:
                begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd6;
                    if (P_NUM_INPUTS>=2**8) prot_wdata = input_cnt[$bits(input_cnt)-1:8];
                end

            // WI_ADDR_LSB: write LSB of address from the counter value.
            WI_ADDR_LSB:
                begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd7;
                    prot_wdata = 8'(input_cnt);
                end
            
            // WI_DATA_2: waiting for RX from computer that holds the MSB of the input current data.
            WI_DATA_2:
                if (rx_done) begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd9;
                end else watchdog_en = 1'b1;
            
            // WI_DATA_1: waiting for RX from computer that holds the middle byte of the input current data.
            WI_DATA_1:
                if (rx_done) begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd10;
                end else watchdog_en = 1'b1;
            
            // WI_DATA_0: waiting for RX from computer that holds the LSB of the input current data.
            //            if we're concluding the last input, then go to Execute and Poll states, otherwise
            //            restart the Write Inputs states.
            WI_DATA_0:
                if (rx_done) begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd11;
                end else watchdog_en = 1'b1;
                
            WI_WRITE:
                begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd5;
                    prot_wdata = 8'd1;
                    if (input_cnt== $bits(input_cnt)'(P_NUM_INPUTS)) begin
                        input_cnt_nxt = $bits(input_cnt)'(1);
                    end else begin
                        input_cnt_nxt = input_cnt + $bits(input_cnt)'(1);
                    end
                end
                
            EP_START_EXE:
                begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd0;
                    prot_wdata = 8'd1;
                end
            
            // EP_READ_START: Wait for transmission from computer signalling that it wants to read the state of the start register.
            EP_READ_START:
                begin
                    // Continuously read the start bit:
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b0;
                    prot_addr = 7'd0;
                    // Transmit if we receive anything:
                    tx_enable = rx_done;
                end
            
            // RO_READ_CNTR: Wait for transmission to continue from computer before reading a counter.
            //               In the background, when tx received, protocol interface sets the output counter to target.
            RO_CNTR_SEL:
                begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b1;
                    prot_addr = 7'd12;
                    prot_wdata = 8'(output_cnt);
                end
            
            // RO_TX_CNTR: Transmit the counter then immediately go to RO_READ_CNTR or IDLE depending on if it's the last counter.
            RO_TX_CNTR:
                begin
                    prot_enable = 1'b1;
                    prot_r0w1 = 1'b0;
                    prot_addr = 7'd13;
                    tx_enable = 1'b1;
                    if (output_cnt== $bits(output_cnt)'(P_NUM_OUTPUTS-1)) output_cnt_nxt = '0;
                    else output_cnt_nxt = output_cnt + $bits(output_cnt)'(1);
                end
            
            default:;
        endcase
    end
endmodule

