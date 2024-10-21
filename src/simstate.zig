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
        obstacle_scratch: *[simwidth * simheight]Coordinate,
        simdata_scratch: *[simwidth * simheight]f32,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const buf: *[width * height * 8]u8 = @ptrCast(try allocator.alloc(u8, simwidth * simheight * 8));
            const obstacle_scratch: *[simwidth * simheight]Coordinate = @alignCast(@ptrCast(buf));
            const simdata_scratch: *[simwidth * simheight]f32 = @alignCast(@ptrCast(buf));
            return @This(){
                .obstacles = std.ArrayList(Obstacle).init(allocator),
                .oscillators = std.ArrayList(Oscillator).init(allocator),
                .scratch_buffer = buf,
                .obstacle_scratch = obstacle_scratch,
                .simdata_scratch = simdata_scratch,
            };
        }
    };
}
