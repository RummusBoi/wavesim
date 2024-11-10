pub const c = @cImport({
	@cInclude("SDL2/SDL.h");
	@cInclude("SDL2/SDL_ttf.h");
});

pub const WIDTH = 1200;
pub const HEIGHT = 800;
pub const RENDERBUFFER_SIZE = HEIGHT * WIDTH;
pub const std = @import("std");

const Appstate = @import("appstate.zig").Appstate;
const alloc_scratch = @import("simstate.zig").alloc_scratch;
const kernel_source = @embedFile("kernel.cl");
const cl = @import("zig_opencl");

pub const Locale = struct {
	left: f32,
	right: f32,
	up: f32,
	down: f32,
	here: f32,
};

pub fn OpenCLShader() type {
	return struct {
		context: cl.Context,
		queue: cl.CommandQueue,
		kernel: cl.Kernel,

		pub fn init(allocator: std.mem.Allocator) !@This() {
			const platforms = try cl.getPlatforms(allocator);
			if (platforms.len == 0) {
				@panic("no platforms");
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

			const program = try cl.createProgramWithSource(context, kernel_source);
			defer program.release();

			program.build(
				&.{device},
				"-cl-std=CL3.0 -cl-unsafe-math-optimizations -cl-mad-enable",
			) catch |err| {
				if (err == error.BuildProgramFailure) {
					const log = try program.getBuildLog(allocator, device);
					defer allocator.free(log);
					std.log.err("failed to compile:\n{s}", .{log});
				}

				return err;
			};

			const kernel = try cl.createKernel(program, "map_to_color");

			return @This(){
				.context = context,
				.queue = queue,
				.kernel = kernel,
			};
		}

		pub fn shade(self: *@This(), locale: Locale, simdata: []const u8) !f32 {
			_ = simdata; // autofix
			var to_draw: [RENDERBUFFER_SIZE] = .{};
			try self.kernel.setArg(@TypeOf(locale), 0, locale);

			return 1.0;
		}

		pub fn deinit(self: *@This()) void {
			self.context.release();
			self.queue.release();
			self.kernel.release();
		}
	};
}
