const std = @import("std");
const zig_opencl = @import("zig_opencl");

pub fn SolverWithSize(width: u32, height: u32) type {
    _ = zig_opencl;
    return struct {
        data: []f32,
        prev_data: []f32,
        tmp_data: []f32,
        dt: f32,
        grid_spacing: f32,
        propagation_speed: f32,
        oscillators: std.ArrayList(Oscillator),
        obstacles: std.ArrayList(Obstacle),

        elapsed: f32,

        pub fn init(dt: f32, grid_spacing: f32, propagation_speed: f32, allocator: *std.mem.Allocator) !@This() {
            if (propagation_speed * dt > grid_spacing) {
                return error.MaxPropagationSpeedExceeded;
            }
            std.debug.print("Propagation speed per timestep: {}\n", .{propagation_speed * dt});
            const data: []f32 = try allocator.alloc(f32, width * height);
            const prev_data: []f32 = try allocator.alloc(f32, width * height);
            const tmp_data: []f32 = try allocator.alloc(f32, width * height);

            return @This(){
                .data = data,
                .prev_data = prev_data,
                .tmp_data = tmp_data,
                .dt = dt,
                .grid_spacing = grid_spacing,
                .propagation_speed = propagation_speed,
                .oscillators = std.ArrayList(Oscillator).init(allocator.*),
                .obstacles = std.ArrayList(Obstacle).init(allocator.*),
                .elapsed = 0,
            };
        }

        pub fn solve_until_time(
            self: *@This(),
            time: f32,
        ) void {
            var iteration_count: u32 = 0;
            while (self.elapsed < time) {
                iteration_count += 1;
                self.solve();
            }
            std.debug.print("Iterations: {}\n", .{iteration_count});
        }

        pub fn solve(
            self: *@This(),
        ) void {
            const start = std.time.milliTimestamp();
            self.elapsed += self.dt;
            for (self.oscillators.items) |oscillator| {
                var wavelength_sum: f32 = 0.0;
                for (oscillator.wavelengths.items) |wl| {
                    // const frequency = self.propagation_speed / wl;
                    wavelength_sum += std.math.sin(1 / wl * self.elapsed * self.propagation_speed * std.math.pi);
                }
                self.data[oscillator.y * width + oscillator.x] = oscillator.amplitude * wavelength_sum;
            }
            for (self.obstacles.items) |obstacle| {
                for (obstacle.y..obstacle.y + obstacle.height) |y| {
                    for (obstacle.x..obstacle.x + obstacle.width) |x| {
                        self.data[y * width + x] = 0;
                    }
                }
            }
            for (0..height) |y| {
                for (0..width) |x| {
                    const derivative = self.compute_second_derivative(@intCast(x), @intCast(y));
                    const new_value = self.propagation_speed * self.propagation_speed * derivative * self.dt * self.dt + 2 * self.data[y * width + x] - self.prev_data[y * width + x];
                    var modifier: f32 = 0;
                    const bound: f32 = 0.1;
                    if (x > (1 - bound) * width or x < bound * width or y > (1 - bound) * height or y < bound * height) {
                        modifier = 0.999;
                    } else {
                        modifier = 1;
                    }
                    self.tmp_data[y * width + x] = new_value * modifier;
                }
            }
            const tmp = self.prev_data;
            self.prev_data = self.data;
            self.data = self.tmp_data;
            self.tmp_data = tmp;
            const elapsed = std.time.milliTimestamp() - start;
            std.debug.print("Solving took: {}\n", .{elapsed});
        }

        fn compute_second_derivative(self: *@This(), x_coord: u32, y_coord: u32) f32 {
            const x: i32 = @intCast(x_coord);
            const y: i32 = @intCast(y_coord);
            const first_part = (self.data[@intCast(@max(y * width + x - 1, 0))] + self.data[@intCast(@min(y * width + x + 1, width * height - 1))] + self.data[@intCast(@max((y - 1) * width + x, 0))] + self.data[@intCast(@min((y + 1) * width + x, width * height - 1))] - self.data[@intCast(y * width + x)] * 4.0);
            const divisor = self.grid_spacing * self.grid_spacing;
            return first_part / divisor;
        }
    };
}
pub const Oscillator = struct {
    x: u32,
    y: u32,
    amplitude: f32,
    wavelengths: std.ArrayList(f32),
    pub fn init(x: u32, y: u32, amplitude: f32, wavelengths: []const f32, allocator: *std.mem.Allocator) !Oscillator {
        var wavelength_arr = std.ArrayList(f32).init(allocator.*);
        try wavelength_arr.appendSlice(wavelengths);
        return Oscillator{
            .x = x,
            .y = y,
            .amplitude = amplitude,
            .wavelengths = wavelength_arr,
        };
    }
    pub fn deinit(self: *Oscillator) void {
        self.frequencies.deinit();
    }
    // phase: f32,
};

pub const Obstacle = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};
