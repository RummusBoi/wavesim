const std = @import("std");
pub const width = 4000;
pub const height = 2048;

pub const Simstate = SimStateWithSize(width, height);
const Obstacle = @import("common.zig").Obstacle;
const Oscillator = @import("common.zig").Oscillator;
const Coordinate = @import("common.zig").Coordinate;

pub fn SimStateWithSize(simwidth: u32, simheight: u32) type {
    return struct {
        obstacles: std.ArrayList(Obstacle),
        oscillators: std.ArrayList(Oscillator),
        scratch_buffer: *[simwidth * simheight * 8]u8,
        id: u32 = 0,

        pub fn create_obstacle(self: *@This(), x: u32, y: u32, w: u32, h: u32) !Obstacle {
            const id = self.id;
            self.id += 1;
            const obstacle = Obstacle{ .id = id, .x = x, .y = y, .width = w, .height = h };
            try self.obstacles.append(obstacle);
            return obstacle;
        }

        pub fn create_oscillator(self: *@This(), x: u32, y: u32, amplitude: f32, wavelengths: []const f32) !Oscillator {
            const id = self.id;
            self.id += 1;
            const oscillator = try Oscillator.init(id, x, y, amplitude, wavelengths);
            try self.oscillators.append(oscillator);
            return oscillator;
        }

        pub fn alloc_scratch(self: *@This(), t: type, len: comptime_int) *[len]t {
            const buf_size = self.scratch_buffer.len * @sizeOf(u8);
            const size = @sizeOf(t);
            if (size * len > buf_size) {
                @compileError("Buffer too small");
            }
            const result: *[len]t = @alignCast(@ptrCast(self.scratch_buffer));
            return result;
        }

        pub fn get_obstacle_by_id(self: *@This(), id: u32) ?*Obstacle {
            for (self.obstacles.items) |*obstacle| {
                if (obstacle.id == id) {
                    return obstacle;
                }
            }
            return null;
        }

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const buf: *[width * height * 8]u8 = @ptrCast(try allocator.alloc(u8, simwidth * simheight * 8));
            return @This(){
                .obstacles = std.ArrayList(Obstacle).init(allocator),
                .oscillators = std.ArrayList(Oscillator).init(allocator),
                .scratch_buffer = buf,
            };
        }
    };
}
