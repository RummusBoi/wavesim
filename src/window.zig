pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
pub const std = @import("std");
pub const HEIGHT = 1500;
pub const WIDTH = 3000;
pub const RENDERBUFFER_SIZE = HEIGHT * WIDTH;
pub const Window = struct {
    win: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    allocator: std.mem.Allocator,
    texture: *c.SDL_Texture,
    window_pos: Coordinates,
    zoom_level: f32,

    pub fn init(width: u32, height: u32, allocator: std.mem.Allocator) !Window {
        _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);
        _ = c.TTF_Init();

        const win = c.SDL_CreateWindow("Wavesim", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, @intCast(width), @intCast(height), c.SDL_WINDOW_ALLOW_HIGHDPI) orelse sdl_panic("Creating window");

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
            .window_pos = Coordinates{ .x = WIDTH / 2, .y = HEIGHT / 2 },
            .zoom_level = 1.0,
        };
    }

    pub fn show_simdata(self: *Window, data: []const f32, stride: usize) !void {
        var pixels: *[RENDERBUFFER_SIZE]u32 = undefined;
        // for (pixels_ptrs, 0..) |_, index| {
        //     pixels_ptrs[index] = &pixels[index * WIDTH];
        // }

        var width: c_int = WIDTH;
        if (c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &width) != 0) sdl_panic("Locking texture");
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                const x_f: f32 = @floatFromInt(x);
                const y_f: f32 = @floatFromInt(y);
                const world_x: i32 = @as(i32, @intFromFloat(x_f * self.zoom_level - WIDTH * self.zoom_level / 2)) + self.window_pos.x;
                const world_y: i32 = @as(i32, @intFromFloat(y_f * self.zoom_level - HEIGHT * self.zoom_level / 2)) + self.window_pos.y;

                const simdata_x: isize = @intFromFloat(std.math.floor(@as(f32, @floatFromInt(stride)) / @as(f32, @floatFromInt(WIDTH)) * @as(f32, @floatFromInt(world_x))));
                const simdata_y: isize = @intFromFloat(std.math.floor(@as(f32, @floatFromInt(data.len / stride)) / @as(f32, @floatFromInt(HEIGHT)) * @as(f32, @floatFromInt(world_y))));
                const simval = if (simdata_x > 0 and simdata_x < stride and simdata_y > 0 and simdata_y < data.len / stride) data[@as(usize, @intCast(simdata_y)) * stride + @as(usize, @intCast(simdata_x))] else 0;
                const color: u32 = @intFromFloat(clamp_float(simval));
                pixels[y * WIDTH + x] = (color << 24) | (color << 16) | (color << 8) | color;
            }
        }

        c.SDL_UnlockTexture(self.texture); // sdl_panic("Unlocking texture");
        if (c.SDL_RenderCopy(self.renderer, self.texture, null, null) != 0) sdl_panic("Copying texture");
        c.SDL_RenderPresent(self.renderer);
    }
};

fn sdl_panic(base_msg: []const u8) noreturn {
    std.debug.print("SDL panic detected.\n", .{});
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

fn clamp_float(val: f32) f32 {
    const v = val + 126.0;
    if (v < 0) return 0.0;
    if (v > 255) return 255.0;
    return v;
}

pub const Coordinates = struct {
    x: i32,
    y: i32,
};
