const std = @import("std");
pub const Coordinate = struct {
    x: i32,
    y: i32,
};

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
