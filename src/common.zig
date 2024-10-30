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

    pub fn sub(self: Coordinate, other: Coordinate) Coordinate {
        return Coordinate{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn add(self: Coordinate, other: Coordinate) Coordinate {
        return Coordinate{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn mul(self: Coordinate, other: anytype) Coordinate {
        switch (@TypeOf(other)) {
            Coordinate => return Coordinate{
                .x = self.x * other.x,
                .y = self.y * other.y,
            },
            f32 => return Coordinate{
                .x = @intFromFloat(@as(f32, @floatFromInt(self.x)) * other),
                .y = @intFromFloat(@as(f32, @floatFromInt(self.y)) * other),
            },
            i32 => return Coordinate{
                .x = self.x * other,
                .y = self.y * other,
            },
            else => @compileError("Type not supported."),
        }
    }
    pub fn div(self: Coordinate, other: anytype) Coordinate {
        switch (@TypeOf(other)) {
            Coordinate => return Coordinate{
                .x = self.x / other.x,
                .y = self.y / other.y,
            },
            f32 => return Coordinate{
                .x = @intFromFloat(@as(f32, @floatFromInt(self.x)) / other),
                .y = @intFromFloat(@as(f32, @floatFromInt(self.y)) / other),
            },
            i32 => return Coordinate{
                .x = self.x / other,
                .y = self.y / other,
            },
            else => @compileError("Type not supported."),
        }
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

pub fn clamp(T: type, value: T, min: T, max: T) T {
    return @min(@max(value, min), max);
}
