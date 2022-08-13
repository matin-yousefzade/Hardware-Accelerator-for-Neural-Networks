
`timescale 1ns / 1ps

module Receive_CTRL (
    // Global clock signal
    input   wire    clk,
    // Global active low reset signal
    input   wire    rst,
    // Indicates that address and data are valid from pre PE
    input   wire    acc_valid_in,
    // Start signal for Receive_CTRL
    input   wire    done,
    // Indicates that idx counter is zero
    input   wire    idx_zero,
    // Indicates that idx counter is full
    input   wire    idx_full,
    // Indicates this PE is ready for reciving data from pre PE
    output  reg     acc_done_out,
    // Write signal from receive part
    output  reg     receive_write,
    // Count signal for idx counter
    output  reg     idx_count
);

    
    // FSM state parameters
    parameter   [0 : 0]     idle = 1'b0,
                            receive = 1'b1;
                        
    
    // FSM state registers
    reg [0 : 0] ps, ns;
    // FSM combinational part
    always @(ps, acc_valid_in, done, idx_zero, idx_full) begin
        begin ns = idle; {acc_done_out, receive_write, idx_count} = 'b0; end
        case(ps)
            idle:
                begin
                    ns = (done & idx_zero) ? receive : idle;
                end
            receive:
                begin
                    ns = (acc_valid_in & idx_full) ? idle : receive;
                    acc_done_out = 1'b1;
                    receive_write = acc_valid_in;
                    idx_count = acc_valid_in;
                end
            default: begin ns = idle; {acc_done_out, receive_write, idx_count} = 'b0; end
        endcase
    end
    
    
    // FSM sequential part
    always @(posedge clk) begin
        if (~rst) ps <= idle;
        else ps <= ns;
    end
    
    
endmodule
