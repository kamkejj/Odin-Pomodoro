package main

import "core:fmt"
import "core:mem"
import "core:math"
import "core:flags"
import "core:os"
import "vendor:sdl2"
import "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "core:c/libc"
import "core:encoding/json"
import "core:path/filepath"
import "core:strings"

WINDOW_WIDTH  :: 150
WINDOW_HEIGHT :: 150

PomodoroState :: enum {
    Work,
    ShortBreak,
    LongBreak,
}

Settings :: struct {
    work:        f32 `usage:"Work duration in minutes"`,
    short_break: f32 `usage:"Short break duration in minutes"`,
    long_break:  f32 `usage:"Long break duration in minutes"`,
}

StateColor :: struct { r, g, b: f32 }

get_color :: proc(state: PomodoroState) -> StateColor {
    switch state {
    case .Work:       return {0.9, 0.3, 0.3} // Red
    case .ShortBreak: return {0.3, 0.8, 0.5} // Green
    case .LongBreak:  return {0.3, 0.5, 0.9} // Blue
    }
    return {0.5, 0.5, 0.5}
}

get_duration :: proc(state: PomodoroState, settings: Settings) -> f32 {
    switch state {
    case .Work:       return settings.work * 60.0
    case .ShortBreak: return settings.short_break * 60.0
    case .LongBreak:  return settings.long_break * 60.0
    }
    return 0.0
}

get_settings_path :: proc() -> string {
    home := os.get_env("HOME", context.temp_allocator)
    if home == "" {
        return ".pomodoro_settings.json"
    }
    return filepath.join({home, ".pomodoro_settings.json"}, context.temp_allocator)
}

load_settings_from_json :: proc(settings: ^Settings, path: string) -> bool {
    data, ok := os.read_entire_file(path, context.temp_allocator)
    if !ok {
        return false // File doesn't exist or can't be read
    }
    
    v, err := json.parse(data, allocator = context.temp_allocator)
    if err != .None {
        return false
    }
    
    root, root_ok := v.(json.Object)
    if !root_ok {
        return false
    }
    
    if work_val, ok := root["work"].(json.Float); ok {
        settings.work = f32(work_val)
    } else if work_val, ok := root["work"].(json.Integer); ok {
        settings.work = f32(work_val)
    }

    if short_val, ok := root["short_break"].(json.Float); ok {
        settings.short_break = f32(short_val)
    } else if short_val, ok := root["short_break"].(json.Integer); ok {
        settings.short_break = f32(short_val)
    }
    
    if long_val, ok := root["long_break"].(json.Float); ok {
        settings.long_break = f32(long_val)
    } else if long_val, ok := root["long_break"].(json.Integer); ok {
        settings.long_break = f32(long_val)
    }
    
    return true
}

