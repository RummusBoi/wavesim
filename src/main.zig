const std = @import("std");

const Window = @import("window.zig").Window;
const c = @import("window.zig").c;
const RENDERBUFFER_SIZE = @import("window.zig").RENDERBUFFER_SIZE;
const WIDTH = @import("window.zig").WIDTH;
const HEIGHT = @import("window.zig").HEIGHT;
const OpenCLSolverWithSize = @import("opencl_solver.zig").OpenCLSolverWithSize;
const Oscillator = @import("opencl_solver.zig").Oscillator;
const Obstacle = @import("opencl_solver.zig").Obstacle;

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const simwidth = 4000;
    const simheight = 2048;
    const zoom_level = @max(@as(f32, @floatFromInt(simwidth)) / WIDTH, @as(f32, @floatFromInt(simheight)) / HEIGHT);
    var window = try Window.init(WIDTH, HEIGHT, zoom_level, std.heap.c_allocator);
    const hole_width = 50;
    const hole_start = simheight / 2 - hole_width / 2;
    // const hole_end = simheight / 2 + hole_width / 2;
    var obstacles: [3]Obstacle = undefined;
    obstacles[0] = Obstacle{ .x = 3000, .y = 0, .width = 50, .height = hole_start - 20 };
    obstacles[1] = Obstacle{ .x = 3000, .y = hole_start, .width = 50, .height = hole_width };
    obstacles[2] = Obstacle{ .x = 3000, .y = hole_start + hole_width + 20, .width = 50, .height = simheight - (hole_start + hole_width + 20) };
    const oscillator_start = simheight / 2 - hole_width / 2;
    const oscillator_end = simheight / 2 + hole_width / 2;
    const oscillator_count = 100;
    var oscillators = std.ArrayList(Oscillator).init(allocator);
    for (0..oscillator_count) |i| {
        const i_f: f32 = @floatFromInt(i);
        const oscillator_count_f: f32 = @floatFromInt(oscillator_count);
        try oscillators.append(try Oscillator.init(
            3500,
            oscillator_start + @as(u32, @intFromFloat((oscillator_end - oscillator_start) * i_f / oscillator_count_f)),
            1000,
            &[_]f32{
                10,
            }, //, 1, 2 },
        ));
    }
    var solver = try OpenCLSolverWithSize(simwidth, simheight).init(0.001, 1, 100, &obstacles, oscillators.items, allocator); // Initialize the solver
    try window.draw_simdata(solver.data, simwidth);
    // const spacing = 20;

    // solver.data[RENDERBUFFER_SIZE / 2 + WIDTH / 2 - 2 * spacing] = 100;
    // solver.data[RENDERBUFFER_SIZE / 2 + WIDTH / 2 - spacing] = 100;
    // solver.data[RENDERBUFFER_SIZE / 2 + WIDTH / 2 + spacing * 0] = 100;
    // solver.data[RENDERBUFFER_SIZE / 2 + WIDTH / 2 + 1 * spacing] = 100;
    // solver.data[RENDERBUFFER_SIZE / 2 + WIDTH / 2 + 2 * spacing] = 100;
    // wavelength is c / f. Meaning that:
    // for
    //  f = 0.1: wavelength = 2 / 0.1 = 20
    //  f = 0.5: wavelength = 2 / 0.5 = 4
    //  f = 1: wavelength = 2 / 1 = 2
    //  f = 2: wavelength = 2 / 2 = 1

    var event: c.SDL_Event = undefined;
    var keep_going = true;
    var iter: u32 = 0;
    const target_fps = 60;
    var last_frame = std.time.milliTimestamp();
    var paused = false;
    var is_holding_up = false;
    var is_holding_down = false;
    var is_holding_left = false;
    var is_holding_right = false;
    var is_holding_zoom_in = false;
    var is_holding_zoom_out = false;
    var is_holding_left_button = false;

    while (keep_going) {
        iter += 1;
        if (is_holding_up) {
            window.window_pos.y -= @intFromFloat(10 * window.zoom_level);
        }
        if (is_holding_down) {
            window.window_pos.y += @intFromFloat(10 * window.zoom_level);
        }
        if (is_holding_left) {
            window.window_pos.x -= @intFromFloat(10 * window.zoom_level);
        }
        if (is_holding_right) {
            window.window_pos.x += @intFromFloat(10 * window.zoom_level);
        }
        if (is_holding_zoom_in) {
            window.zoom_level *= 0.98;
        }
        if (is_holding_zoom_out) {
            window.zoom_level *= 1.02;
        }
        std.debug.print("\n\n --- Frame {} --- \n", .{iter});
        const target_frame_time: i64 = 1000 / target_fps;
        const start_solve_time = std.time.milliTimestamp();
        var solve_count: u32 = 0;
        if (!paused) {
            while (std.time.milliTimestamp() - last_frame < target_frame_time) {
                try solver.solve();
                solve_count += 1;
            }
        } else {
            c.SDL_Delay(@intCast(target_frame_time));
        }
        const end_solve_time = std.time.milliTimestamp();
        std.debug.print("Solve time: {}, solves: {}\n", .{ end_solve_time - start_solve_time, solve_count });
        const start_present_time = std.time.milliTimestamp();

        try window.draw_simdata(try solver.read_simdata(), simwidth);

        for (solver.obstacles.items) |obstacle| {
            window.draw_box(
                .{ .x = @intCast(obstacle.x), .y = @intCast(obstacle.y) },
                .{ .x = @intCast(obstacle.x + obstacle.width), .y = @intCast(obstacle.y + obstacle.height) },
                0,
                0,
                0,
                255,
            );
        }
        window.draw_boundary(simwidth, simheight);
        window.present();

        const end_present_time = std.time.milliTimestamp();
        std.debug.print("Present time: {}\n", .{end_present_time - start_present_time});
        const elapsed = std.time.milliTimestamp() - last_frame;
        std.debug.print("TOTAL Frame time: {}\n", .{elapsed});
        last_frame = std.time.milliTimestamp();
        // c.SDL_Delay(100);
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    keep_going = false;
                    break;
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        is_holding_left_button = true;
                    }
                },
                c.SDL_MOUSEBUTTONUP => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        is_holding_left_button = false;
                    }
                },
                c.SDL_MOUSEMOTION => {
                    if (is_holding_left_button) {
                        window.window_pos.x -= @intFromFloat(@as(f32, @floatFromInt(event.motion.xrel)) * window.zoom_level);
                        window.window_pos.y -= @intFromFloat(@as(f32, @floatFromInt(event.motion.yrel)) * window.zoom_level);
                    }
                },
                c.SDL_KEYDOWN => {
                    const scancode = event.key.keysym.scancode;
                    if (scancode == c.SDL_SCANCODE_ESCAPE) {
                        keep_going = false;
                        break;
                    }
                    if (scancode == c.SDL_SCANCODE_LEFT) {
                        is_holding_left = true;
                    }
                    if (scancode == c.SDL_SCANCODE_RIGHT) {
                        is_holding_right = true;
                    }
                    if (scancode == c.SDL_SCANCODE_UP) {
                        is_holding_up = true;
                    }
                    if (scancode == c.SDL_SCANCODE_DOWN) {
                        is_holding_down = true;
                    }

                    if (event.key.keysym.sym == c.SDLK_PLUS) {
                        is_holding_zoom_in = true;
                    }
                    if (event.key.keysym.sym == c.SDLK_MINUS) {
                        is_holding_zoom_out = true;
                    }
                    if (event.key.keysym.sym == c.SDLK_r) {
                        try solver.reset();
                    }
                    if (event.key.keysym.sym == c.SDLK_SPACE) {
                        paused = !paused;
                    }
                },
                c.SDL_KEYUP => {
                    const scancode = event.key.keysym.scancode;

                    if (scancode == c.SDL_SCANCODE_LEFT) {
                        is_holding_left = false;
                    }
                    if (scancode == c.SDL_SCANCODE_RIGHT) {
                        is_holding_right = false;
                    }
                    if (scancode == c.SDL_SCANCODE_UP) {
                        is_holding_up = false;
                    }
                    if (scancode == c.SDL_SCANCODE_DOWN) {
                        is_holding_down = false;
                    }
                    if (event.key.keysym.sym == c.SDLK_PLUS) {
                        is_holding_zoom_in = false;
                    }
                    if (event.key.keysym.sym == c.SDLK_MINUS) {
                        is_holding_zoom_out = false;
                    }
                },
                else => {},
            }
        }
    }
}
