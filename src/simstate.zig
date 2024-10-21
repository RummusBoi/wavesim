const std = @import("std");
pub const width = 4000;
pub const height = 2048;

pub const Simstate = SimStateWithSize(width, height);
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
pub const Obstacle = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

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
};
