
`timescale 1ns / 1ps

module Compute_CTRL #(
    // SIMD factor
    parameter   SIMD = 4
)(
    // Global clock signal
    input   wire                clk,
    // Global active low reset signal
    input   wire                rst,
    // Validation signal for activation and weight
    input   wire                aw_valid,
    // End of window synched with aw_valid
    input   wire                eow,
    // Indicates this PE is ready for reciving data from pre PE
    input   wire                acc_done_out,
    // Sign of next digit of a-input
    input   wire                a3,
    // Sign of next digit of w-input
    input   wire                w3,
    // Carry out of a-counter
    input   wire                a_co,
    // Carry out of w-counter
    input   wire                w_co,
    // Indicates result of inputs isn't zero
    input   wire                nz,
    // Indicates that multiplication of SIMD * input is ready
    output  reg                 ready,
    // Start signal for Receive_CTRL
    output  reg                 done,
    // Signal for toggling acc_sel register
    output  reg                 acc_sel_toggle,
    // Write signal from compute part
    output  reg                 compute_write,
    // Signal for control compute part
    // 3'h1 for load inputs
    // 3'h2 for shift inputs
    // 3'h3 for rotate inputs
    // 3'h4 for reset w-input to first data
    output  reg     [2 : 0]     ctrl
);
    
    
    // FSM state parameters
    parameter   [1 : 0]     idle = 2'h0,
                            store_data = 2'h1,
                            dot_product = 2'h2,
                            start_receive = 2'h3;
                        
    
    // Reg and wire
    wire                            co1;
    reg                             count1;
    reg     [$clog2(SIMD)-1 : 0]    cnt1;
    reg                             count2;
    reg     [$clog2(SIMD+1)-1 : 0]  cnt2;
    reg                             cnt_init;
    reg                             eow_ld;
    reg                             eow_reg;
    wire                            no_data;
    wire                            last_data;
          
    
    // Counter for looping on inputs
    always @(posedge clk) begin
        if(~rst) cnt1 <= 'b0;
        else if(cnt_init) cnt1 <= 'b0;
        else if(count1 & co1) cnt1 <= 'b0;
        else if(count1 & ~co1) cnt1 <= cnt1 + 1'b1;
        else cnt1 <= cnt1;
    end
    assign co1 = (cnt1 == SIMD-1);
    
    
    // Counter for saving number of not-zero inputs
    always @(posedge clk) begin
        if(~rst) cnt2 <= 'b0;
        else if(cnt_init) cnt2 <= 'b0;
        else if(count2) cnt2 <= cnt2 + 1'b1;
        else cnt2 <= cnt2;
    end
    
    
    // One-bit register for eow signal
    always @(posedge clk) begin
        if(~rst) eow_reg <= 1'b0;
        else if(eow_ld) eow_reg <= eow;
        else eow_reg <= eow_reg;
    end
    
    
    // Indicates there are no data for computing
    assign no_data = (cnt2 == 'b0);
    // Indicates last inputs are in-use
    assign last_data = ((cnt1 + 1'b1) == cnt2);
    
    
    // FSM state registers
    reg [1 : 0] ps, ns;
    // FSM combinational part
    always @(ps, aw_valid, acc_done_out, a3, w3, a_co, w_co, nz, co1, no_data, last_data) begin
        begin ns = idle; {ready, done, acc_sel_toggle, compute_write, ctrl, count1, count2, cnt_init, eow_ld} = 'b0; end
        case(ps)
            idle:
                begin
                    ns = aw_valid ? store_data : idle;
                    ready = ~aw_valid;
                    ctrl = (aw_valid & nz) ? 3'h1 : 3'h0;
                    count1 = aw_valid;
                    count2 = (aw_valid & nz);
                    eow_ld = aw_valid;
                end
            store_data:
                begin
                    ns = (co1 & aw_valid & (no_data & ~nz)) ? idle : (co1 & aw_valid) ? dot_product : store_data;
                    ctrl = (aw_valid & nz) ? 3'h1 : 3'h0;
                    count1 = aw_valid;
                    count2 = (aw_valid & nz);
                end
            dot_product:
                begin
                    compute_write = 1'b1;
                    case({a_co, w_co})
                        2'b00:
                            begin
                                ns = (eow_reg & (last_data & (~a3 & ~w3))) ? start_receive : (last_data & (~a3 & ~w3)) ? idle : dot_product;
                                ctrl = (~a3 & ~w3) ? 3'h2 : ~w3 ? 3'h3 : 3'h4;
                                count1 = (~a3 & ~w3);
                                cnt_init = (last_data & (~a3 & ~w3));
                            end
                        2'b01:
                            begin
                                ns = (eow_reg & (last_data & ~a3)) ? start_receive : (last_data & ~a3) ? idle : dot_product;
                                ctrl = ~a3 ? 3'h2 : 3'h3;
                                count1 = ~a3;
                                cnt_init = (last_data & ~a3);
                            end
                        2'b10:
                            begin
                                ns = (eow_reg & (last_data & ~w3)) ? start_receive : (last_data & ~w3) ? idle : dot_product;
                                ctrl = ~w3 ? 3'h2 : 3'h4;
                                count1 = ~w3;
                                cnt_init = (last_data & ~w3);
                            end
                        2'b11:
                            begin
                                ns = (eow_reg & last_data) ? start_receive : last_data ? idle : dot_product;
                                ctrl = 3'h2;
                                count1 = 1'b1;
                                cnt_init = last_data;
                            end
                    endcase
                end
            start_receive:
                begin
                    ns = ~acc_done_out ? idle : start_receive;
                    done = ~acc_done_out;
                    acc_sel_toggle = ~acc_done_out;
                end
            default: begin ns = idle; {ready, done, acc_sel_toggle, compute_write, ctrl, count1, count2, cnt_init, eow_ld} = 'b0; end
        endcase
    end
    
    
    // FSM sequential part
    always @(posedge clk) begin
        if (~rst) ps <= idle;
        else ps <= ns;
    end
    
    
endmodule
