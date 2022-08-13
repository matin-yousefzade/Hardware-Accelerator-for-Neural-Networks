import random as rd
import pandas as pd


# Data width of each digit for activation
A_W = 3
# Data width of each digit for weight
W_W = 3
# SIMD factor
SIMD = 4
# Number of SIMD computations in a window
WIN_SIZE = 4
# Number of Tests
TEST_NUM = 10


# Function for generate list all of ternary numbers with given width
def generate_ternary(width):
    if(width == 1):
        return [[0], [-1], [1]]
    else:
        res = []
        for i in generate_ternary(width - 1):
            res.append(i + [0])
        temp1 = [[-1], [1]]
        temp2 = []
        for i in range(width - 1):
            for j in temp1:
                temp2.append(j + [-1])
                temp2.append(j + [1])
            temp1 = temp2
            temp2 = []
        return res + temp1


# List all of ternary numbers with width A_W
a_list = generate_ternary(A_W)
# List all of ternary numbers with width W_W
w_list = generate_ternary(W_W)


# Looping on test number
for i in range(TEST_NUM):
    # List of random aw data
    aw_list = []
    # List of result of random aw data
    dot_product_list = [0] * (A_W * W_W)
    # Generating random aw data and result
    for j in range(WIN_SIZE * SIMD):
        a = rd.choice(a_list)
        w = rd.choice(w_list)
        aw_list.append(a + w)
        for k in range(A_W):
            for m in range(W_W):
                dot_product_list[k * W_W + m] += a[k] * w[m]


    # Writing aw data in file
    aw_df = pd.DataFrame(aw_list)
    if(i == 0):
        aw_df.to_csv('test.txt', header = False, index = False, sep = ' ')
    else:
        aw_df.to_csv('test.txt', header = False, index = False, sep = ' ', mode = 'a')


    # Writing result in file
    dot_product_df = pd.DataFrame([dot_product_list])
    dot_product_df.to_csv('test.txt', header = False, index = False, sep = ' ', mode = 'a')


print('Test data generated!')
