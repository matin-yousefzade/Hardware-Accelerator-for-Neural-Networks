
`timescale 1ns / 1ps

module PE#(
	// Data width of each digit for activation
    parameter       A_W = 3,
    // Data width of each digit for weight
    parameter       W_W = 3,
    // SIMD factor
    parameter       SIMD = 4,
    // Ternary data width for activation            
    parameter       T_A_W = A_W * 2,
    // Ternary data width for weight
    parameter       T_W_W = W_W * 2,
    // Accumulator address width
    parameter       ACC_ADDR_W = $clog2(A_W * W_W),
    // Accumulator data width
    parameter       ACC_DATA_W = 8
)(
	// Global signals
	// Global clock signal
	input 	wire	clk,
	// Global active low reset signal
	input 	wire	rst,
	
	// Data and control signals
	// Input data bus for activation
	input	wire	[T_A_W-1 : 0] 	a,
	// Input data bus for weight
	input	wire	[T_W_W-1 : 0] 	w,
	// Validation signal for activation and weight
	input	wire					aw_valid,
	// End of window synched with aw_valid
	input	wire					eow,
	// Indicates that multiplication of SIMD * input is ready
	output	wire					ready,

	// Interface with pre PE
	// Indicates this PE is ready for reciving data from pre PE
	output 	wire 						acc_done_out,
	// Indicates that address and data are valid from pre PE
	input 	wire 						acc_valid_in,
	// Address for this PE from pre PE
	input 	wire 	[ACC_ADDR_W-1 : 0] 	acc_addr_in,
	// Data for this PE from pre PE
	input 	wire	[ACC_DATA_W-1 : 0] 	acc_data_in,	

	// Interface with next PE
	// Indicates next PE is ready for reciving data from this PE
	input 	wire 						acc_done_in,
	// Indicates that address and data are valid
	output 	wire 						acc_valid_out,
	// Address for next PE from this PE
	output 	wire 	[ACC_ADDR_W-1 : 0]	acc_addr_out,
	// Data for next PE from this PE
	output 	wire	[ACC_DATA_W-1 : 0] 	acc_data_out
);
    
    // Local parameters
    // a-register width
    parameter   A_REG_W = SIMD * T_A_W;
    // w-register width
    parameter   W_REG_W = (SIMD + 1) * T_W_W;
    // Accumulator size
    parameter   ACC_SIZE = A_W * W_W;
    
    // Reg and wire
    wire                                a_co;
    reg     [ACC_ADDR_W-1 : 0]          a_addr;
    wire                                w_co;
    reg     [ACC_ADDR_W-1 : 0]          w_addr;
    wire    [ACC_ADDR_W-1 : 0]          compute_addr;
    reg     [A_REG_W-1 : 0]             a_reg;
    reg     [W_REG_W-1 : 0]             w_reg;
    wire                                nz;
    wire                                mult;
    wire                                compute_write;
    wire    [2 : 0]                     ctrl;
    wire    [ACC_DATA_W-1 : 0]          compute_data0;
    wire    [ACC_DATA_W-1 : 0]          compute_data1;
    wire                                done;
    wire                                receive_write;
    wire    [ACC_DATA_W-1 : 0]          receive_data0;
    wire    [ACC_DATA_W-1 : 0]          receive_data1;
    wire                                acc_sel_toggle;
    reg                                 acc_sel;
    reg     [ACC_SIZE-1 : 0]            acc0_valid;
    reg     [ACC_SIZE-1 : 0]            acc1_valid;
    reg     [ACC_DATA_W-1 : 0]          acc0                [0 : ACC_SIZE-1];
    reg     [ACC_DATA_W-1 : 0]          acc1                [0 : ACC_SIZE-1];
    wire                                idx_init;
    wire                                idx_count;
    wire                                idx_zero;
    wire                                idx_full;
    reg     [$clog2(ACC_SIZE+1)-1 : 0]  idx;
    
    
    ///////////////////////////////////////////////////
    // Compute
    ///////////////////////////////////////////////////
    
    // Counter for a-register
    always @(posedge clk) begin
        if(~rst) begin
            a_addr <= 'b0;
        end
        else begin
            case(ctrl)
                3'h2: a_addr <= 'b0;
                3'h3: a_addr <= a_addr + W_W;
                default: a_addr <= a_addr;
            endcase
        end
    end
    assign a_co = (a_addr == (A_W-1)*W_W);
    
    
    // Counter for w-register
    always @(posedge clk) begin
        if(~rst) begin
            w_addr <= 'b0;
        end
        else begin
            case(ctrl)
                3'h2: w_addr <= 'b0;
                3'h3: w_addr <= 'b0;
                3'h4: w_addr <= w_addr + 1'b1;
                default: w_addr <= w_addr;
            endcase
        end
    end
    assign w_co = (w_addr == W_W-1);
        
    
    // Register for a-inputs
    always @(posedge clk) begin
        if(~rst) begin
            a_reg <= 'b0;
        end
        else begin
            case(ctrl)
                // Load inputs
                3'h1: a_reg <= {a_reg[A_REG_W-1-T_A_W : 0], a};
                // Shift inputs
                3'h2: a_reg <= {{T_A_W{1'b0}}, a_reg[A_REG_W-1 : T_A_W]};
                // Rotate in-use data
                3'h3: a_reg <= {a_reg[A_REG_W-1 : T_A_W], a_reg[1 : 0], a_reg[T_A_W-1 : 2]};
                default: a_reg <= a_reg;
            endcase
        end
    end
                    
    
    // Register for w-inputs
    always @(posedge clk) begin
        if(~rst) begin
            w_reg <= 'b0;
        end
        else begin
            case(ctrl)
                // Load inputs
                3'h1: w_reg <= {w_reg[W_REG_W-1-T_W_W : T_W_W], w, w};
                // Shift inputs
                3'h2: w_reg <= {{T_W_W{1'b0}}, w_reg[W_REG_W-1 : 2*T_W_W], w_reg[3*T_W_W-1 : 2*T_W_W]};
                // Rotate in-use data
                3'h3: w_reg <= {w_reg[W_REG_W-1 : T_W_W], w_reg[2*T_W_W-1 : T_W_W]};
                // Reset in-use data to first value
                3'h4: w_reg <= {w_reg[W_REG_W-1 : T_W_W], w_reg[1 : 0], w_reg[T_W_W-1 : 2]};
                default: w_reg <= w_reg;
            endcase
        end
    end
    
    // Indicates result of inputs isn't zero
    assign nz = (a[1] & w[1]);
    // Multiplication of last significant digits
    assign mult = a_reg[0] ~^ w_reg[0];
    // Address that computed data must be writen
    assign compute_addr = a_addr + w_addr;
    // Computed data for acc0
    assign compute_data0 = (acc0_valid[compute_addr] & mult) ? acc0[compute_addr] + 1'b1 : (acc0_valid[compute_addr] & ~mult) ? acc0[compute_addr] - 1'b1 : mult ? 1'b1 : -1'b1;
    // Computed data for acc1
    assign compute_data1 = (acc1_valid[compute_addr] & mult) ? acc1[compute_addr] + 1'b1 : (acc1_valid[compute_addr] & ~mult) ? acc1[compute_addr] - 1'b1 : mult ? 1'b1 : -1'b1;
    
    
    // Instance of Compute_CTRL
    Compute_CTRL #(
        .SIMD(SIMD)
    ) compute_ctrl (
        .clk(clk),
        .rst(rst),
        .aw_valid(aw_valid),
        .eow(eow),
        .acc_done_out(acc_done_out),
        .a3(a_reg[3]),
        .w3(w_reg[3]),
        .a_co(a_co),
        .w_co(w_co),
        .nz(nz),
        .ready(ready),
        .done(done),
        .acc_sel_toggle(acc_sel_toggle),
        .compute_write(compute_write),
        .ctrl(ctrl)
    );
    
    
    ///////////////////////////////////////////////////
    // Receive CTRL
    ///////////////////////////////////////////////////
    
    // Counter for cooperation between receive and send part
    always @(posedge clk) begin
        if(~rst) idx <= 'b0;
        else if(idx_init) idx <= 'b0;
        else if(idx_count) idx <= idx + 1'b1;
        else idx <= idx;
    end
    assign idx_zero = (idx == 'b0);
    assign idx_full = (idx == ACC_SIZE-1);
    
    // Receive data for acc0
    assign receive_data0 = acc0[acc_addr_in] + acc_data_in;
    // Receive data for acc1
    assign receive_data1 = acc1[acc_addr_in] + acc_data_in;
    
    
    // Instance of Receive_CTRL
    Receive_CTRL receive_ctrl(
        .clk(clk),
        .rst(rst),
        .acc_valid_in(acc_valid_in),
        .done(done),
        .idx_zero(idx_zero),
        .idx_full(idx_full),
        .acc_done_out(acc_done_out),
        .receive_write(receive_write),
        .idx_count(idx_count)
    );
    
    
    ///////////////////////////////////////////////////
    // Send CTRL
    ///////////////////////////////////////////////////
    
    // Data for next PE
    assign acc_data_out = acc_sel ? acc0[acc_addr_out] : acc1[acc_addr_out];
        
    // Instance of Send_CTRL
    Send_CTRL #(
        .ACC_ADDR_W(ACC_ADDR_W),
        .ACC_SIZE(ACC_SIZE)
    ) send_ctrl (
        .clk(clk),
        .rst(rst),
        .acc_done_in(acc_done_in),
        .idx(idx),
        .acc_valid_out(acc_valid_out),
        .acc_addr_out(acc_addr_out),
        .idx_init(idx_init)
    );
    
    
    ///////////////////////////////////////////////////
    // Accumulator
    ///////////////////////////////////////////////////
    
    // One-bit register for acc addressing
    always @(posedge clk) begin
        if(~rst) acc_sel <= 1'b0;
        else if(acc_sel_toggle) acc_sel <= ~acc_sel;
        else acc_sel <= acc_sel;
    end
    
    
    // Validation register for reseting acc0
    always @(posedge clk) begin
        if(~rst) acc0_valid <= 'b0;
        else if(acc_sel_toggle & acc_sel) acc0_valid <= 'b0;
        else if(~acc_sel & compute_write) acc0_valid[compute_addr] <= 1'b1;
        else acc0_valid <= acc0_valid;
    end
    
    
    // Validation register for reseting acc1
    always @(posedge clk) begin
        if(~rst) acc1_valid <= 'b0;
        else if(acc_sel_toggle & ~acc_sel) acc1_valid <= 'b0;
        else if(acc_sel & compute_write) acc1_valid[compute_addr] <= 1'b1;
        else acc1_valid <= acc1_valid;
    end
    
    
    // Writing data in acc0
    always @(posedge clk) begin
        if(~acc_sel & compute_write) begin
            // Writing data in acc0 from compute part
            acc0[compute_addr] <= compute_data0;
        end
        else if(acc_sel & receive_write) begin
            // Writing data in acc0 from receive part
            acc0[acc_addr_in] <= receive_data0;
        end
    end
    
    
    // Writing data in acc1
    always @(posedge clk) begin
        if(acc_sel & compute_write) begin
            // Writing data in acc1 from compute part
            acc1[compute_addr] <= compute_data1;
        end
        else if(~acc_sel & receive_write) begin
            // Writing data in acc1 from receive part
            acc1[acc_addr_in] <= receive_data1;
        end
    end
      
    
endmodule
