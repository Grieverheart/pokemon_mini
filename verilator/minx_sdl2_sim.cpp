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
        "    outColor = val * vec3(0.611, 0.694, 0.611);\n"
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

struct SimData
{
    Vminx* minx;
    VerilatedVcdC* tfp;

    uint64_t timestamp;
    uint64_t osc1_clocks;
    uint64_t osc1_next_clock;

    uint8_t* bios;
    uint8_t* memory;
    uint8_t* cartridge;

    size_t bios_file_size;
    size_t cartridge_file_size;

    uint8_t* bios_touched;
    uint8_t* cartridge_touched;
    uint8_t* instructions_executed;
};

void sim_init(SimData* sim, const char* cartridge_path)
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

    sim->osc1_clocks = 4000000.0 / 32768.0 + 0.5;
    sim->osc1_next_clock = sim->osc1_clocks;

    sim->timestamp = 0;

    Verilated::traceEverOn(true);
    sim->tfp = nullptr;
}

void sim_dump_stop(SimData* sim)
{
    if(!sim->tfp) return;
    printf("Stopping dump.\n");

    sim->tfp->close();
    delete sim->tfp;
    sim->tfp = nullptr;
}

void sim_dump_start(SimData* sim, const char* filepath)
{
    printf("Starting dump at timestamp: %llu.\n", sim->timestamp);
    if(sim->tfp)
        sim_dump_stop(sim);

    sim->tfp = new VerilatedVcdC;
    sim->minx->trace(sim->tfp, 99);  // Trace 99 levels of hierarchy
    sim->tfp->rolloverMB(209715200);
    sim->tfp->open(filepath);
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
            if(sim->tfp) sim->tfp->dump(sim->timestamp);
            sim->osc1_next_clock += sim->osc1_clocks;
        }
        else if(sim->tfp) sim->tfp->dump(sim->timestamp);
        sim->timestamp++;

        sim->minx->clk = 0;
        sim->minx->eval();
        if(sim->timestamp == sim->osc1_next_clock)
        {
            sim->minx->rt_clk = !sim->minx->rt_clk;
            sim->minx->eval();
            if(sim->tfp) sim->tfp->dump(sim->timestamp);
            sim->osc1_next_clock += sim->osc1_clocks;
        }
        else if(sim->tfp) sim->tfp->dump(sim->timestamp);
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


        // Check for errors
        {
            if(sim->minx->rootp->minx__DOT__cpu__DOT__state == 2 && sim->minx->pl == 0 && !sim->minx->rootp->minx__DOT__bus_ack)
            {
                if(sim->minx->rootp->minx__DOT__cpu__DOT__microaddress == 0 &&
                   sim->minx->rootp->minx__DOT__cpu__DOT__extended_opcode != 0x1AE
                ){
                    PRINTE("** Instruction 0x%x not implemented at 0x%x, timestamp: %llu**\n", sim->minx->rootp->minx__DOT__cpu__DOT__extended_opcode, sim->minx->rootp->minx__DOT__cpu__DOT__top_address, sim->timestamp);
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
                            PRINTE(" ** Discrepancy found in number of cycles of instruction 0x%x: %d, %d, timestamp: %llu** \n", extended_opcode, num_cycles, num_cycles_actual, sim->timestamp);

                    //if(!sim->instructions_executed[extended_opcode])
                    //    printf("Instruction 0x%x executed for the first time, at 0x%x, timestamp: %llu.\n", extended_opcode, sim->minx->rootp->minx__DOT__cpu__DOT__top_address, sim->timestamp);
                    sim->instructions_executed[extended_opcode] = 1;
                }
            }

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_addressing_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Addressing not implemented error: 0x%llx, timestamp: %llu** \n", (sim->minx->rootp->minx__DOT__cpu__DOT__micro_op & 0x3F00000) >> 20, sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_jump_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Jump not implemented error, 0x%llx, timestamp: %llu** \n", (sim->minx->rootp->minx__DOT__cpu__DOT__micro_op & 0x7C000) >> 14, sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_data_out_error == 1 && sim->minx->pl == 1)
                PRINTE(" ** Data-out not implemented error, timestamp: %llu** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_mov_src_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Mov src not implemented error, timestamp: %llu** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_write_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Write not implemented error, timestamp: %llu** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__alu_op_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Alu not implemented error, timestamp: %llu** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_alu_dec_pack_ops_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Alu decimal and packed operations not implemented error, sim->timestamp: %llu** \n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__not_implemented_divzero_error == 1 && sim->minx->pl == 0)
                PRINTE(" ** Division by zero exception not implemented error, sim->timestamp: %llu**\n", sim->timestamp);

            if(sim->minx->rootp->minx__DOT__cpu__DOT__SP > 0x2000 && sim->minx->pl == 0)
            {
                PRINTE(" ** Stack overflow, timestamp: %llu**\n", sim->timestamp);
                break;
            }
        }

        //if(
        //    sim->minx->rootp->minx__DOT__cpu__DOT__postpone_exception == 1 &&
        //    sim->minx->rootp->iack == 1 &&
        //    sim->minx->rootp->minx__DOT__cpu__DOT__NB > 0
        //){
        //    if(!sim->tfp)
        //        sim_dump_start(sim, "temp.vcd");
        //}
        //if(sim->timestamp == 23475360-1000)
        //    sim_dump_start(sim, "temp.vcd");

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
            else if(sim->minx->address_out >= 0x2100)
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
                PRINTD("Program trying to write to bios at 0x%x, timestamp: %llu\n", sim->minx->address_out, sim->timestamp);
            }
            else if(sim->minx->address_out < 0x2000)
            {
                // write to ram
                uint32_t address = sim->minx->address_out & 0xFFF;
                *(uint8_t*)(sim->memory + address) = sim->minx->data_out;
            }
            else if(sim->minx->address_out >= 0x2100)
            {
                PRINTD("Program trying to write to cartridge at 0x%x, timestamp: %llu\n", sim->minx->address_out, sim->timestamp);
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

// @todo: Create a call stack for keeping track call/return problems.
int main(int argc, char** argv)
{
    int num_sim_steps = 150000;

    SimData sim;
    //const char* rom_filepath = "data/party_j.min";
    // Possibly problem with display starting 2 pixels from the left.
    //const char* rom_filepath = "data/6shades.min";
    //const char* rom_filepath = "data/pichu_bros_mini_j.min";
    //const char* rom_filepath = "data/pokemon_anime_card_daisakusen_j.min";
    //const char* rom_filepath = "data/snorlaxs_lunch_time_j.min";
    //const char* rom_filepath = "data/pokemon_shock_tetris_j.min";
    // Glitching when clock is reaching zero while counting down.
    const char* rom_filepath = "data/togepi_no_daibouken_j.min";
    //const char* rom_filepath = "data/pokemon_race_mini_j.min";
    //const char* rom_filepath = "data/pokemon_sodateyasan_mini_j.min";
    //const char* rom_filepath = "data/pokemon_puzzle_collection_j.min";
    //const char* rom_filepath = "data/pokemon_puzzle_collection_vol2_j.min";
    //const char* rom_filepath = "data/pokemon_pinball_mini_j.min";
    sim_init(&sim, rom_filepath);

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
    bool dump_sim = false;
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
                else if(sdl_event.key.keysym.sym == SDLK_d)
                {
                    if(!dump_sim)
                    {
                        dump_sim = true;
                        sim_dump_start(&sim, "sim.vcd");
                    }
                    else
                    {
                        dump_sim = false;
                        sim_dump_stop(&sim);
                    }
                }
                else
                {
                    switch(sdl_event.key.keysym.sym){
                    case SDLK_ESCAPE:
                        program_is_running = false;
                        break;
                    case SDLK_UP:
                        sim.minx->keys_active |= 0x08;
                        break;
                    case SDLK_DOWN:
                        sim.minx->keys_active |= 0x10;
                        break;
                    case SDLK_RIGHT:
                        sim.minx->keys_active |= 0x40;
                        break;
                    case SDLK_LEFT:
                        sim.minx->keys_active |= 0x20;
                        break;
                    case SDLK_x: // A
                        sim.minx->keys_active |= 0x01;
                        break;
                    case SDLK_z: // B
                        sim.minx->keys_active |= 0x02;
                        break;
                    case SDLK_s:
                    case SDLK_c:
                        sim.minx->keys_active |= 0x04;
                        break;
                    default:
                        break;
                    }
                }
            }
            else if(sdl_event.type == SDL_KEYUP)
            {
                switch(sdl_event.key.keysym.sym){
                case SDLK_UP:
                    sim.minx->keys_active &= ~0x08;
                    break;
                case SDLK_DOWN:
                    sim.minx->keys_active &= ~0x10;
                    break;
                case SDLK_RIGHT:
                    sim.minx->keys_active &= ~0x40;
                    break;
                case SDLK_LEFT:
                    sim.minx->keys_active &= ~0x20;
                    break;
                case SDLK_x: // A
                    sim.minx->keys_active &= ~0x01;
                    break;
                case SDLK_z: // B
                    sim.minx->keys_active &= ~0x02;
                    break;
                case SDLK_s:
                case SDLK_c:
                    sim.minx->keys_active &= ~0x04;
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

    sim_dump_stop(&sim);

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
