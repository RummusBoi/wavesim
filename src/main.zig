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
const UI = @import("ui.zig").UI;
const generate_ui = @import("ui.zig").generate_ui_with_size(width, height).update_ui;
pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var window = try Window.init(WIDTH, HEIGHT, std.heap.c_allocator);
    const hole_width = 200;
    const hole_start = height / 2 - hole_width / 2;

    const oscillator_start = height / 2 - hole_width / 2;
    const oscillator_end = height / 2 + hole_width / 2;
    const oscillator_count = 100;

    var solver = try OpenCLSolverWithSize(width, height).init(0.005, 1, 100, allocator); // Initialize the solver
    var simstate = try Simstate.init(allocator);
    _ = try simstate.create_obstacle(3000, 0, 50, hole_start - 20);
    _ = try simstate.create_obstacle(3000, hole_start, 50, hole_width);
    _ = try simstate.create_obstacle(3000, hole_start + hole_width + 20, 50, height - (hole_start + hole_width + 20));
    for (0..oscillator_count) |i| {
        const i_f: f32 = @floatFromInt(i);
        const oscillator_count_f: f32 = @floatFromInt(oscillator_count);
        _ = try simstate.create_oscillator(
            3500,
            oscillator_start + @as(u32, @intFromFloat((oscillator_end - oscillator_start) * i_f / oscillator_count_f)),
            1,
            &[_]f32{
                60,
                20,
                100,
            },
        );
    }
    solver.on_simstate_update(&simstate);
    var iter: u32 = 0;
    const target_fps = 60;
    const estimated_solve_time: comptime_float = 0.6; // amortized solve time
    const estimated_present_time: comptime_float = 6; // amortized present time
    const solves_per_frame: comptime_int = @intFromFloat(@as(comptime_float, (1000 / target_fps - estimated_present_time)) / estimated_solve_time); // sub 1 ms, as it takes roughly 1ms to show results
    var last_frame = std.time.milliTimestamp();

    const simdata_scratch = simstate.alloc_scratch(f32, width * height);
    var appstate = Appstate{ .zoom_level = @max(@as(f32, @floatFromInt(width)) / WIDTH, @as(f32, @floatFromInt(height)) / HEIGHT) };
    var ui: UI = UI{};
    const do_frame_prints = false;
    while (appstate.keep_going) {
        iter += 1;

        handle_events(&ui, &appstate, &simstate, &solver);

        if (appstate.updates.simstate) {
            solver.on_simstate_update(&simstate);
        }
        if (do_frame_prints) std.debug.print("\n\n --- Frame {} --- \n", .{iter});

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

        if (do_frame_prints) std.debug.print("Solve time: {}, sleep time: {}, solves: {}, solves / sec: {}\n", .{ end_solve_time - start_solve_time - sleep_time, sleep_time, solve_count, solve_count * target_fps });
        const start_present_time = std.time.milliTimestamp();

        try window.draw_simdata(solver.read_simdata(simdata_scratch), width, appstate.zoom_level, appstate.window_pos);
        generate_ui(&simstate, &appstate, &ui);
        window.draw_ui(&ui);

        window.present();

        const end_present_time = std.time.milliTimestamp();
        if (do_frame_prints) std.debug.print("Present time: {}\n", .{end_present_time - start_present_time});
        const elapsed = std.time.milliTimestamp() - last_frame;
        if (do_frame_prints) std.debug.print("TOTAL Frame time: {}\n", .{elapsed});

        last_frame = std.time.milliTimestamp();
        // c.SDL_Delay(100);
    }
}
