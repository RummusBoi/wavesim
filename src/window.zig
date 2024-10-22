pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

pub const std = @import("std");
pub const WIDTH = 1200;
pub const HEIGHT = 800;
pub const RENDERBUFFER_SIZE = HEIGHT * WIDTH;

const sqrt = std.math.sqrt;
const pow = std.math.pow;

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Locale = struct {
    left: f32,
    right: f32,
    up: f32,
    down: f32,
};

pub const Window = struct {
    win: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    allocator: std.mem.Allocator,
    texture: *c.SDL_Texture,
    window_pos: Coordinates,
    zoom_level: f32,

    pub fn init(width: u32, height: u32, zoom_level: f32, allocator: std.mem.Allocator) !Window {
        _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);
        _ = c.TTF_Init();

        const win = c.SDL_CreateWindow("Wavesim", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, @intCast(width), @intCast(height), 0) orelse sdl_panic("Creating window");

        c.SDL_SetWindowResizable(win, 1);
        const renderer = c.SDL_CreateRenderer(win, 0, c.SDL_RENDERER_ACCELERATED) orelse sdl_panic("Creating renderer");

        if (c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND) != 0) {
            sdl_panic("Setting blend mode.");
        }

        const texture: *c.SDL_Texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGB888,
            c.SDL_TEXTUREACCESS_STREAMING,
            WIDTH,
            HEIGHT,
        ) orelse sdl_panic("Creating texture");

        return Window{
            .win = win,
            .renderer = renderer,
            .allocator = allocator,
            .texture = texture,
            .window_pos = Coordinates{ .x = @intFromFloat(WIDTH / 2 * zoom_level), .y = @intFromFloat(HEIGHT / 2 * zoom_level) },
            .zoom_level = zoom_level,
        };
    }

    fn camera_to_sim_coord(self: *Window, coords: Coordinates) Coordinates {
        const x_f: f32 = @floatFromInt(coords.x);
        const y_f: f32 = @floatFromInt(coords.y);

        const world_x: i32 = @as(i32, @intFromFloat(x_f * self.zoom_level - WIDTH * self.zoom_level / 2)) + self.window_pos.x;
        const world_y: i32 = @as(i32, @intFromFloat(y_f * self.zoom_level - HEIGHT * self.zoom_level / 2)) + self.window_pos.y;

        return Coordinates{ .x = world_x, .y = world_y };
    }

    fn sim_to_camera_coord(self: *Window, coords: Coordinates) Coordinates {
        const x_f: f32 = @floatFromInt(coords.x);
        const y_f: f32 = @floatFromInt(coords.y);

        const camera_x = (x_f - @as(f32, @floatFromInt(self.window_pos.x)) + WIDTH * self.zoom_level / 2) / self.zoom_level;
        const camera_y = (y_f - @as(f32, @floatFromInt(self.window_pos.y)) + HEIGHT * self.zoom_level / 2) / self.zoom_level;

        return Coordinates{ .x = @intFromFloat(camera_x), .y = @intFromFloat(camera_y) };
    }

    pub fn draw_simdata(self: *Window, data: []const f32, stride: usize) !void {
        var pixels: *[RENDERBUFFER_SIZE]u32 = undefined;
        var width: c_int = WIDTH;
        if (c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &width) != 0) sdl_panic("Locking texture");
        // var mode: c.SDL_DisplayMode = undefined;
        // _ = c.SDL_GetWindowDisplayMode(self.win, &mode);
        for (0..@intCast(HEIGHT)) |y| {
            for (0..@intCast(WIDTH)) |x| {
                const simdata_coords = self.camera_to_sim_coord(
                    .{ .x = @intCast(x), .y = @intCast(y) },
                );

                const simval = get_simval(simdata_coords, data, stride);
                const up = get_simval(simdata_coords, data, stride);
                const down = get_simval(simdata_coords, data, stride);
                const left = get_simval(simdata_coords, data, stride);
                const right = get_simval(simdata_coords, data, stride);

                const locale = Locale{
                    .up = up,
                    .down = down,
                    .left = left,
                    .right = right,
                };

                const color: u32 = @intFromFloat(map_to_color(simval, locale));
                const index = y * @as(usize, @intCast(WIDTH)) + x;

                const r = @min((color + 80) << 16, 255 << 16);
                const g = @min((color + 150) << 8, 255 << 8);
                const b = 255;

                pixels[index] = 0 | r | g | b;
            }
        }

        c.SDL_UnlockTexture(self.texture); // sdl_panic("Unlocking texture");

    }
    pub fn draw_box(self: *Window, upper_left: Coordinates, lower_right: Coordinates, r: u32, g: u32, b: u32, a: u32) void {
        var pixels: *[RENDERBUFFER_SIZE]u32 = undefined;
        var width: c_int = WIDTH;

        if (c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &width) != 0) sdl_panic("Locking texture");
        // var mode: c.SDL_DisplayMode = undefined;
        // _ = c.SDL_GetWindowDisplayMode(self.win, &mode);
        for (@intCast(upper_left.x)..@intCast(lower_right.x)) |x| {
            for (@intCast(upper_left.y)..@intCast(lower_right.y)) |y| {
                const cam_coords: Coordinates = self.sim_to_camera_coord(.{ .x = @intCast(x), .y = @intCast(y) });
                if (cam_coords.x < 0 or cam_coords.x >= WIDTH or cam_coords.y < 0 or cam_coords.y >= HEIGHT) continue;
                const index: i32 = cam_coords.y * WIDTH + cam_coords.x;
                const u_index: usize = @intCast(index);
                pixels[u_index] = (a << 24) | (r << 16) | (g << 8) | b;
            }
        }

        c.SDL_UnlockTexture(self.texture); // sdl_panic("Unlocking texture");
    }
    pub fn draw_boundary(self: *Window, width: i32, height: i32) void {
        if (c.SDL_RenderCopy(self.renderer, self.texture, null, null) != 0) sdl_panic("Copying texture");
        if (c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255) != 0) {
            sdl_panic("Setting draw color");
        }
        const upper_left = self.sim_to_camera_coord(.{ .x = 0, .y = 0 });
        const upper_right = self.sim_to_camera_coord(.{ .x = width, .y = 0 });
        const lower_left = self.sim_to_camera_coord(.{ .x = 0, .y = height });
        const lower_right = self.sim_to_camera_coord(.{ .x = width, .y = height });
        _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 0, 0, 255);
        _ = c.SDL_RenderDrawLine(self.renderer, upper_left.x, upper_left.y, upper_right.x, upper_right.y);
        _ = c.SDL_RenderDrawLine(self.renderer, upper_left.x, upper_left.y, lower_left.x, lower_left.y);
        _ = c.SDL_RenderDrawLine(self.renderer, lower_left.x, lower_left.y, lower_right.x, lower_right.y);
        _ = c.SDL_RenderDrawLine(self.renderer, upper_right.x, upper_right.y, lower_right.x, lower_right.y);
    }
    pub fn present(self: *Window) void {
        c.SDL_RenderPresent(self.renderer);
    }
};