main :: proc() {
    settings := Settings{
        work        = 25.0,
        short_break = 5.0,
        long_break  = 15.0,
    }
    
    settings_path := get_settings_path()
    load_settings_from_json(&settings, settings_path)
    last_settings_time, _ := os.last_write_time_by_name(settings_path)

    flags.parse_or_exit(&settings, os.args)

    if sdl2.Init({.VIDEO, .TIMER}) != 0 {
        fmt.eprintln("Failed to initialize SDL2:", sdl2.GetError())
        return
    }
    defer sdl2.Quit()

    window_flags: sdl2.WindowFlags = {.METAL, .ALLOW_HIGHDPI, .ALWAYS_ON_TOP}
    window := sdl2.CreateWindow(
        "OPT",
        sdl2.WINDOWPOS_CENTERED,
        sdl2.WINDOWPOS_CENTERED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        window_flags,
    )
    if window == nil {
        fmt.eprintln("Failed to create SDL2 window:", sdl2.GetError())
        return
    }
    defer sdl2.DestroyWindow(window)

    metal_view := sdl2.Metal_CreateView(window)
    if metal_view == nil {
        fmt.eprintln("Failed to create Metal view")
        return
    }
    defer sdl2.Metal_DestroyView(metal_view)

    metal_layer := (^CA.MetalLayer)(sdl2.Metal_GetLayer(metal_view))

    device := Metal.CreateSystemDefaultDevice()
    if device == nil {
        fmt.eprintln("Metal is not supported on this device")
        return
    }
    metal_layer->setDevice(device)
    
    // Shader Compilation
    shader_src := #load("shader.metal", string)
    ns_shader_src := NS.String.alloc()->initWithOdinString(shader_src)
    defer ns_shader_src->release()
    
    library, err := device->newLibraryWithSource(ns_shader_src, nil)
    if err != nil {
        fmt.eprintln("Failed to compile shader:", err->localizedDescription()->odinString())
        return
    }
    defer library->release()
    
    vertex_func := library->newFunctionWithName(NS.String.alloc()->initWithOdinString("vertexMain"))
    defer vertex_func->release()
    
    frag_func := library->newFunctionWithName(NS.String.alloc()->initWithOdinString("fragmentMain"))
    defer frag_func->release()

    pipeline_desc := Metal.RenderPipelineDescriptor.alloc()->init()
    defer pipeline_desc->release()
    pipeline_desc->setVertexFunction(vertex_func)
    pipeline_desc->setFragmentFunction(frag_func)
    
    color_att := pipeline_desc->colorAttachments()->object(0)
    color_att->setPixelFormat(metal_layer->pixelFormat())

    pipeline_state, pipe_err := device->newRenderPipelineStateWithDescriptor(pipeline_desc)
    if pipe_err != nil {
        fmt.eprintln("Failed to create pipeline:", pipe_err->localizedDescription()->odinString())
        return
    }
    defer pipeline_state->release()

    command_queue := device->newCommandQueue()
    if command_queue == nil {
        fmt.eprintln("Failed to create command queue")
        return
    }
    defer command_queue->release()

    // Pomodoro logic tracking
    current_state := PomodoroState.Work
    time_remaining := get_duration(current_state, settings)
    last_ticks := sdl2.GetTicks()
    is_paused := false
    pomodoros_completed := 0

    running := true
    for running {
        pool := NS.scoped_autoreleasepool()
        defer free_all(context.temp_allocator)
        
        current_ticks := sdl2.GetTicks()
        dt := f32(current_ticks - last_ticks) / 1000.0
        last_ticks = current_ticks
        
        current_settings_time, err := os.last_write_time_by_name(settings_path)
        if err == os.ERROR_NONE && current_settings_time != last_settings_time {
            load_settings_from_json(&settings, settings_path)
            last_settings_time = current_settings_time
            // Reset the time remaining for the current state to the new setting
            time_remaining = get_duration(current_state, settings)
        }
        
        event: sdl2.Event
        for sdl2.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
            case .KEYDOWN:
                if event.key.keysym.sym == .SPACE {
                    is_paused = !is_paused
                } else if event.key.keysym.sym == .S { 
                    // Skip to next state
                    time_remaining = 0.0
                } else if event.key.keysym.sym == .COMMA && (.LGUI in event.key.keysym.mod || .RGUI in event.key.keysym.mod) {
                    // Launch settings ui (Cmd+,)
                    exe_dir := filepath.dir(os.args[0], context.temp_allocator)
                    settings_swift_path := filepath.join({exe_dir, "settings.swift"}, context.temp_allocator)
                    cmd_str := fmt.tprintf("swiftc \"%s\" -parse-as-library -o /tmp/pomodoro_settings_app && /tmp/pomodoro_settings_app &", settings_swift_path)
                    libc.system(strings.clone_to_cstring(cmd_str, context.temp_allocator))
                }
            }
        }

        if !is_paused {
            time_remaining -= dt
            if time_remaining <= 0.0 {
                if current_state == .Work {
                    pomodoros_completed += 1
                    if pomodoros_completed % 4 == 0 {
                        current_state = .LongBreak
                    } else {
                        current_state = .ShortBreak
                    }
                } else {
                    current_state = .Work
                }
                time_remaining = get_duration(current_state, settings)
            }
        }

        drawable := metal_layer->nextDrawable()
        if drawable != nil {
            pass_descriptor := Metal.RenderPassDescriptor.renderPassDescriptor()
            color_attachment := pass_descriptor->colorAttachments()->object(0)
            
            color_attachment->setTexture(drawable->texture())
            color_attachment->setLoadAction(.Clear)
            color_attachment->setClearColor(Metal.ClearColor{red = 0.05, green = 0.05, blue = 0.05, alpha = 1.0})
            color_attachment->setStoreAction(.Store)

            command_buffer := command_queue->commandBuffer()
            render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass_descriptor)
            
            render_encoder->setRenderPipelineState(pipeline_state)
            
            // Set bindings
            progress := 1.0 - (time_remaining / get_duration(current_state, settings))
            progress_bytes := mem.slice_ptr((^byte)(&progress), size_of(f32))
            render_encoder->setFragmentBytes(progress_bytes, 0)
            
            color := get_color(current_state)
            color_array := [3]f32{color.r, color.g, color.b}
            color_bytes := mem.slice_ptr((^byte)(&color_array), size_of([3]f32))
            render_encoder->setFragmentBytes(color_bytes, 1)
            
            aspect := f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT)
            aspect_bytes := mem.slice_ptr((^byte)(&aspect), size_of(f32))
            render_encoder->setFragmentBytes(aspect_bytes, 2)
            
            // Draw 6 vertices (2 triangles making a quad)
            render_encoder->drawPrimitives(.Triangle, 0, 6)
            
            render_encoder->endEncoding()
            command_buffer->presentDrawable(drawable)
            command_buffer->commit()
        }
    }
}
