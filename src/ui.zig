const std = @import("std");
const Simstate = @import("simstate.zig").Simstate;
const Appstate = @import("appstate.zig").Appstate;
const Coordinate = @import("common.zig").Coordinate;
const sim_to_camera_coord = @import("window.zig").sim_to_camera_coord;
const camera_to_sim_coord = @import("window.zig").camera_to_sim_coord;
const HoverState = @import("window.zig").HoverState;
const simwidth = @import("simstate.zig").width;
const simheight = @import("simstate.zig").height;
pub fn generate_ui_with_size(width: comptime_int, height: comptime_int) type {
    return struct {
        pub fn update_ui(simstate: *Simstate, appstate: *Appstate, ui: *UI) void {
            var box_index: usize = 0;
            var button_index: usize = 0;

            for (simstate.obstacles.items) |obstacle| {
                const upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(obstacle.x), .y = @intCast(obstacle.y) });
                const lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(obstacle.x + obstacle.width), .y = @intCast(obstacle.y + obstacle.height) });
                const is_selected = if (appstate.selected_entity) |selected_entity| selected_entity == obstacle.id else false;
                const fill_color: Color = if (is_selected) .{ .r = 255, .g = 0, .b = 0, .a = 255 } else .{ .r = 0, .g = 0, .b = 0, .a = 255 };

                ui.buttons[button_index] = ObstacleButton.init(
                    obstacle.id,
                    Box.init(
                        upper_left.x,
                        upper_left.y,
                        lower_right.x - upper_left.x,
                        lower_right.y - upper_left.y,
                        .{
                            .fill_color = fill_color,
                            .border = null,
                        },
                        if (!is_selected) .{
                            .fill_color = .{ .r = 61, .g = 24, .b = 9, .a = 255 },
                            .border = .{
                                .color = .{ .r = 163, .g = 79, .b = 0, .a = 255 },
                                .width = 1,
                            },
                        } else null,
                        null,
                        appstate.mouse_pos,
                        appstate.button_states.is_holding_left_button,
                    ),
                );
                button_index += 1;
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

            if (appstate.paused) {
                ui.buttons[button_index] = PauseButton.init(
                    Box.init(
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
                );
            } else {
                ui.buttons[button_index] = PauseButton.init(
                    Box.init(
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
                );
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

    pub fn find_intersecting_button(self: *UI, x: i32, y: i32) ?*Button {
        for (self.buttons[0..self.button_count]) |*button| {
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

pub const BoxStyling = struct {
    fill_color: ?Color,
    border: ?struct {
        color: Color,
        width: u32,
    },
};

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Button = struct {
    payload: [16]u8 = undefined,
    on_click_inner: *const fn (self: *Button, _: *Simstate, appstate: *Appstate) void,
    on_mouse_drag_inner: *const fn (self: *Button, _: *Simstate, appstate: *Appstate, xrel: i32, yrel: i32) void,
    box: Box,
    pub fn on_click(self: *Button, simstate: *Simstate, appstate: *Appstate) void {
        (self.on_click_inner)(self, simstate, appstate);
    }
    pub fn on_mouse_drag(self: *Button, simstate: *Simstate, appstate: *Appstate, xrel: i32, yrel: i32) void {
        (self.on_mouse_drag_inner)(self, simstate, appstate, xrel, yrel);
    }
};

pub const PauseButton = struct {
    box: Box,
    pub fn init(box: Box) Button {
        return Button{
            .box = box,
            .on_click_inner = on_click,
            .on_mouse_drag_inner = on_mouse_drag,
            .payload = undefined,
        };
    }
    pub fn on_click(_: *Button, _: *Simstate, appstate: *Appstate) void {
        appstate.paused = !appstate.paused;
    }
    pub fn on_mouse_drag(_: *Button, _: *Simstate, _: *Appstate, _: i32, _: i32) void {}
};

pub const ObstacleButton = struct {
    box: Box,
    id: u32,
    draw_start_pos: ?Coordinate,

    pub fn init(id: u32, box: Box) Button {
        var payload: [16]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], id, .big);

        return Button{
            .box = box,
            .on_click_inner = on_click,
            .on_mouse_drag_inner = on_mouse_drag,
            .payload = payload,
        };
    }

    pub fn on_click(btn: *Button, _: *Simstate, appstate: *Appstate) void {
        const id = std.mem.readInt(u32, btn.payload[0..4], .big);
        appstate.drag_obstacle_id = id;

        appstate.selected_entity = id;
    }

    pub fn on_mouse_drag(btn: *Button, simstate: *Simstate, appstate: *Appstate, xrel: i32, yrel: i32) void {
        const id = std.mem.readInt(u32, btn.payload[0..4], .big);

        if (simstate.get_obstacle_by_id(id)) |obstacle| {
            const sim_drag_start = camera_to_sim_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(appstate.mouse_pos.x), .y = @intCast(appstate.mouse_pos.y) });
            const sim_drag_end = camera_to_sim_coord(appstate.zoom_level, appstate.window_pos, .{ .x = @intCast(appstate.mouse_pos.x + xrel), .y = @intCast(appstate.mouse_pos.y + yrel) });
            const sim_drag_delta = sim_drag_end.sub(sim_drag_start);

            obstacle.x = @intCast(@as(i32, @intCast(obstacle.x)) + @as(i32, @intCast(sim_drag_delta.x)));
            obstacle.y = @intCast(@as(i32, @intCast(obstacle.y)) + @as(i32, @intCast(sim_drag_delta.y)));

            appstate.updates.simstate = true;
        }
    }
};