fn sdl_panic(base_msg: []const u8) noreturn {
    // std.debug.print("SDL panic detected.\n", .{});
    const message = c.SDL_GetError() orelse @panic("Unknown error in SDL.");

    var ptr: u32 = 0;
    char_loop: while (true) {
        const char = message[ptr];
        if (char == 0) {
            break :char_loop;
        }
        ptr += 1;
    }
    var zig_slice: []const u8 = undefined;
    zig_slice.len = ptr;
    zig_slice.ptr = message;

    var full_msg: [256]u8 = undefined;
    join_strs(base_msg, zig_slice, &full_msg);

    @panic(&full_msg);
}
fn join_strs(s1: []const u8, s2: []const u8, buf: []u8) void {
    for (s1, 0..) |char, index| {
        buf[index] = char;
    }
    for (s2, 0..) |char, index| {
        buf[s1.len + index] = char;
    }
}

fn get_simval(simdata_coords: Coordinates, data: []const f32, stride: usize) f32 {
    return if (simdata_coords.x > 0 and simdata_coords.x < stride and simdata_coords.y > 0 and simdata_coords.y < data.len / stride)
        data[@as(usize, @intCast(simdata_coords.y)) * stride + @as(usize, @intCast(simdata_coords.x))]
    else
        0;
}

fn cross_product(v1: Vector, v2: Vector) Vector {
    return Vector{
        .x = v1.y * v2.z - v1.z * v2.y,
        .y = v1.z * v2.x - v1.x * v2.z,
        .z = v1.x * v2.y - v1.y * v2.x,
    };
}

fn norm(v: Vector) f32 {
    return sqrt(pow(f32, v.x, 2) + pow(f32, v.y, 2) + pow(f32, v.z, 2));
}

// In degrees.
fn angle(v1: Vector, v2: Vector) f32 {
    const divisor = (norm(v1) * norm(v2));
    const res = norm(cross_product(v1, v2)) / divisor;
    return std.math.asin(res) * (180.0 / std.math.pi);
}

// Returns the angle of the normal vector to the z axis, with a few conditions:
// - Returns 0 or 255 if angle < 0 or angle > 255.
// - Returns sqrt(angle) if angle > 100.
// - Else, returns angle.
fn map_to_color(val: f32, locale: Locale) f32 {
    const q = Vector{
        .x = 0,
        .y = 0,
        .z = val,
    };

    const r = Vector{
        .x = 0,
        .y = 1,
        .z = locale.up - locale.down,
    };

    const s = Vector{
        .x = 1,
        .y = 0,
        .z = locale.right - locale.left,
    };

    const qr = Vector{
        .x = r.x - q.x,
        .y = r.y - q.y,
        .z = r.z - q.z,
    };

    const qs = Vector{
        .x = s.x - q.x,
        .y = s.y - q.y,
        .z = s.z - q.z,
    };

    const normal_vector = cross_product(qr, qs);
    const z_axis = Vector{
        .x = 0,
        .y = 0,
        .z = 1,
    };

    const angle_to_z_axis = angle(normal_vector, z_axis);

    // If angle is 0, then it will be blue. Otherwise it will be gradually lighter.
    if (angle_to_z_axis < 0) {
        return 0.0;
    }
    if (angle_to_z_axis > 255) {
        return 255.0;
    }
    if (angle_to_z_axis > 100) {
        return pow(f32, angle_to_z_axis, 0.5);
    }
    return angle_to_z_axis;
}

pub const Vector = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Coordinates = struct {
    x: i32,
    y: i32,
};
