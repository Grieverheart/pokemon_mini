import os

# @warning: This is not a full-fledged verilog parser and might fail in certain
# cases. Use with caution.
def read_localparams(filepath):
    text = open(filepath, 'r').read()
    localparam_dict= {}
    while True:
        text = text.lstrip()

        if len(text) == 0:
            break

        while text.startswith('//'):
            newline_pos = text.find('\n')
            if newline_pos == -1:
                text = ""
                break
            text = text[newline_pos+1:]
            text = text.lstrip()

        if len(text) == 0:
            break

        if text.startswith('/*'):
            endcomment_pos = text.find('*/')
            if endcomment_pos == -1:
                text = ""
                break
            text = text[endcomment_pos+1:]
            text = text.lstrip()

        endcommand_pos = text.find(';')
        if endcommand_pos == -1:
            text = ""
            break

        command = text[0:endcommand_pos]
        if command.startswith('localparam'):
            command = command.strip().replace('\n', '').replace(' ', '')
            if command.find('[') != -1:
                command = command[15:]
            else:
                command = command[10:]

            if command.startswith('MICRO_'):
                parts = command.split(',')
                for part in parts:
                    name, value = part.split('=')
                    if "'" in value:
                        bits, value = value.split("'")
                        if value[0] == 'b':
                            value = value[1:]
                        elif value[0] == 'h':
                            value = bin(int(value[1:], base=16))[2:].zfill(int(bits))
                        elif value[0] == 'd':
                            value = bin(int(value[1:]))[2:].zfill(int(bits))
                        else:
                            print("Cannot read value in %s" % part)
                    else:
                        print('Not implemented %s' % command)

                    localparam_dict[name[6:]] = value

        text = text[endcommand_pos+1:]

    return localparam_dict

if __name__ == '__main__':
    microinstruction_width = 32
    rom_bits = 9

    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '../'))

    localparam_dict = read_localparams(os.path.join(root, 'rtl/s1c88.sv'))

    lines = open(os.path.join(root, 'rom/microinstructions.txt'), 'r').readlines()

    addresses = [0] * 768
    rom = []
    microinstruction_address = 0
    for line in lines:
        line = line.strip()

        if len(line) == 0 or line.startswith('//'):
            continue

        if line[0] == '#':
            if line[1:] == 'default':
                opcode = 0
            else:
                opcode = int(line[1:], base=16)
                if opcode >= 0xCF00:
                    opcode = 0x200 | opcode & 0xFF
                elif opcode >= 0xCE00:
                    opcode = 0x100 | opcode & 0xFF

            addresses[opcode] = microinstruction_address
        else:
            microcommands = line.split(' ')
            microcommands = [localparam_dict[x] if x in localparam_dict else x for x in microcommands]
            command = ''.join(microcommands)
            assert(len(command) == microinstruction_width)
            rom.append(command)
            microinstruction_address += 1

    rom = '\n'.join([hex(int(x, base=2))[2:] for x in rom])
    addresses = '\n'.join([hex(int(bin(x)[2:].zfill(rom_bits)[:9], base=2))[2:] for x in addresses])

    with open('translation_rom.mem', 'w') as fp:
        fp.write(addresses)

    with open('rom.mem', 'w') as fp:
        fp.write(rom)

