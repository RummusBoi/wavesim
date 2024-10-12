const std = @import("std");
const zig_opencl = @import("zig_opencl");
const cl = @import("zig_opencl");
const kernel_source = @embedFile("kernel.cl");

pub fn OpenCLSolverWithSize(width: u32, height: u32) type {
    _ = zig_opencl;
    return struct {
        data: []f32,
        dt: f32,
        grid_spacing: f32,
        propagation_speed: f32,
        oscillators: std.ArrayList(Oscillator),

        context: cl.Context,
        queue: cl.CommandQueue,
        kernel: cl.Kernel,
        buffer1: cl.Buffer(f32),
        buffer2: cl.Buffer(f32),
        buffer3: cl.Buffer(f32),
        obstacle_buffer: cl.Buffer(Obstacle),
        oscillator_buffer: cl.Buffer(Oscillator),
        oscillator_count: u32,
        obstacle_count: u32,
        elapsed: f32 = 0,
        iteration: u32 = 0,

        pub fn init(dt: f32, grid_spacing: f32, propagation_speed: f32, obstacles: []Obstacle, oscillators: []Oscillator, allocator: std.mem.Allocator) !@This() {
            if (propagation_speed * dt > grid_spacing) {
                return error.MaxPropagationSpeedExceeded;
            }
            std.debug.print("Propagation speed per timestep: {}\n", .{propagation_speed * dt});
            const platforms = try cl.getPlatforms(allocator);
            std.log.info("{} opencl platform(s) available", .{platforms.len});
            if (platforms.len == 0) {
                @panic("no opencl platforms available");
            }

            const platform, const device = found: for (platforms) |platform| {
                const platform_name = try platform.getName(allocator);

                const devices = try platform.getDevices(allocator, cl.DeviceType.all);
                for (devices) |device| {
                    const device_name = try device.getName(allocator);

                    std.log.info("selected platform '{s}' and device '{s}'", .{ platform_name, device_name });

                    break :found .{ platform, device };
                }
            } else {
                @panic("failed to select platform and device");
            };

            const context = try cl.createContext(&.{device}, .{ .platform = platform });

            const queue = try cl.createCommandQueue(context, device, .{ .profiling = true });

            std.log.info("compiling kernel...", .{});

            const program = try cl.createProgramWithSource(context, kernel_source);
            defer program.release();

            program.build(
                &.{device},
                "-cl-std=CL3.0",
            ) catch |err| {
                if (err == error.BuildProgramFailure) {
                    const log = try program.getBuildLog(allocator, device);
                    defer allocator.free(log);
                    std.log.err("failed to compile kernel:\n{s}", .{log});
                }

                return err;
            };

            const kernel = try cl.createKernel(program, "wavesim");

            const data: []f32 = try allocator.alloc(f32, width * height);

            const buffer1 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);
            const buffer2 = try cl.createBufferWithData(f32, context, .{ .read_write = true }, data);
            const buffer3 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);

            const obstacle_buffer = try cl.createBufferWithData(Obstacle, context, .{ .read_write = true }, obstacles);
            const oscillator_buffer = try cl.createBufferWithData(Oscillator, context, .{ .read_write = true }, oscillators);

            return @This(){
                .data = data,
                .dt = dt,
                .grid_spacing = grid_spacing,
                .propagation_speed = propagation_speed,
                .oscillators = std.ArrayList(Oscillator).init(allocator),
                .context = context,
                .queue = queue,
                .kernel = kernel,
                .buffer1 = buffer1,
                .buffer2 = buffer2,
                .buffer3 = buffer3,
                .obstacle_buffer = obstacle_buffer,
                .obstacle_count = @intCast(obstacles.len),
                .oscillator_buffer = oscillator_buffer,
                .oscillator_count = @intCast(oscillators.len),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.context.release();
            self.queue.release();
            self.kernel.release();
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
        ) !void {
            std.debug.print("Solving\n", .{});
            // for (self.oscillators.items) |oscillator| {
            //     var wavelength_sum: f32 = 0.0;
            //     for (oscillator.wavelengths.items) |wl| {
            //         // const frequency = self.propagation_speed / wl;
            //         wavelength_sum += std.math.sin(1 / wl * self.elapsed * self.propagation_speed * std.math.pi);
            //     }
            //     self.data[oscillator.y * width + oscillator.x] = oscillator.amplitude * wavelength_sum;
            // }
            // for (self.obstacles.items) |obstacle| {
            //     for (obstacle.y..obstacle.y + obstacle.height) |y| {
            //         for (obstacle.x..obstacle.x + obstacle.width) |x| {
            //             self.data[y * width + x] = 0;
            //         }
            //     }
            // }

            const offset: u32 = @rem(self.iteration, 3);

            try self.kernel.setArg(@TypeOf(self.buffer1), @rem(0 + offset, 3), self.buffer1);
            try self.kernel.setArg(@TypeOf(self.buffer2), @rem(1 + offset, 3), self.buffer2);
            try self.kernel.setArg(@TypeOf(self.buffer3), @rem(2 + offset, 3), self.buffer3);

            try self.kernel.setArg(@TypeOf(width), 3, width);
            try self.kernel.setArg(@TypeOf(height), 4, height);
            try self.kernel.setArg(@TypeOf(self.grid_spacing), 5, self.grid_spacing);
            try self.kernel.setArg(@TypeOf(self.dt), 6, self.dt);
            try self.kernel.setArg(@TypeOf(self.propagation_speed), 7, self.propagation_speed);
            try self.kernel.setArg(@TypeOf(self.iteration), 8, self.iteration);
            try self.kernel.setArg(@TypeOf(self.obstacle_buffer), 9, self.obstacle_buffer);
            try self.kernel.setArg(@TypeOf(self.obstacle_count), 10, self.obstacle_count);
            try self.kernel.setArg(@TypeOf(self.oscillator_buffer), 11, self.oscillator_buffer);
            try self.kernel.setArg(@TypeOf(self.oscillator_count), 12, self.oscillator_count);
            std.debug.print("Running kernel..\n", .{});
            const start_kernel = std.time.microTimestamp();

            const complete = try self.queue.enqueueNDRangeKernel(
                self.kernel,
                null,
                &.{width * height},
                &.{256},
                &.{},
            );
            try cl.waitForEvents(&.{complete});
            defer complete.release();
            const end_kernel = std.time.microTimestamp();
            std.debug.print("Kernel time: {}\n", .{end_kernel - start_kernel});
            try cl.waitForEvents(&.{complete});
            // const start_read = std.time.microTimestamp();
            // const read_complete = try self.queue.enqueueReadBuffer(
            //     f32,
            //     data_buffer,
            //     false,
            //     0,
            //     self.data,
            //     &.{complete},
            // );
            // defer read_complete.release();
            // try cl.waitForEvents(&.{read_complete});
            // const end_read = std.time.microTimestamp();

            // std.debug.print("Read time: {}\n", .{end_read - start_read});

            self.elapsed += self.dt;
            self.iteration += 1;
        }

        pub fn read_simdata(self: *@This()) ![]f32 {
            const buffer_to_read = blk: {
                if (@rem(self.iteration, 3) == 0) {
                    break :blk self.buffer1;
                } else if (@rem(self.iteration, 3) == 1) {
                    break :blk self.buffer2;
                } else {
                    break :blk self.buffer3;
                }
            };
            const start_read = std.time.microTimestamp();
            const read_complete = try self.queue.enqueueReadBuffer(
                f32,
                buffer_to_read,
                false,
                0,
                self.data,
                &.{},
            );
            defer read_complete.release();
            try cl.waitForEvents(&.{read_complete});
            const end_read = std.time.microTimestamp();

            std.debug.print("Read time: {}\n", .{end_read - start_read});
            return self.data;
        }
    };
}
pub const Oscillator = struct {
    x: u32,
    y: u32,
    amplitude: f32,
    wavelengths: [5]f32,
    pub fn init(x: u32, y: u32, amplitude: f32, wavelengths: []const f32) !Oscillator {
        var wavelength_array: [5]f32 = undefined;
        std.mem.copyForwards(f32, &wavelength_array, wavelengths);
        return Oscillator{
            .x = x,
            .y = y,
            .amplitude = amplitude,
            .wavelengths = wavelength_array,
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
