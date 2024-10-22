const std = @import("std");
const zig_opencl = @import("zig_opencl");
const cl = @import("zig_opencl");
const kernel_source = @embedFile("kernel.cl");
const Oscillator = @import("common.zig").Oscillator;
const Obstacle = @import("common.zig").Obstacle;
const Coordinate = @import("common.zig").Coordinate;
const Simstate = @import("simstate.zig").Simstate;
const alloc_scratch = @import("simstate.zig").alloc_scratch;

pub fn OpenCLSolverWithSize(width: u32, height: u32) type {
    _ = zig_opencl;
    return struct {
        dt: f32,
        grid_spacing: f32,
        propagation_speed: f32,
        context: cl.Context,
        queue: cl.CommandQueue,
        main_kernel: cl.Kernel,

        obstacle_kernel: cl.Kernel,
        obstacle_buffer: cl.Buffer(Coordinate),
        obstacle_pixel_count: usize,

        oscillator_kernel: cl.Kernel,
        oscillator_buffer: cl.Buffer(Oscillator),
        oscillator_count: usize,

        buffer1: cl.Buffer(f32),
        buffer2: cl.Buffer(f32),
        buffer3: cl.Buffer(f32),

        elapsed: f32 = 0,
        iteration: u32 = 0,
        total_kernel_time: i64 = 0,
        total_waiting_time: i64 = 0,

        pub fn init(dt: f32, grid_spacing: f32, propagation_speed: f32, allocator: std.mem.Allocator) !@This() {
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

            const queue = try cl.createCommandQueue(context, device, .{ .profiling = false });

            std.log.info("compiling kernel...", .{});

            const program = try cl.createProgramWithSource(context, kernel_source);
            defer program.release();

            std.debug.print("Building program...\n", .{});

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

            const buffer1 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);
            const buffer2 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);
            const buffer3 = try cl.createBuffer(f32, context, .{ .read_write = true }, width * height);

            const obstacle_buffer = try cl.createBuffer(Coordinate, context, .{ .read_write = true }, height * width);
            const oscillator_buffer = try cl.createBuffer(Oscillator, context, .{ .read_write = true }, 100);

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
            std.debug.print("Returning..\n", .{});
            return @This(){
                .dt = dt,
                .grid_spacing = grid_spacing,
                .propagation_speed = propagation_speed,
                .context = context,
                .queue = queue,
                .main_kernel = main_kernel,
                .buffer1 = buffer1,
                .buffer2 = buffer2,
                .buffer3 = buffer3,
                .obstacle_kernel = obstacle_kernel,
                .obstacle_buffer = obstacle_buffer,
                .obstacle_pixel_count = 0,
                .oscillator_kernel = oscillator_kernel,
                .oscillator_buffer = oscillator_buffer,
                .oscillator_count = 0,
            };
        }

        pub fn on_simstate_update(self: *@This(), simstate: *Simstate) void {
            var obstacle_bfr: *[width * height]Coordinate = simstate.alloc_scratch(Coordinate, width * height);
            var total_pixel_count: u32 = 0;
            for (simstate.obstacles.items) |obstacle| {
                for (obstacle.y..obstacle.y + obstacle.height) |y| {
                    for (obstacle.x..obstacle.x + obstacle.width) |x| {
                        obstacle_bfr[total_pixel_count] = .{ .x = @intCast(x), .y = @intCast(y) };
                        total_pixel_count += 1;
                    }
                }
            }

            std.debug.print("Total pixel count: {}\n", .{total_pixel_count});

            _ = self.queue.enqueueWriteBuffer(Coordinate, self.obstacle_buffer, true, 0, obstacle_bfr, &.{}) catch |err| {
                std.debug.print("Error writing obstacle buffer: {}\n", .{err});
                @panic("Error writing obstacle buffer");
            };

            if (simstate.oscillators.items.len > 0) {
                _ = self.queue.enqueueWriteBuffer(Oscillator, self.oscillator_buffer, true, 0, simstate.oscillators.items, &.{}) catch |err| {
                    std.debug.print("Error writing oscillator buffer: {}\n", .{err});
                    @panic("Error writing oscillator buffer");
                };
            }

            self.oscillator_count = simstate.oscillators.items.len;
            self.obstacle_pixel_count = total_pixel_count;
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
            iter_count: u32,
        ) void {
            const start_kernel = std.time.microTimestamp();
            var maybe_prev_event: ?cl.Event = null;
            for (0..iter_count) |_| {
                self.main_kernel.setArg(@TypeOf(self.buffer1), @rem(0 + self.iteration, 3), self.buffer1) catch @panic("Failed when setting arg.");
                self.main_kernel.setArg(@TypeOf(self.buffer2), @rem(1 + self.iteration, 3), self.buffer2) catch @panic("Failed when setting arg."); // prev_data
                self.main_kernel.setArg(@TypeOf(self.buffer3), @rem(2 + self.iteration, 3), self.buffer3) catch @panic("Failed when setting arg."); // tmp_data

                self.oscillator_kernel.setArg(@TypeOf(self.iteration), 4, self.iteration) catch @panic("Failed when setting arg.");

                if (@rem(self.iteration, 3) == 0) {
                    self.oscillator_kernel.setArg(@TypeOf(self.buffer3), 0, self.buffer3) catch @panic("Failed when setting arg.");
                    self.obstacle_kernel.setArg(@TypeOf(self.buffer3), 0, self.buffer3) catch @panic("Failed when setting arg.");
                } else if (@rem(self.iteration, 3) == 1) {
                    self.oscillator_kernel.setArg(@TypeOf(self.buffer2), 0, self.buffer2) catch @panic("Failed when setting arg.");
                    self.obstacle_kernel.setArg(@TypeOf(self.buffer2), 0, self.buffer2) catch @panic("Failed when setting arg.");
                } else {
                    self.oscillator_kernel.setArg(@TypeOf(self.buffer1), 0, self.buffer1) catch @panic("Failed when setting arg.");
                    self.obstacle_kernel.setArg(@TypeOf(self.buffer1), 0, self.buffer1) catch @panic("Failed when setting arg.");
                }
                const main_kernel_event = self.queue.enqueueNDRangeKernel(
                    self.main_kernel,
                    null,
                    &.{width * height - 2 * width},
                    null,
                    if (maybe_prev_event) |prev_event| &.{prev_event} else &.{},
                ) catch @panic("Failed to enqueue main kernel");
                maybe_prev_event = main_kernel_event;
                //defer main_kernel_event.release();

                var obstacle_kernel_event: ?cl.Event = null;
                var oscillator_kernel_event: ?cl.Event = null;
                if (self.obstacle_pixel_count > 0) {
                    obstacle_kernel_event = self.queue.enqueueNDRangeKernel(
                        self.obstacle_kernel,
                        null,
                        &.{self.obstacle_pixel_count},
                        null,
                        &.{main_kernel_event},
                    ) catch @panic("Failed to enqueue obstacle kernel");
                    //defer obstacle_kernel_event.?.release();
                    maybe_prev_event = obstacle_kernel_event;
                }
                if (self.oscillator_count > 0) {
                    const wait_event = if (obstacle_kernel_event) |obs_event| obs_event else main_kernel_event;
                    oscillator_kernel_event = self.queue.enqueueNDRangeKernel(
                        self.oscillator_kernel,
                        null,
                        &.{self.oscillator_count},
                        null,
                        &.{wait_event},
                    ) catch @panic("Failed to enqueue oscillator kernel");
                    //defer oscillator_kernel_event.?.release();
                    maybe_prev_event = oscillator_kernel_event;
                }
                self.elapsed += self.dt;
                self.iteration += 1;
            }
            cl.waitForEvents(if (maybe_prev_event) |prev_event| &.{prev_event} else &.{}) catch @panic("Failed to wait for events");
            const end_kernel = std.time.microTimestamp();

            // std.debug.print("Kernel time: {}\n", .{end_kernel - start_kernel});
            // std.debug.print("Kernel time per call: {}\n", .{@divTrunc(end_kernel - start_kernel, iter_count)});
            self.total_kernel_time += end_kernel - start_kernel;
            // std.debug.print("Average kernel time: {} ({} per task)\n", .{ @divFloor(self.total_kernel_time, self.iteration + 1), @divFloor(@divFloor(self.total_kernel_time, self.iteration + 1), 1) });
            // std.debug.print("Average waiting time: {}\n", .{@divFloor(self.total_waiting_time, self.iteration + 1)});

        }

        pub fn reset(self: *@This(), buf: *[width * height]f32) void {
            self.elapsed = 0;
            self.iteration = 0;
            for (0..buf.len) |i| {
                buf[i] = 0;
            }
            const b1 = self.queue.enqueueWriteBuffer(
                f32,
                self.buffer1,
                false,
                0,
                buf,
                &.{},
            ) catch @panic("Failed to write buffer");
            const b2 = self.queue.enqueueWriteBuffer(
                f32,
                self.buffer2,
                false,
                0,
                buf,
                &.{},
            ) catch @panic("Failed to write buffer");
            const b3 = self.queue.enqueueWriteBuffer(
                f32,
                self.buffer3,
                false,
                0,
                buf,
                &.{},
            ) catch @panic("Failed to write buffer");
            cl.waitForEvents(&.{ b1, b2, b3 }) catch @panic("Failed to waiting for buffer writes");
        }

        pub fn read_simdata(self: *@This(), dest: *[width * height]f32) []f32 {
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
            const read_complete = self.queue.enqueueReadBuffer(
                f32,
                buffer_to_read,
                false,
                0,
                dest,
                &.{},
            ) catch @panic("Failed to read buffer");
            defer read_complete.release();

            cl.waitForEvents(&.{read_complete}) catch @panic("Failed to wait for read buffer");
            const end_read = std.time.microTimestamp();

            std.debug.print("Read time: {}\n", .{end_read - start_read});
            return dest;
        }
    };
}
