#include "Vminx.h"
#include "Vminx___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstring>
#include <cstdint>

#include "instruction_cycles.h"

#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>
#include "gl_utils.h"

#define VERBOSE 1

#if VERBOSE == 0
#define PRINTE(...) do{ } while ( false )
#define PRINTD(...) do{ } while ( false )
#elif VERBOSE == 1
#define PRINTE(...) do{ fprintf( stderr, __VA_ARGS__ ); } while( false )
#define PRINTD(...) do{ } while ( false )
#else
#define PRINTE(...) do{ fprintf( stderr, __VA_ARGS__ ); } while( false )
#define PRINTD(...) do{ fprintf( stdout, __VA_ARGS__ ); } while( false )
#endif


enum
{
    BUS_IDLE      = 0x0,
    BUS_IRQ_READ  = 0x1,
    BUS_MEM_WRITE = 0x2,
    BUS_MEM_READ  = 0x3
};

uint32_t sec_cnt = 0;
uint8_t sec_ctrl = 0;
uint32_t prc_map = 0;
uint8_t prc_mode = 0;
uint8_t prc_rate = 0;

int prc_state = 0;
bool data_sent = false;
bool irq_processing = false;
int irq_render_done_old = 0;
int irq_copy_complete_old = 0;
int num_cycles_since_sync = 0;

bool gl_renderer_init(int buffer_width, int buffer_height)
{
    GLenum err = glewInit();
    if(err != GLEW_OK)
    {
        fprintf(stderr, "Error initializing GLEW.\n");
        return false;
    }

    int glVersion[2] = {-1, 1};
    glGetIntegerv(GL_MAJOR_VERSION, &glVersion[0]);
    glGetIntegerv(GL_MINOR_VERSION, &glVersion[1]);

    gl_debug(__FILE__, __LINE__);

    printf("Using OpenGL: %d.%d\n", glVersion[0], glVersion[1]);
    printf("Renderer used: %s\n", glGetString(GL_RENDERER));
    printf("Shading Language: %s\n", glGetString(GL_SHADING_LANGUAGE_VERSION));

    glClearColor(1.0, 0.0, 0.0, 1.0);

    // Create texture for presenting buffer to OpenGL
    GLuint buffer_texture;
    glGenTextures(1, &buffer_texture);
    glBindTexture(GL_TEXTURE_2D, buffer_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, buffer_width, buffer_height, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);


    // Create vao for generating fullscreen triangle
    GLuint fullscreen_triangle_vao;
    glGenVertexArrays(1, &fullscreen_triangle_vao);


    // Create shader for displaying buffer
    static const char* fragment_shader =
        "\n"
        "#version 330\n"
        "\n"
        "uniform sampler2D buffer;\n"
        "noperspective in vec2 TexCoord;\n"
        "\n"
        "out vec3 outColor;\n"
        "\n"
        "void main(void){\n"
        "    float val = texture(buffer, TexCoord).r;\n"
        "    outColor = ((val > 0.5)? 1.0: 0.2) * vec3(0.611, 0.694, 0.611);\n"
        "}\n";

    static const char* vertex_shader =
        "\n"
        "#version 330\n"
        "\n"
        "noperspective out vec2 TexCoord;\n"
        "\n"
        "void main(void){\n"
        "\n"
        "    TexCoord.x = (gl_VertexID == 2)? 2.0: 0.0;\n"
        "    TexCoord.y = (gl_VertexID == 1)? 2.0: 0.0;\n"
        "    \n"
        "    gl_Position = vec4(2.0 * TexCoord - 1.0, 0.0, 1.0);\n"
        "}\n";

    GLuint shader_id = glCreateProgram();

    {
        //Create vertex shader
        GLuint shader_vp = glCreateShader(GL_VERTEX_SHADER);

        glShaderSource(shader_vp, 1, &vertex_shader, 0);
        glCompileShader(shader_vp);
        validate_shader(shader_vp, vertex_shader);
        glAttachShader(shader_id, shader_vp);

        glDeleteShader(shader_vp);
    }

    {
        //Create fragment shader
        GLuint shader_fp = glCreateShader(GL_FRAGMENT_SHADER);

        glShaderSource(shader_fp, 1, &fragment_shader, 0);
        glCompileShader(shader_fp);
        validate_shader(shader_fp, fragment_shader);
        glAttachShader(shader_id, shader_fp);

        glDeleteShader(shader_fp);
    }

    glLinkProgram(shader_id);

    if(!validate_program(shader_id)){
        fprintf(stderr, "Error while validating shader.\n");
        glDeleteVertexArrays(1, &fullscreen_triangle_vao);
        return false;
    }

    glUseProgram(shader_id);

    GLint location = glGetUniformLocation(shader_id, "buffer");
    glUniform1i(location, 0);


    //OpenGL setup
    glDisable(GL_DEPTH_TEST);
    glActiveTexture(GL_TEXTURE0);

    glBindVertexArray(fullscreen_triangle_vao);

    return true;
}

