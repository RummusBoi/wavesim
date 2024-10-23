const std = @import("std");

const sqrt = std.math.sqrt;
const pow = std.math.pow;

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
const handle_events = @import("event_handler.zig").handle_events_with_size(width, height).handle_events;
const Appstate = @import("appstate.zig").Appstate;
const sim_to_camera_coord = @import("window.zig").sim_to_camera_coord;
pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var window = try Window.init(WIDTH, HEIGHT, std.heap.c_allocator);
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
    var iter: u32 = 0;
    const target_fps = 60;
    const estimated_solve_time: comptime_float = 0.6; // amortized solve time
    const estimated_present_time: comptime_float = 6; // amortized present time
    const solves_per_frame: comptime_int = @intFromFloat(@as(comptime_float, (1000 / target_fps - estimated_present_time)) / estimated_solve_time); // sub 1 ms, as it takes roughly 1ms to show results
    var last_frame = std.time.milliTimestamp();

    const simdata_scratch = simstate.alloc_scratch(f32, width * height);
    var appstate = Appstate{ .zoom_level = @max(@as(f32, @floatFromInt(width)) / WIDTH, @as(f32, @floatFromInt(height)) / HEIGHT) };
    while (appstate.keep_going) {
        iter += 1;

        handle_events(&appstate, &simstate, &solver);
        std.debug.print("\n\n --- Frame {} --- \n", .{iter});
        const target_frame_time: i64 = 1000 / target_fps;
        const start_solve_time = std.time.milliTimestamp();
        var solve_count: u32 = 0;
        var sleep_time: i64 = 0;
        if (!appstate.paused) {
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

        window.draw_simdata(solver.read_simdata(simdata_scratch), width, appstate.zoom_level, appstate.window_pos);

        for (obstacles) |obstacle| {
            const upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(obstacle.x), .y = @intCast(obstacle.y) });
            const lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(obstacle.x + obstacle.width), .y = @intCast(obstacle.y + obstacle.height) });
            window.draw_filled_box(
                .{ .x = @intCast(upper_left.x), .y = @intCast(upper_left.y) },
                .{ .x = @intCast(lower_right.x), .y = @intCast(lower_right.y) },
                0,
                0,
                0,
                255,
            );
        }
        const boundary_upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = 0, .y = 0 });
        const boundary_lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(width), .y = @intCast(height) });
        window.draw_box(
            .{ .x = boundary_upper_left.x, .y = boundary_upper_left.y },
            .{ .x = boundary_lower_right.x, .y = boundary_lower_right.y },
            255,
            0,
            0,
            255,
        );
        window.present();

        const end_present_time = std.time.milliTimestamp();
        std.debug.print("Present time: {}\n", .{end_present_time - start_present_time});
        const elapsed = std.time.milliTimestamp() - last_frame;
        std.debug.print("TOTAL Frame time: {}\n", .{elapsed});
        last_frame = std.time.milliTimestamp();
    }
}
