const c = @import("window.zig").c;
const std = @import("std");
const Simstate = @import("simstate.zig").Simstate;
const Appstate = @import("appstate.zig").Appstate;
const Coordinate = @import("common.zig").Coordinate;
const sim_to_camera_coord = @import("window.zig").sim_to_camera_coord;
const camera_to_sim_coord = @import("window.zig").camera_to_sim_coord;
const HoverState = @import("window.zig").HoverState;
pub fn generate_ui_with_size(width: comptime_int, height: comptime_int) type {
    return struct {
        pub fn update_ui(simstate: *Simstate, appstate: *Appstate, ui: *UI) void {
            var box_index: usize = 0;
            for (simstate.obstacles.items) |obstacle| {
                const upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(obstacle.x), .y = @intCast(obstacle.y) });
                const lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(obstacle.x + obstacle.width), .y = @intCast(obstacle.y + obstacle.height) });
                ui.boxes[box_index] = Box.init(
                    upper_left.x,
                    upper_left.y,
                    lower_right.x - upper_left.x,
                    lower_right.y - upper_left.y,
                    .{
                        .fill_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
                        .border = null,
                    },
                    .{
                        .fill_color = .{ .r = 61, .g = 24, .b = 9, .a = 255 },
                        .border = .{
                            .color = .{ .r = 163, .g = 79, .b = 0, .a = 255 },
                            .width = 1,
                        },
                    },
                    null,
                    appstate.mouse_pos,
                    appstate.button_states.is_holding_left_button,
                );
                box_index += 1;
            }

            const boundary_upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = 0, .y = 0 });
            const boundary_lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(width), .y = @intCast(height) });

            ui.boxes[box_index] = Box.init(
                boundary_upper_left.x,
                boundary_upper_left.y,
                boundary_lower_right.x - boundary_upper_left.x,
                boundary_lower_right.y - boundary_upper_left.y,
                .{
                    .fill_color = null,
                    .border = .{
                        .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
                        .width = 1,
                    },
                },
                null,
                null,
                appstate.mouse_pos,
                appstate.button_states.is_holding_left_button,
            );
            box_index += 1;
            ui.box_count = box_index;

            // Add pause button on the left!
            var button_index: usize = 0;

            if (appstate.paused) {
                ui.buttons[button_index] = Button{
                    .box = Box.init(
                        0,
                        0,
                        100,
                        50,
                        .{
                            .fill_color = .{ .r = 8, .g = 153, .b = 46, .a = 255 },
                            .border = null,
                        },
                        .{
                            .fill_color = .{ .r = 50, .g = 173, .b = 83, .a = 255 },
                            .border = null,
                        },
                        .{
                            .fill_color = .{ .r = 50, .g = 173, .b = 83, .a = 255 },
                            .border = null,
                        },
                        appstate.mouse_pos,
                        appstate.button_states.is_holding_left_button,
                    ),
                    .on_click = on_pause_button_click,
                };
            } else {
                ui.buttons[button_index] = Button{
                    .box = Box.init(
                        0,
                        0,
                        100,
                        50,
                        .{
                            .fill_color = .{ .r = 212, .g = 202, .b = 72, .a = 255 },
                            .border = null,
                        },
                        .{
                            .fill_color = .{ .r = 217, .g = 210, .b = 117, .a = 255 },
                            .border = null,
                        },
                        .{
                            .fill_color = .{ .r = 217, .g = 210, .b = 117, .a = 255 },
                            .border = null,
                        },
                        appstate.mouse_pos,
                        appstate.button_states.is_holding_left_button,
                    ),
                    .on_click = on_pause_button_click,
                };
            }

            button_index += 1;
            ui.button_count = button_index;
        }
    };
}

fn intersects(point: Coordinate, x: i32, y: i32, w: i32, h: i32) bool {
    return point.x < x + w and point.x > x and point.y < y + h and point.y > y;
}

pub const UI = struct {
    boxes: [128]Box = undefined,
    box_count: usize = 0,
    buttons: [128]Button = undefined,
    button_count: usize = 0,
    texts: [128]Text = undefined,
    text_count: usize = 0,

    pub fn find_intersecting_button(self: *const UI, x: i32, y: i32) ?Button {
        for (self.buttons[0..self.button_count]) |button| {
            if (x >= button.box.x and x <= button.box.x + button.box.width and y >= button.box.y and y <= button.box.y + button.box.height) {
                return button;
            }
        }
        return null;
    }

    pub fn find_intersecting_box(self: *const UI, x: i32, y: i32) ?Box {
        for (self.boxes[0..self.box_count]) |box| {
            if (x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height) {
                return box;
            }
        }
        return null;
    }
};

pub const Box = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    styling: BoxStyling,

    pub fn init(x: i32, y: i32, width: i32, height: i32, non_hover: BoxStyling, hover: ?BoxStyling, pressed: ?BoxStyling, mouse_pos: Coordinate, is_holding_left_button: bool) Box {
        const styling = switch (HoverState.from_bool(intersects(mouse_pos, x, y, width, height), is_holding_left_button)) {
            .None => non_hover,
            .Hover => hover orelse non_hover,
            .Pressed => pressed orelse hover orelse non_hover,
        };
        return Box{ .x = x, .y = y, .width = width, .height = height, .styling = styling };
    }
};

pub const Text = struct {
    x: i32,
    y: i32,
    contents: []const u8,
    font_size: u8,
    styling: TextStyling,
};

pub const TextStyling = struct {
    fill_color: ?struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
    border: ?struct {
        color: struct {
            r: u8,
            g: u8,
            b: u8,
            a: u8,
        },
        width: u32,
    },
};

pub const BoxStyling = struct {
    fill_color: ?struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
    border: ?struct {
        color: struct {
            r: u8,
            g: u8,
            b: u8,
            a: u8,
        },
        width: u32,
    },
};

pub const Button = struct {
    box: Box,
    on_click: *const fn (simstate: *Simstate, appstate: *Appstate) void,
};

fn on_pause_button_click(_: *Simstate, appstate: *Appstate) void {
    appstate.paused = !appstate.paused;
}

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

//        var w: c_int = undefined;
//        var h: c_int = undefined;
//
//        self.scratch_buffer.clearRetainingCapacity();
//        try self.scratch_buffer.appendSlice(value);
//        try self.scratch_buffer.append(0);
//        if (c.TTF_SizeText(self.font, @ptrCast(self.scratch_buffer.items), &w, &h) != 0) {
//            sdl_panic("Getting text size");
//        }
//        if (value.len > 0) {
//            const texture_res = self.find_cached_texture_for_value(value, "cell");
//            const texture = texture_res orelse blk: {
//                const font_color: c.SDL_Color = .{ .r = 0, .g = 0, .b = 0 };
//
//                const surface = c.TTF_RenderText_Shaded(self.font, @ptrCast(self.scratch_buffer.items), font_color, .{ .a = 255, .r = 255, .g = 255, .b = 255 });
//                defer c.SDL_FreeSurface(surface);
//                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse {
//                    sdl_panic("Creating text texture.");
//                };
//                self.cache_texture(texture, value, "cell") catch {
//                    std.debug.print("Could not cache texture.", .{});
//                };
//                break :blk texture;
//            };
//            const dest_rect: c.SDL_Rect = .{ .x = outer.x + 3, .y = outer.y + 3, .w = w, .h = h };
//            if (c.SDL_RenderCopy(self.renderer, texture, null, &dest_rect) != 0) {
//                sdl_panic("Could not render");
//            }
//        }
