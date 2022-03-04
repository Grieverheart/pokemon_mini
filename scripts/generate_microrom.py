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
        # @todo: The current parsing does not allow for comments!
        # @todo: Perhaps it's nice to be able to annotate the localparams to
        # modify the number of bits/value, e.g. it would be nice to change
        # MICRO_ALU_OP_NONE to be 7'd0 so that we do not have to define the alu
        # size and flag updating explicitly.
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

def num_string_to_binary_string(x):

    if '\'' in x:
        num_bits, value = x.split('\'')
        num_bits = int(num_bits)
        format, value = value[0], value[1:]
        if format == 'd':
            value = int(value)
        elif format == 'h':
            value = int(value, base=16)
        elif format == 'b':
            value = int(value, base=2)
        else:
            print("Couldn't decode x:", x)
            return x

        value = bin(value)[2:].zfill(num_bits)

        return value

    x = bin(int(x))[2:]
    return x

if __name__ == '__main__':
    microinstruction_width = 32
    rom_bits = 9

    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '../'))

    localparam_dict = read_localparams(os.path.join(root, 'rtl/s1c88.sv'))

    lines = open(os.path.join(root, 'rom/microinstructions.txt'), 'r').readlines()

    addresses = [-1] * 768
    rom = []
    microinstruction_address = 0
    num_opcodes_implemented = 0
    for line in lines:
        line = line.strip()

        comment_start = line.find('//')
        if comment_start > -1:
            line = line[:comment_start].strip()

        if len(line) == 0:
            continue

        if line[0] == '#':
            if line[1:] == 'default':
                for i in range(len(addresses)):
                    if addresses[i] == -1:
                        addresses[i] = microinstruction_address
            else:
                num_opcodes_implemented += 1
                opcode = int(line[1:], base=16)
                if opcode >= 0xCF00:
                    opcode = 0x200 | opcode & 0xFF
                elif opcode >= 0xCE00:
                    opcode = 0x100 | opcode & 0xFF

                addresses[opcode] = microinstruction_address
        else:
            microcommands = line.split(' ')
            microcommands = [
                    localparam_dict[x] if x in localparam_dict else
                    num_string_to_binary_string(x)
                    for x in microcommands]

            command = ''.join(microcommands)
            assert(len(command) == microinstruction_width)
            rom.append(command)
            microinstruction_address += 1

    print('%d/608 opcodes implemented.' % num_opcodes_implemented)

    rom = '\n'.join([hex(int(x, base=2))[2:] for x in rom])
    addresses = '\n'.join([hex(int(bin(x)[2:].zfill(rom_bits)[:9], base=2))[2:] for x in addresses])

    with open('translation_rom.mem', 'w') as fp:
        fp.write(addresses)

    with open('rom.mem', 'w') as fp:
        fp.write(rom)