void gl_renderer_draw(int buffer_width, int buffer_height, void* buffer_data)
{
    glTexSubImage2D(
        GL_TEXTURE_2D, 0, 0, 0,
        buffer_width, buffer_height,
        GL_RED, GL_UNSIGNED_BYTE,
        buffer_data
    );
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

void write_hardware_register(uint8_t* registers, uint32_t address, uint8_t data)
{
    switch(address)
    {
        case 0x00:
        case 0x01:
        case 0x02:
        {
            PRINTD("Writing hardware register SYS_CTRL%d=", address+1);
        }
        break;

        case 0x08:
        {
            PRINTD("Writing hardware register SEC_CTRL=");
            sec_ctrl = data & 3;
        }
        break;

        case 0x10:
        {
            PRINTD("Writing hardware register SYS_BATT=");
        }
        break;

        case 0x18:
        case 0x19:
        case 0x1A:
        case 0x1B:
        case 0x1C:
        case 0x1D:
        {
            PRINTD("Writing hardware register TMR%d_%s=", (address - 0x16) / 2, (address % 2)? "OSC": "SCALE");
        }
        break;

        case 0x20:
        case 0x21:
        case 0x22:
        {
            PRINTD("Writing hardware register IRQ_PRI%d=", address - 0x1F);
        }
        break;

        case 0x23:
        case 0x24:
        case 0x25:
        case 0x26:
        {
            PRINTD("Writing hardware register IRQ_ENA%d=", address - 0x22);
        }
        break;

        case 0x27:
        case 0x28:
        case 0x29:
        case 0x2A:
        {
            PRINTD("Writing hardware register IRQ_ACT%d=", address - 0x26);
            data = registers[address] & ~data;
        }
        break;

        case 0x30:
        case 0x31:
        case 0x38:
        case 0x39:
        case 0x48:
        case 0x49:
        {
            PRINTD("Writing hardware register TMR%d_CTRL_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
        }
        break;

        case 0x32:
        case 0x33:
        case 0x3A:
        case 0x3B:
        case 0x4A:
        case 0x4B:
        {
            PRINTD("Writing hardware register TMR%d_PRE_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
        }
        break;

        case 0x34:
        case 0x35:
        case 0x3C:
        case 0x3D:
        {
            PRINTD("Writing hardware register TMR%d_PVT_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
        }
        break;

        case 0x40:
        {
            PRINTD("Writing hardware register TMR256_CTRL=");
        }
        break;

        case 0x41:
        {
            PRINTD("Writing hardware register TMR256_CNT=");
        }
        break;

        case 0x60:
        {
            PRINTD("Writing hardware register IO_DIR=");
        }
        break;

        case 0x61:
        {
            PRINTD("Writing hardware register IO_DATA=");
        }
        break;

        case 0x70:
        {
            PRINTD("Writing hardware register AUD_CTRL=");
        }
        break;

        case 0x71:
        {
            PRINTD("Writing hardware register AUD_VOL=");
        }
        break;

        case 0x80:
        {
            PRINTD("Writing hardware register PRC_MODE=");
            prc_mode = data & 0x3F;
        }
        break;

        case 0x81:
        {
            PRINTD("Writing hardware register PRC_RATE=");
            if((prc_rate & 0xE) != (data & 0xE)) prc_rate = data & 0xF;
            else prc_rate = (prc_rate & 0xF0) | (data & 0x0F);
        }
        break;

        case 0x82:
        {
            PRINTD("Writing hardware register PRC_MAP_LO=");
            prc_map = (prc_map & 0xFFFFF00) | (data & 0xFF);
        }
        break;

        case 0x83:
        {
            PRINTD("Writing hardware register PRC_MAP_MID=");
            prc_map = (prc_map & 0xFFF00FF) | ((data & 0xFF) << 8);
        }
        break;

        case 0x84:
        {
            PRINTD("Writing hardware register PRC_MAP_HI=");
            prc_map = (prc_map & 0xF00FFFF) | ((data & 0xFF) << 16);
        }
        break;

        case 0x85:
        {
            PRINTD("Writing hardware register PRC_SCROLL_Y=");
        }
        break;

        case 0x86:
        {
            PRINTD("Writing hardware register PRC_SCROLL_X=");
        }
        break;

        case 0x87:
        {
            PRINTD("Writing hardware register PRC_SPR_LO=");
        }
        break;

        case 0x88:
        {
            PRINTD("Writing hardware register PRC_SPR_MID=");
        }
        break;

        case 0x89:
        {
            PRINTD("Writing hardware register PRC_SPR_HI=");
        }
        break;

        case 0xFE:
        {
            switch(data) {
                case 0x00: case 0x01: case 0x02: case 0x03: case 0x04: case 0x05: case 0x06: case 0x07:
                case 0x08: case 0x09: case 0x0A: case 0x0B: case 0x0C: case 0x0D: case 0x0E: case 0x0F:
                    PRINTD("LCD_CTRL: Set column low.\n");
                    break;
                case 0x10: case 0x11: case 0x12: case 0x13: case 0x14: case 0x15: case 0x16: case 0x17:
                case 0x18: case 0x19: case 0x1A: case 0x1B: case 0x1C: case 0x1D: case 0x1E: case 0x1F:
                    PRINTD("LCD_CTRL: Set column high.\n");
                    break;
                case 0x20: case 0x21: case 0x22: case 0x23: case 0x24: case 0x25: case 0x26: case 0x27:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x28: case 0x29: case 0x2A: case 0x2B: case 0x2C: case 0x2D: case 0x2E: case 0x2F:
                    // Modify LCD voltage? (2F Default)
                    // 0x28 = Blank
                    // 0x29 = Blank
                    // 0x2A = Blue screen then blank
                    // 0x2B = Blank
                    // 0x2C = Blank
                    // 0x2D = Blank
                    // 0x2E = Blue screen (overpower?)
                    // 0x2F = Normal
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37:
                case 0x38: case 0x39: case 0x3A: case 0x3B: case 0x3C: case 0x3D: case 0x3E: case 0x3F:
                    // Do nothing?
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45: case 0x46: case 0x47:
                case 0x48: case 0x49: case 0x4A: case 0x4B: case 0x4C: case 0x4D: case 0x4E: case 0x4F:
                case 0x50: case 0x51: case 0x52: case 0x53: case 0x54: case 0x55: case 0x56: case 0x57:
                case 0x58: case 0x59: case 0x5A: case 0x5B: case 0x5C: case 0x5D: case 0x5E: case 0x5F:
                case 0x60: case 0x61: case 0x62: case 0x63: case 0x64: case 0x65: case 0x66: case 0x67:
                case 0x68: case 0x69: case 0x6A: case 0x6B: case 0x6C: case 0x6D: case 0x6E: case 0x6F:
                case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x76: case 0x77:
                case 0x78: case 0x79: case 0x7A: case 0x7B: case 0x7C: case 0x7D: case 0x7E: case 0x7F:
                    // Set starting LCD scanline (cause warp around)
                    PRINTD("LCD_CTRL: Display start line\n");
                    break;
                case 0x80:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0x81:
                    PRINTD("LCD_CTRL: Set contrast\n");
                    break;
                case 0x82: case 0x83: case 0x84: case 0x85: case 0x86: case 0x87:
                case 0x88: case 0x89: case 0x8A: case 0x8B: case 0x8C: case 0x8D: case 0x8E: case 0x8F:
                case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: case 0x97:
                case 0x98: case 0x99: case 0x9A: case 0x9B: case 0x9C: case 0x9D: case 0x9E: case 0x9F:
                    // Do nothing?
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xA0:
                    // Segment Driver Direction Select: Normal
                    PRINTD("LCD_CTRL: Segment driver direction normal\n");
                    break;
                case 0xA1:
                    // Segment Driver Direction Select: Reverse
                    PRINTD("LCD_CTRL: Segment driver direction reverse\n");
                    break;
                case 0xA2:
                    // Max Contrast: Disable
                    PRINTD("LCD_CTRL: Normal voltage bias\n");
                    break;
                case 0xA3:
                    // Max Contrast: Enable
                    PRINTD("LCD_CTRL: Darker voltage bias\n");
                    break;
                case 0xA4:
                    // Set All Pixels: Disable
                    PRINTD("LCD_CTRL: Set all pixels disable\n");
                    break;
                case 0xA5:
                    // Set All Pixels: Enable
                    PRINTD("LCD_CTRL: Set all pixels enable\n");
                    break;
                case 0xA6:
                    // Invert All Pixels: Disable
                    PRINTD("LCD_CTRL: Invert all pixels disable\n");
                    break;
                case 0xA7:
                    // Invert All Pixels: Enable
                    PRINTD("LCD_CTRL: Invert all pixels enable\n");
                    break;
                case 0xA8: case 0xA9: case 0xAA: case 0xAB:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xAC: case 0xAD:
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
                case 0xAE:
                    // Display Off
                    PRINTD("LCD_CTRL: Display off\n");
                    break;
                case 0xAF:
                    // Display On
                    PRINTD("LCD_CTRL: Display on\n");
                    break;
                case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: case 0xB7:
                case 0xB8:
                    // Set page (0-8, each page is 8px high)
                    PRINTD("LCD_CTRL: Set page\n");
                    break;
                case 0xB9: case 0xBA: case 0xBB: case 0xBC: case 0xBD: case 0xBE: case 0xBF:
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xC0: case 0xC1: case 0xC2: case 0xC3: case 0xC4: case 0xC5: case 0xC6: case 0xC7:
                    // Display rows from top to bottom as 0 to 63
                    PRINTD("LCD_CTRL: Scan direction normal\n");
                    break;
                case 0xC8: case 0xC9: case 0xCA: case 0xCB: case 0xCC: case 0xCD: case 0xCE: case 0xCF:
                    // Display rows from top to bottom as 63 to 0
                    PRINTD("LCD_CTRL: Scan direction mirrored\n");
                    break;
                case 0xD0: case 0xD1: case 0xD2: case 0xD3: case 0xD4: case 0xD5: case 0xD6: case 0xD7:
                case 0xD8: case 0xD9: case 0xDA: case 0xDB: case 0xDC: case 0xDD: case 0xDE: case 0xDF:
                    // Do nothing?
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xE0:
                    // Start "Read Modify Write"
                    break;
                case 0xE2:
                    // Reset
                    PRINTD("LCD_CTRL: Reset display\n");
                    break;
                case 0xE3:
                    // No operation
                    PRINTD("LCD_CTRL: ???\n");
                    break;
                case 0xEE:
                    // End "Read Modify Write"
                    PRINTD("LCD_CTRL: Read modify write\n");
                    break;
                case 0xE1: case 0xE4: case 0xE5: case 0xE6: case 0xE7:
                case 0xE8: case 0xE9: case 0xEA: case 0xEB: case 0xEC: case 0xED: case 0xEF:
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
                case 0xF0: case 0xF1: case 0xF2: case 0xF3: case 0xF4: case 0xF5: case 0xF6: case 0xF7:
                    // 0xF1 and 0xF5 freeze LCD and cause malfunction (need to power off the device to restore)
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
                case 0xF8: case 0xF9: case 0xFA: case 0xFB: case 0xFC: case 0xFD: case 0xFE: case 0xFF:
                    // Contrast voltage control, FC = Default
                    // User shouldn't mess with this ones as may damage the LCD
                    PRINTD("LCD_CTRL: Damage\n");
                    break;
            }
            PRINTD("Writing hardware register LCD_CTRL=");
        }
        break;

        case 0xFF:
        {
            PRINTD("Writing hardware register LCD_DATA=");
        }
        break;

        case 0x44:
        case 0x45:
        case 0x46:
        case 0x47:
        case 0x50:
        case 0x51:
        case 0x54:
        case 0x55:
        case 0x62:
        {
            PRINTD("Writing hardware register Unknown=");
        }
        break;

        default:
        {
            PRINTD("Writing to hardware register 0x%x\n", address);
            return;
        }
    }
    registers[address] = data;
    PRINTD("0x%x\n", data);
}

uint8_t read_hardware_register(const uint8_t* registers, uint32_t address)
{
    uint8_t data = registers[address];
    switch(address)
    {
        case 0x0:
        case 0x1:
        case 0x2:
        {
            PRINTD("Reading hardware register SYS_CTRL%d=", address+1);
        }
        break;

        case 0x8:
        {
            PRINTD("Reading hardware register SEC_CTRL=");
            data = sec_ctrl;
        }
        break;

        case 0x9:
        {
            PRINTD("Reading hardware register SEC_CNT_LO=");
            data = sec_cnt & 0xFF;
        }
        break;

        case 0xA:
        {
            PRINTD("Reading hardware register SEC_CNT_MID=");
            data = (sec_cnt >> 8) & 0xFF;
        }
        break;

        case 0xB:
        {
            PRINTD("Reading hardware register SEC_CNT_MID=");
            data = (sec_cnt >> 16) & 0xFF;
        }
        break;

        case 0x10:
        {
            PRINTD("Reading hardware register SYS_BATT=");
        }
        break;

        case 0x52:
        {
            PRINTD("Reading hardware register KEY_PAD=");
        }
        break;

        case 0x53:
        {
            PRINTD("Reading hardware register CART_BUS=");
        }
        break;

        case 0x18:
        case 0x19:
        case 0x1A:
        case 0x1B:
        case 0x1C:
        case 0x1D:
        {
            PRINTD("Writing hardware register TMR%d_%s=", (address - 0x16) / 2, (address % 2)? "OSC": "SCALE");
        }
        break;

        case 0x20:
        case 0x21:
        case 0x22:
        {
            PRINTD("Reading hardware register IRQ_PRI%d=", address - 0x1F);
        }
        break;

        case 0x23:
        case 0x24:
        case 0x25:
        case 0x26:
        {
            PRINTD("Reading hardware register IRQ_ENA%d=", address - 0x22);
        }
        break;

        case 0x27:
        case 0x28:
        case 0x29:
        case 0x2A:
        {
            PRINTD("Reading hardware register IRQ_ACT%d=", address - 0x26);
        }
        break;

        case 0x30:
        case 0x31:
        case 0x38:
        case 0x39:
        case 0x48:
        case 0x49:
        {
            PRINTD("Reading hardware register TMR%d_CTRL_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
        }
        break;

        case 0x32:
        case 0x33:
        case 0x3A:
        case 0x3B:
        case 0x4A:
        case 0x4B:
        {
            PRINTD("Reading hardware register TMR%d_PRE_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
        }
        break;

        case 0x34:
        case 0x35:
        case 0x3C:
        case 0x3D:
        {
            PRINTD("Reading hardware register TMR%d_PVT_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
        }
        break;

        case 0x36:
        case 0x37:
        case 0x3E:
        case 0x3F:
        case 0x4E:
        case 0x4F:
        {
            PRINTD("Reading hardware register TMR%d_CNT_%s=", (address > 0x40)? 3: (address - 0x28) / 8, address % 2? "H": "L");
            PRINTE("** Reading hardware register 0x%x which is a timer register and is not implemented! **\n", address);
        }
        break;

        case 0x40:
        {
            PRINTD("Reading hardware register TMR256_CTRL=");
        }
        break;

        case 0x41:
        {
            PRINTD("Reading hardware register TMR256_CNT=");
        }
        break;

        case 0x60:
        {
            PRINTD("Reading hardware register IO_DIR=");
        }
        break;

        case 0x61:
        {
            PRINTD("Reading hardware register IO_DATA=");
        }
        break;

        case 0x70:
        {
            PRINTD("Reading hardware register AUD_CTRL=");
        }
        break;

        case 0x71:
        {
            PRINTD("Reading hardware register AUD_VOL=");
        }
        break;

        case 0x80:
        {
            PRINTD("Reading hardware register PRC_MODE=");
            data = prc_mode;
        }
        break;

        case 0x81:
        {
            PRINTD("Reading hardware register PRC_RATE=");
            data = prc_rate;
        }
        break;

        case 0x82:
        {
            PRINTD("Reading hardware register PRC_MAP_LO=");
        }
        break;

        case 0x83:
        {
            PRINTD("Reading hardware register PRC_MAP_MID=");
        }
        break;

        case 0x84:
        {
            PRINTD("Reading hardware register PRC_MAP_HI=");
        }
        break;

        case 0x85:
        {
            PRINTD("Reading hardware register PRC_SCROLL_Y=");
        }
        break;

        case 0x86:
        {
            PRINTD("Reading hardware register PRC_SCROLL_X=");
        }
        break;

        case 0x87:
        {
            PRINTD("Reading hardware register PRC_SPR_LO=");
        }
        break;

        case 0x88:
        {
            PRINTD("Reading hardware register PRC_SPR_MID=");
        }
        break;

        case 0x89:
        {
            PRINTD("Reading hardware register PRC_SPR_HI=");
        }
        break;

        case 0x44:
        case 0x45:
        case 0x46:
        case 0x47:
        case 0x50:
        case 0x51:
        case 0x54:
        case 0x55:
        case 0x62:
        {
            PRINTD("Reading hardware register Unknown=");
        }
        break;

        default:
        {
            PRINTD("Reading hardware register 0x%x=", address);
        }
        break;
    }
    PRINTD("0x%x\n", data);
    return data;
}

struct SimData
{
    Vminx* minx;

    int timestamp;
    uint64_t osc1_clocks;
    uint64_t osc1_next_clock;

    uint8_t registers[256] = {};

    uint8_t* bios;
    uint8_t* memory;
    uint8_t* cartridge;

    size_t bios_file_size;
    size_t cartridge_file_size;

    uint8_t* bios_touched;
    uint8_t* cartridge_touched;
    uint8_t* instructions_executed;
};

void init_sim(SimData* sim, const char* cartridge_path)
{
    FILE* fp = fopen("data/bios.min", "rb");
    fseek(fp, 0, SEEK_END);
    sim->bios_file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */

    sim->bios = (uint8_t*) malloc(sim->bios_file_size);
    fread(sim->bios, 1, sim->bios_file_size, fp);
    fclose(fp);

    sim->bios_touched = (uint8_t*) calloc(sim->bios_file_size, 1);

    sim->memory = (uint8_t*) calloc(1, 4*1024);

    // Load a cartridge.
    sim->cartridge = (uint8_t*) calloc(1, 0x200000);
    fp = fopen(cartridge_path, "rb");

    fseek(fp, 0, SEEK_END);
    sim->cartridge_file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */
    fread(sim->cartridge, 1, sim->cartridge_file_size, fp);
    fclose(fp);

    sim->cartridge_touched = (uint8_t*) calloc(1, sim->cartridge_file_size);
    sim->instructions_executed = (uint8_t*) calloc(1, 0x300);

    sim->minx = new Vminx;
    sim->minx->clk = 0;
    sim->minx->reset = 1;

    sim->registers[0x52] = 0xFF;
    sim->registers[0x10] = 0x18;

    sim->osc1_clocks = 4000000.0 / 32768.0 + 0.5;
    sim->osc1_next_clock = sim->osc1_clocks;

    sim->timestamp = 0;
}

void simulate_steps(SimData* sim, int n_steps)
{
    for(int i = 0; i < n_steps && !Verilated::gotFinish(); ++i)
    {
        sim->minx->clk = 1;
        sim->minx->eval();
        if(sim->timestamp == sim->osc1_next_clock)
        {
            sim->minx->rt_clk = !sim->minx->rt_clk;
            sim->minx->eval();
            sim->osc1_next_clock += sim->osc1_clocks;
        }
        sim->timestamp++;

        sim->minx->clk = 0;
        sim->minx->eval();
        if(sim->timestamp == sim->osc1_next_clock)
        {
            sim->minx->rt_clk = !sim->minx->rt_clk;
            sim->minx->eval();
            sim->osc1_next_clock += sim->osc1_clocks;
        }
        sim->timestamp++;

        if(sim->minx->rootp->minx__DOT__irq_render_done && irq_render_done_old == 0)
        {
            irq_render_done_old = 1;
            PRINTD("Render done %d.\n", sim->timestamp / 2);

            uint8_t contrast = sim->minx->rootp->minx__DOT__lcd__DOT__contrast;
            if(contrast > 0x20) contrast = 0x20;

            uint8_t image_data[96*64];

            for (int yC=0; yC<8; yC++)
            {
                for (int xC=0; xC<96; xC++)
                {
                    uint8_t data = sim->minx->rootp->minx__DOT__lcd__DOT__lcd_data[yC * 132 + xC];
                    for(int i = 0; i < 8; ++i)
                        image_data[96 * (8 * yC + i) + xC] = ((~data >> i) & 1)? 255.0: 255.0 * (1.0 - (float)contrast / 0x20);
                }
            }

        }
        else if(!sim->minx->rootp->minx__DOT__irq_render_done) irq_render_done_old = 0;

        if(sim->minx->rootp->minx__DOT__irq_copy_complete && irq_copy_complete_old == 0)
        {
            irq_copy_complete_old = 1;
            PRINTD("Copy complete %d.\n", sim->timestamp / 2);
        }
        else if(!sim->minx->rootp->minx__DOT__irq_copy_complete) irq_copy_complete_old = 0;

        // At rising edge of clock
        data_sent = false;

        if(sec_ctrl & 2)
            sec_cnt = 0;

        if((sec_ctrl & 1) && (sim->timestamp % 4000000 == 0))
            ++sec_cnt;


        // Check for errors
        {
            if(sim->minx->rootp->minx__DOT__cpu__DOT__state == 2 && sim->minx->pl == 0 && !sim->minx->rootp->minx__DOT__bus_ack)
            {
                if(sim->minx->rootp->minx__DOT__cpu__DOT__microaddress == 0 &&
                   sim->minx->rootp->minx__DOT__cpu__DOT__extended_opcode != 0x1AE
                ){
                    PRINTE("** Instruction 0x%x not implemented at 0x%x, timestamp: %d**\n", sim->minx->rootp->minx__DOT__cpu__DOT__extended_opcode, sim->minx->rootp->minx__DOT__cpu__DOT__top_address, sim->timestamp);
                }
            }

            if(
                (sim->minx->sync == 1) &&
                (sim->minx->pl == 0) &&
                (sim->minx->rootp->minx__DOT__cpu__DOT__micro_op & 0x1000) &&
                sim->minx->iack == 0 &&
                !sim->minx->rootp->minx__DOT__bus_ack)
            {
                if(irq_processing)
                    irq_processing = false;
                else
                {
                    uint8_t num_cycles        = num_cycles_since_sync;
                    uint16_t extended_opcode  = sim->minx->rootp->minx__DOT__cpu__DOT__extended_opcode;
                    uint8_t num_cycles_actual = instruction_cycles[2*extended_opcode];
                    uint8_t num_cycles_actual_branch = instruction_cycles[2*extended_opcode+1];


                    if(num_cycles != num_cycles_actual)
                        if(num_cycles != num_cycles_actual_branch || num_cycles_actual_branch == 0)
                            PRINTE(" ** Discrepancy found in number of cycles of instruction 0x%x: %d, %d, timestamp: %d** \n", extended_opcode, num_cycles, num_cycles_actual, sim->timestamp);

                    sim->instructions_executed[extended_opcode] = 1;
                }
            }

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_addressing_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Addressing not implemented error: 0x%llx, timestamp: %d** \n", (sim->minx->rootp->minx__DOT__cpu__DOT__micro_op & 0x3F00000) >> 20, sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_jump_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Jump not implemented error, 0x%llx, timestamp: %d** \n", (sim->minx->rootp->minx__DOT__cpu__DOT__micro_op & 0x7C000) >> 14, sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_data_out_error == 1 && sim->minx->pl == 1)
                PRINTE(" ** Data-out not implemented error, timestamp: %d** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_mov_src_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Mov src not implemented error, timestamp: %d** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_write_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Write not implemented error, timestamp: %d** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__alu_op_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Alu not implemented error, timestamp: %d** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_alu_dec_pack_ops_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Alu decimal and packed operations not implemented error, sim->timestamp: %d** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_divzero_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Division by zero exception not implemented error, sim->timestamp: %d**\n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__SP > 0x2000 && sim->minx->pl == 0)
            {
                PRINTE(" ** Stack overflow, timestamp: %d**\n", sim->timestamp);
                break;
            }
        }

        if(sim->timestamp >= 8)
            sim->minx->reset = 0;

        if(sim->timestamp > 258 && sim->minx->iack == 1 && sim->minx->pl == 0 && sim->minx->sync)
        {
            irq_processing = true;
        }

        if(sim->minx->bus_status == BUS_MEM_READ && sim->minx->pl == 0) // Check if PL=0 just to reduce spam.
        {
            // memory read
            if(sim->minx->address_out < 0x1000)
            {
                // read from bios
                sim->bios_touched[sim->minx->address_out & (sim->bios_file_size - 1)] = 1;
                sim->minx->data_in = *(sim->bios + (sim->minx->address_out & (sim->bios_file_size - 1)));
            }
            else if(sim->minx->address_out < 0x2000)
            {
                // read from ram
                uint32_t address = sim->minx->address_out & 0xFFF;
                sim->minx->data_in = *(uint8_t*)(sim->memory + address);
            }
            else if(sim->minx->address_out < 0x2100)
            {
                // read from hardware registers
                sim->minx->data_in = read_hardware_register(sim->registers, sim->minx->address_out & 0x1FFF);
            }
            else
            {
                // read from cartridge
                sim->cartridge_touched[(sim->minx->address_out & 0x1FFFFF) & (sim->cartridge_file_size - 1)] = 1;
                sim->minx->data_in = *(uint8_t*)(sim->cartridge + (sim->minx->address_out & 0x1FFFFF));
            }

            data_sent = true;
        }
        else if(sim->minx->bus_status == BUS_MEM_WRITE && sim->minx->write)
        {
            // memory write
            if(sim->minx->address_out < 0x1000)
            {
                PRINTD("Program trying to write to bios at 0x%x, timestamp: %d\n", sim->minx->address_out, sim->timestamp);
            }
            else if(sim->minx->address_out < 0x2000)
            {
                // write to ram
                uint32_t address = sim->minx->address_out & 0xFFF;
                *(uint8_t*)(sim->memory + address) = sim->minx->data_out;
            }
            else if(sim->minx->address_out < 0x2100)
            {
                // write to hardware registers
                write_hardware_register(sim->registers, sim->minx->address_out & 0x1FFF, sim->minx->data_out);
            }
            else
            {
                PRINTD("Program trying to write to cartridge at 0x%x, timestamp: %d\n", sim->minx->address_out, sim->timestamp);
            }

            data_sent = true;
        }

        if(sim->minx->sync && sim->minx->pl == 1)
            num_cycles_since_sync = 0;

        if(sim->minx->pl == 1 && !sim->minx->rootp->minx__DOT__bus_ack)
            ++num_cycles_since_sync;
    }
}

uint8_t* get_lcd_image(Vminx& minx)
{
    uint8_t contrast = minx.rootp->minx__DOT__lcd__DOT__contrast;
    if(contrast > 0x20) contrast = 0x20;

    uint8_t* image_data = new uint8_t[96*64];

    for (int yC=0; yC<8; yC++)
    {
        for (int xC=0; xC<96; xC++)
        {
            uint8_t data = minx.rootp->minx__DOT__lcd__DOT__lcd_data[yC * 132 + xC];
            for(int i = 0; i < 8; ++i)
            {
                int idx = 96 * (63 - 8 * yC - i) + xC;
                image_data[idx] = ((~data >> i) & 1)? 255.0: 255.0 * (1.0 - (float)contrast / 0x20);
            }
        }
    }

    return image_data;
}

int main(int argc, char** argv)
{
    int num_sim_steps = 150000;

    SimData sim;
    init_sim(&sim, "data/party_j.min");

    // Create window and gl context, and game controller
    int window_width = 960/2;
    int window_height = 640/2;

    SDL_Window* window;
    SDL_GLContext gl_context;
    {
        if(SDL_Init(SDL_INIT_VIDEO) < 0)// | SDL_INIT_AUDIO) < 0)
        {
            fprintf(stderr, "Error initializing SDL. SDL_Error: %s\n", SDL_GetError());
            return -1;
        }


        // Use OpenGL 3.1 core
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
        //SDL_GL_SetAttribute(SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, 1);

        window = SDL_CreateWindow(
            "Vectron",
            SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
            window_width, window_height,
            SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI
        );

        if(!window)
        {
            fprintf(stderr, "Error creating SDL window. SDL_Error: %s\n", SDL_GetError());
            SDL_Quit();
            return -1;
        }

        gl_context = SDL_GL_CreateContext(window);
        if(!gl_context)
        {
            fprintf(stderr, "Error creating SDL GL context. SDL_Error: %s\n", SDL_GetError());
            SDL_DestroyWindow(window);
            SDL_Quit();
            return -1;
        }

        int r, g, b, a, m, s;
        SDL_GL_GetAttribute(SDL_GL_RED_SIZE, &r);
        SDL_GL_GetAttribute(SDL_GL_GREEN_SIZE, &g);
        SDL_GL_GetAttribute(SDL_GL_BLUE_SIZE, &b);
        SDL_GL_GetAttribute(SDL_GL_ALPHA_SIZE, &a);
        SDL_GL_GetAttribute(SDL_GL_MULTISAMPLESAMPLES, &m);
        //SDL_GL_GetAttribute(SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, &s);

        SDL_GL_SetSwapInterval(1);
    }

    int drawable_width, drawable_height;
    SDL_GL_GetDrawableSize(window, &drawable_width, &drawable_height);
    gl_renderer_init(96, 64);

    bool sim_is_running = true;
    bool program_is_running = true;
    while(program_is_running)
    {
        // Process input
        SDL_Event sdl_event;
        while(SDL_PollEvent(&sdl_event) != 0)
        {
            // Keyboard input
            if(sdl_event.type == SDL_KEYDOWN)
            {
                if(sdl_event.key.keysym.sym == SDLK_p)
                {
                    sim_is_running = !sim_is_running;
                    continue;
                }

                switch(sdl_event.key.keysym.sym){
                case SDLK_ESCAPE:
                    program_is_running = false;
                    break;
                case SDLK_UP:
                    sim.registers[0x52] = sim.registers[0x52] & 0xF7;
                    break;
                case SDLK_DOWN:
                    sim.registers[0x52] = sim.registers[0x52] & 0xEF;
                    break;
                case SDLK_RIGHT:
                    sim.registers[0x52] = sim.registers[0x52] & 0xBF;
                    break;
                case SDLK_LEFT:
                    sim.registers[0x52] = sim.registers[0x52] & 0xDF;
                    break;
                case SDLK_x: // A
                    sim.registers[0x52] = sim.registers[0x52] & 0xFE;
                    break;
                case SDLK_z: // B
                    sim.registers[0x52] = sim.registers[0x52] & 0xFD;
                    break;
                case SDLK_s:
                case SDLK_c:
                    sim.registers[0x52] = sim.registers[0x52] & 0xFB;
                    break;
                default:
                    break;
                }
            }
            else if(sdl_event.type == SDL_KEYUP)
            {
                switch(sdl_event.key.keysym.sym){
                case SDLK_UP:
                    sim.registers[0x52] = sim.registers[0x52] | 0x08;
                    break;
                case SDLK_DOWN:
                    sim.registers[0x52] = sim.registers[0x52] | 0x10;
                    break;
                case SDLK_RIGHT:
                    sim.registers[0x52] = sim.registers[0x52] | 0x40;
                    break;
                case SDLK_LEFT:
                    sim.registers[0x52] = sim.registers[0x52] | 0x20;
                    break;
                case SDLK_x: // A
                    sim.registers[0x52] = sim.registers[0x52] | 0x01;
                    break;
                case SDLK_z: // B
                    sim.registers[0x52] = sim.registers[0x52] | 0x02;
                    break;
                case SDLK_s:
                case SDLK_c:
                    sim.registers[0x52] = sim.registers[0x52] | 0x04;
                    break;
                default:
                    break;
                }
            }
            else if(sdl_event.type == SDL_QUIT)
            {
                program_is_running = false;
            }
            else if(sdl_event.type == SDL_WINDOWEVENT)
            {
                if(sdl_event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED)
                {
                    SDL_GL_GetDrawableSize(window, &drawable_width, &drawable_height);
                }
                else if(sdl_event.window.event == SDL_WINDOWEVENT_FOCUS_LOST)
                    sim_is_running = false;
                else if(sdl_event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED)
                    sim_is_running = true;
            }
        }

        if(sim_is_running)
            simulate_steps(&sim, num_sim_steps);
        uint8_t* lcd_image = get_lcd_image(*sim.minx);
        gl_renderer_draw(96, 64, lcd_image);
        delete[] lcd_image;

        SDL_GL_SwapWindow(window);
    }

    SDL_GL_DeleteContext(gl_context);
    SDL_DestroyWindow(window);
    SDL_Quit();

    size_t total_touched = 0;
    for(size_t i = 0; i < sim.bios_file_size; ++i)
        total_touched += sim.bios_touched[i];
    printf("%zu bytes out of total %zu read from bios.\n", total_touched, sim.bios_file_size);

    total_touched = 0;
    for(size_t i = 0; i < sim.cartridge_file_size; ++i)
        total_touched += sim.cartridge_touched[i];
    printf("%zu bytes out of total %zu read from cartridge.\n", total_touched, sim.cartridge_file_size);

    total_touched = 0;
    for(size_t i = 0; i < 0x300; ++i)
        total_touched += sim.instructions_executed[i];
    printf("%zu instructions out of total 608 executed.\n", total_touched);

    return 0;
}
