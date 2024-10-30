const std = @import("std");
pub const Coordinate = struct {
    x: i32,
    y: i32,

    pub fn clamp(self: Coordinate, min_x: i32, max_x: i32, min_y: i32, max_y: i32) Coordinate {
        return Coordinate{
            .x = @min(@max(self.x, min_x), max_x),
            .y = @min(@max(self.y, min_y), max_y),
        };
    }
};

pub const Obstacle = struct {
    id: u32,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const Oscillator = struct {
    id: u32,
    x: u32,
    y: u32,
    amplitude: f32,
    wavelengths: [5]f32,
    wavelength_count: u32,
    pub fn init(id: u32, x: u32, y: u32, amplitude: f32, wavelengths: []const f32) !Oscillator {
        var wavelength_array: [5]f32 = undefined;
        std.mem.copyForwards(f32, &wavelength_array, wavelengths);
        return Oscillator{
            .id = id,
            .x = x,
            .y = y,
            .amplitude = amplitude,
            .wavelengths = wavelength_array,
            .wavelength_count = @intCast(wavelengths.len),
        };
    }
};
