const font_file_content = @embedFile("font/NaturalMono-Regular.ttf");

pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
pub const std = @import("std");
pub const WIDTH = 1200;
pub const HEIGHT = 800;
pub const RENDERBUFFER_SIZE = HEIGHT * WIDTH;

const Coordinate = @import("common.zig").Coordinate;
const Text = @import("ui.zig").Text;
const UI = @import("ui.zig").UI;
const Appstate = @import("appstate.zig").Appstate;
const Box = @import("ui.zig").Box;
const ArrayList = std.ArrayList;

pub const Window = struct {
    win: *c.SDL_Window,
    font: *c.TTF_Font,
    renderer: *c.SDL_Renderer,
    allocator: std.mem.Allocator,
    texture: *c.SDL_Texture,
    cached_textures_for_text: ArrayList(CachedTexture),

    pub fn init(width: u32, height: u32, allocator: std.mem.Allocator) !Window {
        _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);
        _ = c.TTF_Init();

        const win = c.SDL_CreateWindow("Wavesim", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, @intCast(width), @intCast(height), 0) orelse sdl_panic("Creating window");

        c.SDL_SetWindowResizable(win, 1);
        const renderer = c.SDL_CreateRenderer(win, 0, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse sdl_panic("Creating renderer");

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

        const rw_ops = c.SDL_RWFromConstMem(font_file_content, font_file_content.len) orelse sdl_panic("Interpreting font");
        const font: *c.TTF_Font = c.TTF_OpenFontRW(rw_ops, 1, 13) orelse sdl_panic("Loading font");

        return Window{
            .win = win,
            .renderer = renderer,
            .allocator = allocator,
            .texture = texture,
            .font = font,
            .cached_textures_for_text = ArrayList(CachedTexture).init(allocator),
            // .window_pos = Coordinate{ .x = @intFromFloat(WIDTH / 2 * zoom_level), .y = @intFromFloat(HEIGHT / 2 * zoom_level) },
            // .zoom_level = zoom_level,
        };
    }

    pub fn draw_simdata(self: *Window, data: []const f32, stride: usize, zoom_level: f32, window_pos: Coordinate) void {
        var pixels: *[RENDERBUFFER_SIZE]u32 = undefined;
        var width: c_int = WIDTH;
        if (c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &width) != 0) sdl_panic("Locking texture");
        for (0..@intCast(HEIGHT)) |y| {
            for (0..@intCast(WIDTH)) |x| {
                const simdata_coords = camera_to_sim_coord(
                    zoom_level,
                    window_pos,
                    .{ .x = @intCast(x), .y = @intCast(y) },
                );
                const simval = if (simdata_coords.x > 0 and simdata_coords.x < stride and simdata_coords.y > 0 and simdata_coords.y < data.len / stride) data[@as(usize, @intCast(simdata_coords.y)) * stride + @as(usize, @intCast(simdata_coords.x))] else 0;
                const clamped = clamp_float(simval);

                const color: u32 = @intFromFloat(clamped);
                const index = y * @as(usize, @intCast(WIDTH)) + x;
                pixels[index] = (color << 24) | (color << 16) | (color << 8) | color;
            }
        }

        c.SDL_UnlockTexture(self.texture);
    }
    fn draw_ui_box(self: *Window, box: Box) void {
        const styling = box.styling;
        if (styling.fill_color) |fill_color| {
            self.draw_filled_box(
                .{ .x = box.x, .y = box.y },
                .{ .x = box.x + box.width, .y = box.y + box.height },
                fill_color.r,
                fill_color.g,
                fill_color.b,
                fill_color.a,
            );
        }
        if (styling.border) |border| {
            self.draw_box(
                .{ .x = box.x, .y = box.y },
                .{ .x = box.x + box.width, .y = box.y + box.height },
                border.color.r,
                border.color.g,
                border.color.b,
                border.color.a,
            );
        }
    }
    pub fn draw_ui(self: *Window, ui: *UI) void {
        for (ui.boxes[0..ui.box_count]) |box| {
            self.draw_ui_box(box);
        }
        for (ui.buttons[0..ui.button_count]) |button| {
            self.draw_ui_box(button.box);
        }
    }
    pub fn draw_filled_box(self: *Window, upper_left: Coordinate, lower_right: Coordinate, r: u32, g: u32, b: u32, a: u32) void {
        var pixels: *[RENDERBUFFER_SIZE]u32 = undefined;
        var width: c_int = WIDTH;
        const u_left_clamped = upper_left.clamp(0, WIDTH, 0, HEIGHT);
        const l_right_clamped = lower_right.clamp(0, WIDTH, 0, HEIGHT);

        if (c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &width) != 0) sdl_panic("Locking texture");

        for (@intCast(u_left_clamped.x)..@intCast(l_right_clamped.x)) |x| {
            for (@intCast(u_left_clamped.y)..@intCast(l_right_clamped.y)) |y| {
                const index: i32 = @intCast(y * WIDTH + x);
                const u_index: usize = @intCast(index);
                pixels[u_index] = (a << 24) | (r << 16) | (g << 8) | b;
            }
        }

        c.SDL_UnlockTexture(self.texture);
    }
    pub fn draw_box(self: *Window, upper_left: Coordinate, lower_right: Coordinate, r: u32, g: u32, b: u32, a: u32) void {
        var pixels: *[RENDERBUFFER_SIZE]u32 = undefined;
        var width: c_int = WIDTH;

        if (c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &width) != 0) sdl_panic("Locking texture");
        var x: i32 = upper_left.x;
        var y: i32 = upper_left.y;
        while (x <= lower_right.x) : (x += 1) {
            y = @intCast(upper_left.y);
            if (x < 0 or x >= WIDTH) continue;
            if (y < 0 or y >= HEIGHT) continue;

            const index: i32 = @intCast(y * WIDTH + x);
            const u_index: usize = @intCast(index);

            pixels[u_index] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        x = upper_left.x;
        while (x <= lower_right.x) : (x += 1) {
            y = @intCast(lower_right.y);
            if (x < 0 or x >= WIDTH) continue;
            if (y < 0 or y >= HEIGHT) continue;

            const index: i32 = @intCast(y * WIDTH + x);
            const u_index: usize = @intCast(index);
            pixels[u_index] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        y = upper_left.y;
        while (y <= lower_right.y) : (y += 1) {
            x = @intCast(upper_left.x);
            if (x < 0 or x >= WIDTH) continue;
            if (y < 0 or y >= HEIGHT) continue;

            const index: i32 = @intCast(y * WIDTH + x);
            const u_index: usize = @intCast(index);
            pixels[u_index] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        y = upper_left.y;
        while (y <= lower_right.y) : (y += 1) {
            x = @intCast(lower_right.x);
            if (x < 0 or x >= WIDTH) continue;
            if (y < 0 or y >= HEIGHT) continue;

            const index: i32 = @intCast(y * WIDTH + x);
            const u_index: usize = @intCast(index);
            pixels[u_index] = (a << 24) | (r << 16) | (g << 8) | b;
        }

        c.SDL_UnlockTexture(self.texture);
    }
    pub fn present(self: *Window, ui: *UI) void {
        if (c.SDL_RenderCopy(self.renderer, self.texture, null, null) != 0) sdl_panic("Copying texture to renderer");
        for (ui.texts[0..ui.text_count]) |text| {
            var size: c.SDL_Point = undefined;
            const texture = self.get_text_texture(&text);
            if (c.SDL_QueryTexture(texture, null, null, &size.x, &size.y) != 0) sdl_panic("Querying texture for size");
            const dest_rect: c.SDL_Rect = .{ .x = text.x + 3, .y = text.y + 3, .w = size.x, .h = size.y };
            if (c.SDL_RenderCopy(self.renderer, self.get_text_texture(&text), null, &dest_rect) != 0) sdl_panic("Copying texture to renderer");
        }
        c.SDL_RenderPresent(self.renderer);
    }

    // Will also handle the case where the text is cached.
    pub fn get_text_texture(self: *Window, text: *const Text) *c.SDL_Texture {
        for (self.cached_textures_for_text.items) |t| {
            if (t.text.contents == text.contents) return t.texture;
        }

        std.debug.print("Calculating texture...\n", .{});

        var w: c_int = undefined;
        var h: c_int = undefined;

        if (c.TTF_SizeText(self.font, text.contents, &w, &h) != 0) {
            sdl_panic("Getting text size");
        }

        const surface = c.TTF_RenderText_Shaded(
            self.font,
            @ptrCast(text.contents),
            text.font_color,
            .{ .a = 1, .r = 0, .g = 0, .b = 0 }
        );
        defer c.SDL_FreeSurface(surface);

        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse {
            sdl_panic("Creating text texture");
        };

        self.cached_textures_for_text.append(.{ .texture = texture, .text = text.* }) catch sdl_panic("Caching texture");

        return texture;
    }
};


fn sdl_panic(base_msg: []const u8) noreturn {
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

pub fn camera_to_sim_coord(zoom_level: f32, window_pos: Coordinate, coords: Coordinate) Coordinate {
    const x_f: f32 = @floatFromInt(coords.x);
    const y_f: f32 = @floatFromInt(coords.y);

    const world_x: i32 = @as(i32, @intFromFloat(x_f * zoom_level - WIDTH * zoom_level / 2)) + window_pos.x;
    const world_y: i32 = @as(i32, @intFromFloat(y_f * zoom_level - HEIGHT * zoom_level / 2)) + window_pos.y;

    return Coordinate{ .x = world_x, .y = world_y };
}

pub fn sim_to_camera_coord(zoom_level: f32, window_pos: Coordinate, coords: Coordinate) Coordinate {
    const x_f: f32 = @floatFromInt(coords.x);
    const y_f: f32 = @floatFromInt(coords.y);

    const camera_x = (x_f - @as(f32, @floatFromInt(window_pos.x)) + WIDTH * zoom_level / 2) / zoom_level;
    const camera_y = (y_f - @as(f32, @floatFromInt(window_pos.y)) + HEIGHT * zoom_level / 2) / zoom_level;

    return Coordinate{ .x = @intFromFloat(camera_x), .y = @intFromFloat(camera_y) };
}

pub const HoverState = enum {
    None,
    Hover,
    Pressed,

    pub fn from_bool(hovering: bool, pressed: bool) HoverState {
        if (pressed and hovering) return HoverState.Pressed;
        if (hovering) return HoverState.Hover;
        return HoverState.None;
    }
};

const CachedTexture = struct {
    texture: *c.SDL_Texture,
    text: Text,
};
