import struct
import sys
import numpy as np
import matplotlib.pyplot as plt

if __name__ == '__main__':
    rom_fp = sys.argv[1]
    sprite_address = sys.argv[2]
    sprite_address = int(sprite_address, base=16)

    sprite = np.empty((8, 8))
    with open(rom_fp, 'rb') as fp:
        fp.seek(sprite_address)
        for bi in range(8):
            column = fp.read(1)[0]
            for i in range(8):
                sprite[i,bi] = ~(column & 1)
                column = column >> 1

    plt.imshow(sprite, cmap='gray')
    plt.show()
