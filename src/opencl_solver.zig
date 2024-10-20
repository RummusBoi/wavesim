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
        obstacles: std.ArrayList(Obstacle),
        context: cl.Context,
        queue: cl.CommandQueue,
        main_kernel: cl.Kernel,
        obstacle_kernel: cl.Kernel,
        oscillator_kernel: cl.Kernel,
        buffer1: cl.Buffer(f32),
        buffer2: cl.Buffer(f32),
        buffer3: cl.Buffer(f32),
        obstacle_buffer: cl.Buffer(Coordinate),
        oscillator_buffer: cl.Buffer(Oscillator),

        elapsed: f32 = 0,
        iteration: u32 = 0,
        total_kernel_time: i64 = 0,
        total_waiting_time: i64 = 0,

        pub fn init(dt: f32, grid_spacing: f32, propagation_speed: f32, obstacles: []Obstacle, oscillators: []Oscillator, allocator: std.mem.Allocator) !@This() {
            if (propagation_speed * dt > grid_spacing) {
                return error.MaxPropagationSpeedExceeded;
            }
            // std.debug.print("Propagation speed per timestep: {}\n", .{propagation_speed * dt});
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

            const queue = try cl.createCommandQueue(context, device, .{ .profiling = false });

            std.log.info("compiling kernel...", .{});

            const program = try cl.createProgramWithSource(context, kernel_source);
            defer program.release();

            program.build(
                &.{device},
                "-cl-std=CL3.0 -cl-unsafe-math-optimizations -cl-mad-enable",
            ) catch |err| {
                if (err == error.BuildProgramFailure) {
                    const log = try program.getBuildLog(allocator, device);
                    defer allocator.free(log);
                    std.log.err("failed to compile kernel:\n{s}", .{log});
                }

                return err;
            };

            const main_kernel = try cl.createKernel(program, "wavesim");
            const obstacle_kernel = try cl.createKernel(program, "compute_obstacles");
            const oscillator_kernel = try cl.createKernel(program, "compute_oscillators");

            const data: []f32 = try allocator.alloc(f32, width * height);
            for (data, 0..) |_, index| {
                data[index] = 0;
            }

            const buffer1 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);
            const buffer2 = try cl.createBufferWithData(f32, context, .{ .read_write = true }, data);
            const buffer3 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);

            var obstacle_bfr = std.ArrayList(Coordinate).init(allocator);

            for (obstacles) |obstacle| {
                for (obstacle.y..obstacle.y + obstacle.height) |y| {
                    for (obstacle.x..obstacle.x + obstacle.width) |x| {
                        try obstacle_bfr.append(.{ .x = @intCast(x), .y = @intCast(y) });
                    }
                }
            }
            const obstacle_buffer = try cl.createBuffer(Coordinate, context, .{ .read_write = true }, @max(obstacle_bfr.items.len, 1));
            const oscillator_buffer = try cl.createBuffer(Oscillator, context, .{ .read_write = true }, 100);

            if (obstacle_bfr.items.len > 0) {
                _ = try queue.enqueueWriteBuffer(Coordinate, obstacle_buffer, true, 0, obstacle_bfr.items, &.{});
            }

            if (oscillators.len > 0) {
                _ = try queue.enqueueWriteBuffer(Oscillator, oscillator_buffer, true, 0, oscillators, &.{});
            }

            try main_kernel.setArg(@TypeOf(width), 3, width);
            try main_kernel.setArg(@TypeOf(height), 4, height);
            try main_kernel.setArg(@TypeOf(grid_spacing), 5, grid_spacing);
            try main_kernel.setArg(@TypeOf(dt), 6, dt);
            try main_kernel.setArg(@TypeOf(propagation_speed), 7, propagation_speed);

            try oscillator_kernel.setArg(@TypeOf(width), 1, width);
            try oscillator_kernel.setArg(@TypeOf(dt), 2, dt);
            try oscillator_kernel.setArg(@TypeOf(propagation_speed), 3, propagation_speed);
            try oscillator_kernel.setArg(@TypeOf(oscillator_buffer), 5, oscillator_buffer);

            try obstacle_kernel.setArg(@TypeOf(width), 1, width);
            try obstacle_kernel.setArg(@TypeOf(height), 2, height);
            try obstacle_kernel.setArg(@TypeOf(obstacle_buffer), 3, obstacle_buffer);
            var owned_oscillators = std.ArrayList(Oscillator).init(allocator);
            try owned_oscillators.appendSlice(oscillators);
            var owned_obstacles = std.ArrayList(Obstacle).init(allocator);
            try owned_obstacles.appendSlice(obstacles);
            return @This(){
                .data = data,
                .dt = dt,
                .grid_spacing = grid_spacing,
                .propagation_speed = propagation_speed,
                .oscillators = owned_oscillators,
                .obstacles = owned_obstacles,
                .context = context,
                .queue = queue,
                .main_kernel = main_kernel,
                .obstacle_kernel = obstacle_kernel,
                .oscillator_kernel = oscillator_kernel,
                .buffer1 = buffer1,
                .buffer2 = buffer2,
                .buffer3 = buffer3,
                .obstacle_buffer = obstacle_buffer,
                .oscillator_buffer = oscillator_buffer,
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
            // std.debug.print("Iterations: {}\n", .{iteration_count});
        }

        pub fn solve(
            self: *@This(),
        ) !void {
            // std.debug.print("Solving\n", .{});
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

            try self.main_kernel.setArg(@TypeOf(self.buffer1), @rem(0 + self.iteration, 3), self.buffer1); // data
            try self.main_kernel.setArg(@TypeOf(self.buffer2), @rem(1 + self.iteration, 3), self.buffer2); // prev_data
            try self.main_kernel.setArg(@TypeOf(self.buffer3), @rem(2 + self.iteration, 3), self.buffer3); // tmp_data

            // try self.main_kernel.setArg(@TypeOf(self.iteration), 7, self.iteration);
            try self.oscillator_kernel.setArg(@TypeOf(self.iteration), 4, self.iteration);

            if (@rem(self.iteration, 3) == 0) {
                try self.oscillator_kernel.setArg(@TypeOf(self.buffer3), 0, self.buffer3);
                try self.obstacle_kernel.setArg(@TypeOf(self.buffer3), 0, self.buffer3);
            } else if (@rem(self.iteration, 3) == 1) {
                try self.oscillator_kernel.setArg(@TypeOf(self.buffer2), 0, self.buffer2);
                try self.obstacle_kernel.setArg(@TypeOf(self.buffer2), 0, self.buffer2);
            } else {
                try self.oscillator_kernel.setArg(@TypeOf(self.buffer1), 0, self.buffer1);
                try self.obstacle_kernel.setArg(@TypeOf(self.buffer1), 0, self.buffer1);
            }

            const start_queuing = std.time.microTimestamp();
            // completes[0] = try self.queue.enqueueNDRangeKernel(
            //     self.kernel,
            //     null,
            //     &.{width * height},
            //     &.{256},
            //     &.{},
            // );
            // for (1..count) |i| {
            const main_kernel_event = try self.queue.enqueueNDRangeKernel(
                self.main_kernel,
                null,
                &.{width * height - 2 * width},
                null,
                &.{},
            );

            const start_waiting = std.time.microTimestamp();
            var obstacle_kernel_event: ?cl.Event = null;
            var oscillator_kernel_event: ?cl.Event = null;
            if (self.obstacles.items.len > 0) {
                var obstacle_pixel_count: u32 = 0;
                for (self.obstacles.items) |obstacle| {
                    obstacle_pixel_count += obstacle.width * obstacle.height;
                }
                obstacle_kernel_event = try self.queue.enqueueNDRangeKernel(
                    self.obstacle_kernel,
                    null,
                    &.{obstacle_pixel_count},
                    null,
                    &.{main_kernel_event},
                );
            }
            if (self.oscillators.items.len > 0) {
                oscillator_kernel_event = try self.queue.enqueueNDRangeKernel(
                    self.oscillator_kernel,
                    null,
                    &.{self.oscillators.items.len},
                    null,
                    &.{main_kernel_event},
                );
            }
            if (obstacle_kernel_event) |event| {
                defer event.release();
                try cl.waitForEvents(&.{event});
            }
            const end_kernel = std.time.microTimestamp();

            // std.debug.print("Kernel time: {}\n", .{end_kernel - start_kernel});
            self.total_kernel_time += end_kernel - start_queuing;
            self.total_waiting_time += end_kernel - start_waiting;
            // std.debug.print("Average kernel time: {} ({} per task)\n", .{ @divFloor(self.total_kernel_time, self.iteration + 1), @divFloor(@divFloor(self.total_kernel_time, self.iteration + 1), 1) });
            // std.debug.print("Average waiting time: {}\n", .{@divFloor(self.total_waiting_time, self.iteration + 1)});

            self.elapsed += self.dt;
            self.iteration += 1;
        }

        pub fn reset(self: *@This()) !void {
            self.elapsed = 0;
            self.iteration = 0;
            for (self.data, 0..) |_, index| {
                self.data[index] = 0;
            }
            const b1 = try self.queue.enqueueWriteBuffer(
                f32,
                self.buffer1,
                false,
                0,
                self.data,
                &.{},
            );
            const b2 = try self.queue.enqueueWriteBuffer(
                f32,
                self.buffer2,
                false,
                0,
                self.data,
                &.{},
            );
            const b3 = try self.queue.enqueueWriteBuffer(
                f32,
                self.buffer3,
                false,
                0,
                self.data,
                &.{},
            );
            try cl.waitForEvents(&.{ b1, b2, b3 });
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
            // const start_read = std.time.microTimestamp();
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
            // const end_read = std.time.microTimestamp();

            // std.debug.print("Read time: {}\n", .{end_read - start_read});
            return self.data;
        }
    };
}
pub const Oscillator = struct {
    x: u32,
    y: u32,
    amplitude: f32,
    wavelengths: [5]f32,
    wavelength_count: u32,
    pub fn init(x: u32, y: u32, amplitude: f32, wavelengths: []const f32) !Oscillator {
        var wavelength_array: [5]f32 = undefined;
        std.mem.copyForwards(f32, &wavelength_array, wavelengths);
        return Oscillator{
            .x = x,
            .y = y,
            .amplitude = amplitude,
            .wavelengths = wavelength_array,
            .wavelength_count = @intCast(wavelengths.len),
        };
    }
    pub fn deinit(self: *Oscillator) void {
        self.frequencies.deinit();
    }
};

pub const Coordinate = struct {
    x: u32,
    y: u32,
};

pub const Obstacle = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};
