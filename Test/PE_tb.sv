
`timescale 1ns / 1ps

module PE_tb();
    
    
    // Data width of each digit for activation
    parameter       A_W = 3;
    // Data width of each digit for weight
    parameter       W_W = 3;
    // SIMD factor
    parameter       SIMD = 4;
    // Ternary data width for activation            
    parameter       T_A_W = A_W * 2;
    // Ternary data width for weight
    parameter       T_W_W = W_W * 2;
    // Accumulator address width
    parameter       ACC_ADDR_W = $clog2(A_W * W_W);
    // Accumulator data width
    parameter       ACC_DATA_W = 8;
    // Number of SIMD computations in a window
    parameter       WIN_SIZE = 4;
    // Number of Tests
    parameter       TEST_NUM = 10;
    // Time period of clock frequency
    parameter       PERIOD = 100;
    
    
	// Global signals
	// Global clock signal
    reg    clk;
    // Global active low reset signal
    reg    rst;
    
    // Data and control signals
    // Input data bus for activation
    reg    [T_A_W-1 : 0]            a;
    // Input data bus for weight
    reg    [T_W_W-1 : 0]            w;
    // Validation signal for activation and weight
    reg                             aw_valid;
    // End of window synched with aw_valid
    reg                             eow;
    // Indicates that multiplication of SIMD * input is ready
    wire                            ready;

    // Interface with pre PE
    // Indicates this PE is ready for reciving data from pre PE
    wire                            acc_done_out;
    // Indicates that address and data are valid from pre PE
    reg                             acc_valid_in;
    // Address for this PE from pre PE
    reg     [ACC_ADDR_W-1 : 0]      acc_addr_in;
    // Data for this PE from pre PE
    reg     [ACC_DATA_W-1 : 0]      acc_data_in; 

    // Interface with next PE
    // Indicates next PE is ready for reciving data from this PE
    reg                             acc_done_in;
    // Indicates that address and data are valid
    wire                            acc_valid_out;
    // Address for next PE from this PE
    wire    [ACC_ADDR_W-1 : 0]      acc_addr_out;
    // Data for next PE from this PE
    wire    [ACC_DATA_W-1 : 0]      acc_data_out;
    
    
    // Instance of PE
    PE #(
        .A_W(A_W),
        .W_W(W_W),
        .SIMD(SIMD),
        .ACC_DATA_W(ACC_DATA_W)
    ) pe (
        .clk(clk),
        .rst(rst),
        .a(a),
        .w(w),
        .aw_valid(aw_valid),
        .eow(eow),
        .ready(ready),
        .acc_done_out(acc_done_out),
        .acc_valid_in(acc_valid_in),
        .acc_addr_in(acc_addr_in),
        .acc_data_in(acc_data_in),
        .acc_done_in(acc_done_in),
        .acc_valid_out(acc_valid_out),
        .acc_addr_out(acc_addr_out),
        .acc_data_out(acc_data_out)
    );
    
    // Variables
    int fd;
    int digit;
    int pe_result;
    int correct_result;
    int test_passed;
    realtime tic;
    realtime toc;
    reg [T_A_W-1 : 0] a_digit;
    reg [T_W_W-1 : 0] w_digit;
    
    // Generating clock signal
    initial begin
        clk = 0;
        forever #(PERIOD / 2) clk = ~clk;
    end
            
    
    // Test PE
    initial begin
        // Initializing signals
        rst = 0;
        aw_valid = 0;
        eow = 0;
        acc_valid_in = 1;
        acc_addr_in = 0;
        acc_data_in = 0;
        acc_done_in = 1;
        @(negedge clk);
        rst = 1;
        
        // Opening data file
        fd = $fopen("test.txt", "r");
        
        // Looping on test number
        for(int i = 0; i < TEST_NUM; i++) begin
            tic = $realtime;
            // Looping on window size
            for(int j = 0; j < WIN_SIZE; j++) begin
                // Setting aw_valid
                aw_valid = 1;
                // Setting eow
                if(j == WIN_SIZE-1) eow = 1;
                // Looping on SIMD value
                for(int k = 0; k < SIMD; k++) begin
                    a = 'b0;
                    // Looping on a-width
                    for(int m = 0; m < A_W; m++) begin
                        // Reading one digit from file
                        $fscanf(fd, "%d", digit);
                        // Converting decimal digit to ternary digit
                        a_digit = (digit == 1) ? 2'b11 : (digit == -1) ? 2'b10 : 2'b00;
                        // Save ternary digit in a-register
                        a = a + (a_digit << (2 * m));
                    end
                    w = 'b0;
                    // Looping on w-width
                    for(int m = 0; m < W_W; m++) begin
                        // Reading one digit from file
                        $fscanf(fd, "%d", digit);
                        // Converting decimal digit to ternary digit
                        w_digit = (digit == 1) ? 2'b11 : (digit == -1) ? 2'b10 : 2'b00;
                        // Save ternary digit in w-register
                        w = w + (w_digit << (2 * m));
                    end
                    @(negedge clk);
                end
                // Resetting aw_valid
                aw_valid = 0;
                // Resetting eow
                eow = 0;
                // Waiting for ready signal
                while(~ready) @(negedge clk);
            end
            
            toc = $realtime;
            
            @(negedge clk);
            
            // Comparing results
            test_passed = 1;
            for(int j = 0; j < A_W * W_W; j++) begin
                // Reading result from PE and convert to decimal
                pe_result = acc_data_out[ACC_DATA_W-1] ? acc_data_out - (1 << ACC_DATA_W) : acc_data_out;
                // Reading corresponding result from data file
                $fscanf(fd, "%d", correct_result);
                // Comparing to Read result
                if(pe_result != correct_result) test_passed = 0;
                @(negedge clk);
            end
            
            // Show result and time of test
            if(test_passed) begin
                // Test passed
                $display("Test %0d passed at %0t clock cycles", i + 1, (toc - tic) / PERIOD / 1000);
            end
            else begin
                // Test failed
                $display("Test %0d failed at %0t clock cycles", i + 1, (toc - tic) / PERIOD / 1000);
            end
        end
        
        // Closing data file
        $fclose(fd);
    end
    
    
endmodule
