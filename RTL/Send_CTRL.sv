
`timescale 1ns / 1ps

module Send_CTRL #(
    // Accumulator address width
    parameter   ACC_ADDR_W = 4,
    // Accumulator size
    parameter   ACC_SIZE = 9
)(
    // Global clock signal
    input   wire                                clk,
    // Global active low reset signal
    input   wire                                rst,
    // Indicates next PE is ready for reciving data from this PE
    input   wire                                acc_done_in,
    // Counter for cooperation between receive and send part
    input   wire    [$clog2(ACC_SIZE+1)-1 : 0]  idx,
    // Indicates that address and data are valid
    output  reg                                 acc_valid_out,
    // Address for next PE from this PE
    output  wire    [ACC_ADDR_W-1 : 0]          acc_addr_out,
    // Init signal for idx counter
    output  reg                                 idx_init
);

    
    // FSM state parameters
    parameter   [0 : 0]     idle = 1'b0,
                            send = 1'b1;
                    
    
    // Reg and wire
    wire                        addr_co;
    reg                         addr_count;
    reg     [ACC_ADDR_W-1 : 0]  addr;
    wire                        lesser;
    
    
    // Counter for addressing acc
    always @(posedge clk) begin
        if(~rst) addr <= 'b0;
        else if(addr_count & addr_co) addr <= 'b0;
        else if(addr_count & ~addr_co) addr <= addr + 1'b1;
        else addr <= addr;
    end
    assign addr_co = (addr == ACC_SIZE-1);
    
    
    // Indicates value of acc[addr] is valid for sending
    assign lesser = (addr < idx);
    // Address for next PE
    assign acc_addr_out = addr;
    
    
    // FSM state registers
    reg [0 : 0] ps, ns;
    // FSM combinational part
    always @(ps, acc_done_in, addr_co, lesser) begin
        begin ns = idle; {acc_valid_out, idx_init, addr_count} = 'b0; end
        case(ps)
            idle:
                begin
                    ns = acc_done_in ? send : idle;
                end
            send:
                begin
                    ns = (addr_co & lesser) ? idle : send;
                    acc_valid_out = lesser;
                    idx_init = (addr_co & lesser);
                    addr_count = lesser;
                end
            default: begin ns = idle; {acc_valid_out, idx_init, addr_count} = 'b0; end
        endcase
    end
    
    
    // FSM sequential part
    always @(posedge clk) begin
        if (~rst) ps <= idle;
        else ps <= ns;
    end
    
    
endmodule
