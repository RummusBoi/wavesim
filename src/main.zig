const std = @import("std");

const Window = @import("window.zig").Window;
const c = @import("window.zig").c;
const RENDERBUFFER_SIZE = @import("window.zig").RENDERBUFFER_SIZE;
const WIDTH = @import("window.zig").WIDTH;
const HEIGHT = @import("window.zig").HEIGHT;
const SolverWithSize = @import("solver.zig").SolverWithSize;
const Oscillator = @import("solver.zig").Oscillator;
const Obstacle = @import("solver.zig").Obstacle;

pub fn main() !void {
    var window = try Window.init(WIDTH, HEIGHT, std.heap.c_allocator);
    var allocator = std.heap.c_allocator;
    var solver = try SolverWithSize(1000, 500).init(0.01, 1, 30, &allocator); // Initialize the solver
    try window.show_simdata(solver.data, 1000);
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
    const oscillator_start = 200;
    const oscillator_end = 300;
    const oscillator_count = 100;
    for (0..oscillator_count) |i| {
        try solver.oscillators.append(try Oscillator.init(
            850,
            oscillator_start + @as(u32, @intCast(i)) * (oscillator_end - oscillator_start) / oscillator_count,
            100,
            &[_]f32{ 2, 20 }, //, 1, 2 },
            &allocator,
        ));
    }
    const hole_start = 200;
    const hole_end = 300;
    try solver.obstacles.append(Obstacle{ .x = 450, .y = 0, .width = 250, .height = hole_start });
    try solver.obstacles.append(Obstacle{ .x = 450, .y = hole_end, .width = 250, .height = 500 - hole_end });
    var event: c.SDL_Event = undefined;
    var keep_going = true;
    var iter: u32 = 0;
    const target_fps = 60;
    var last_frame = std.time.milliTimestamp();
    while (keep_going) {
        iter += 1;

        const target_frame_time: i64 = 1000 / target_fps;
        while (std.time.milliTimestamp() - last_frame < target_frame_time) {
            solver.solve();
        }
        try window.show_simdata(solver.data, 1000);
        const elapsed = std.time.milliTimestamp() - last_frame;
        std.debug.print("Frametime without sleep: {}\n", .{elapsed});
        last_frame = std.time.milliTimestamp();
        // c.SDL_Delay(100);
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    keep_going = false;
                    break;
                },
                c.SDL_KEYDOWN => {
                    const scancode = event.key.keysym.scancode;
                    if (scancode == c.SDL_SCANCODE_ESCAPE) {
                        keep_going = false;
                        break;
                    }
                    if (scancode == c.SDL_SCANCODE_LEFT) {
                        window.window_pos.x -= 10;
                    }
                    if (scancode == c.SDL_SCANCODE_RIGHT) {
                        window.window_pos.x += 10;
                    }
                    if (scancode == c.SDL_SCANCODE_UP) {
                        window.window_pos.y -= 10;
                    }
                    if (scancode == c.SDL_SCANCODE_DOWN) {
                        window.window_pos.y += 10;
                    }

                    if (event.key.keysym.sym == c.SDLK_PLUS) {
                        window.zoom_level -= 0.03;
                    }
                    if (event.key.keysym.sym == c.SDLK_MINUS) {
                        window.zoom_level += 0.03;
                    }

                    // if (scancode == sheet_window.c.SDL_SCANCODE_LEFT or
                    //     scancode == sheet_window.c.SDL_SCANCODE_RIGHT or
                    //     scancode == sheet_window.c.SDL_SCANCODE_UP or
                    //     scancode == sheet_window.c.SDL_SCANCODE_DOWN)
                    // {}
                },
                else => {},
            }
        }
    }
}
