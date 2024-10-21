const std = @import("std");

const Window = @import("window.zig").Window;
const c = @import("window.zig").c;
const RENDERBUFFER_SIZE = @import("window.zig").RENDERBUFFER_SIZE;
const WIDTH = @import("window.zig").WIDTH;
const HEIGHT = @import("window.zig").HEIGHT;
const OpenCLSolverWithSize = @import("opencl_solver.zig").OpenCLSolverWithSize;
const Obstacle = @import("common.zig").Obstacle;
const Oscillator = @import("common.zig").Oscillator;
const width = @import("simstate.zig").width;
const height = @import("simstate.zig").height;
const Simstate = @import("simstate.zig").Simstate;
pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const zoom_level = @max(@as(f32, @floatFromInt(width)) / WIDTH, @as(f32, @floatFromInt(height)) / HEIGHT);
    var window = try Window.init(WIDTH, HEIGHT, zoom_level, std.heap.c_allocator);
    const hole_width = 50;
    const hole_start = height / 2 - hole_width / 2;
    // const hole_end = height / 2 + hole_width / 2;
    var obstacles: [3]Obstacle = undefined;
    obstacles[0] = Obstacle{ .x = 3000, .y = 0, .width = 50, .height = hole_start - 20 };
    obstacles[1] = Obstacle{ .x = 3000, .y = hole_start, .width = 50, .height = hole_width };
    obstacles[2] = Obstacle{ .x = 3000, .y = hole_start + hole_width + 20, .width = 50, .height = height - (hole_start + hole_width + 20) };
    const oscillator_start = height / 2 - hole_width / 2;
    const oscillator_end = height / 2 + hole_width / 2;
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
            },
        ));
    }
    var solver = try OpenCLSolverWithSize(width, height).init(0.001, 1, 100, allocator); // Initialize the solver
    var simstate = try Simstate.init(allocator);
    try simstate.obstacles.appendSlice(&obstacles);
    try simstate.oscillators.appendSlice(oscillators.items);
    solver.on_simstate_update(&simstate);

    var event: c.SDL_Event = undefined;
    var keep_going = true;
    var iter: u32 = 0;
    const target_fps = 24;
    const ui_movement_scalor = 60 / target_fps;
    const estimated_solve_time: comptime_float = 0.6; // amortized solve time
    const estimated_present_time: comptime_float = 6; // amortized present time
    const solves_per_frame: comptime_int = @intFromFloat(@as(comptime_float, (1000 / target_fps - estimated_present_time)) / estimated_solve_time); // sub 1 ms, as it takes roughly 1ms to show results
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
            window.window_pos.y -= @intFromFloat(10 * window.zoom_level * ui_movement_scalor);
        }
        if (is_holding_down) {
            window.window_pos.y += @intFromFloat(10 * window.zoom_level * ui_movement_scalor);
        }
        if (is_holding_left) {
            window.window_pos.x -= @intFromFloat(10 * window.zoom_level * ui_movement_scalor);
        }
        if (is_holding_right) {
            window.window_pos.x += @intFromFloat(10 * window.zoom_level * ui_movement_scalor);
        }
        if (is_holding_zoom_in) {
            window.zoom_level *= 1 - (0.02 * ui_movement_scalor);
        }
        if (is_holding_zoom_out) {
            window.zoom_level *= 1 + (0.02 * ui_movement_scalor);
        }
        std.debug.print("\n\n --- Frame {} --- \n", .{iter});
        const target_frame_time: i64 = 1000 / target_fps;
        const start_solve_time = std.time.milliTimestamp();
        var solve_count: u32 = 0;
        var sleep_time: i64 = 0;
        if (!paused) {
            // while (std.time.milliTimestamp() - last_frame < target_frame_time) {
            solver.solve(solves_per_frame);
            solve_count += solves_per_frame;
            // std.debug.print("Delaying by: {}\n", .{target_frame_time - (std.time.milliTimestamp() - start_solve_time)});
            sleep_time = @intCast(@max(target_frame_time - @as(i64, estimated_present_time) - (std.time.milliTimestamp() - start_solve_time), 0));
            // }
        } else {
            sleep_time = target_frame_time - @as(i64, estimated_present_time);
        }
        c.SDL_Delay(@intCast(sleep_time));
        const end_solve_time = std.time.milliTimestamp();
        std.debug.print("Solve time: {}, sleep time: {}, solves: {}, solves / sec: {}\n", .{ end_solve_time - start_solve_time - sleep_time, sleep_time, solve_count, solve_count * target_fps });
        const start_present_time = std.time.milliTimestamp();

        window.draw_simdata(solver.read_simdata(simstate.simdata_scratch), width);

        for (obstacles) |obstacle| {
            window.draw_box_sim(
                .{ .x = @intCast(obstacle.x), .y = @intCast(obstacle.y) },
                .{ .x = @intCast(obstacle.x + obstacle.width), .y = @intCast(obstacle.y + obstacle.height) },
                0,
                0,
                0,
                255,
            );
        }
        window.draw_boundary(width, height);
        window.present();

        const end_present_time = std.time.milliTimestamp();
        std.debug.print("Present time: {}\n", .{end_present_time - start_present_time});
        const elapsed = std.time.milliTimestamp() - last_frame;
        std.debug.print("TOTAL Frame time: {}\n", .{elapsed});
        last_frame = std.time.milliTimestamp();
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
                        solver.reset(simstate.simdata_scratch);
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
