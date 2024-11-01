const std = @import("std");
const Simstate = @import("simstate.zig").Simstate;
const Appstate = @import("appstate.zig").Appstate;
const Coordinate = @import("common.zig").Coordinate;
const sim_to_camera_coord = @import("window.zig").sim_to_camera_coord;
const camera_to_sim_coord = @import("window.zig").camera_to_sim_coord;
const HoverState = @import("window.zig").HoverState;
const simwidth = @import("simstate.zig").width;
const simheight = @import("simstate.zig").height;
const Box = @import("ui_common.zig").Box;
const Button = @import("ui_common.zig").Button;
const ObstacleButton = @import("ui_common.zig").ObstacleButton;
const Color = @import("ui_common.zig").Color;
const add_menu = @import("menu.zig").add_menu;
pub fn generate_ui_with_size(width: comptime_int, height: comptime_int) type {
    return struct {
        pub fn update_ui(simstate: *Simstate, appstate: *Appstate, ui: *UI, window_size: struct { width: i32, height: i32 }) void {
            var box_index: usize = 0;
            var button_index: usize = 0;

            for (simstate.obstacles.items) |obstacle| {
                const upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .width = window_size.width, .height = window_size.height }, .{ .x = @intCast(obstacle.x), .y = @intCast(obstacle.y) });
                const lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .width = window_size.width, .height = window_size.height }, .{ .x = obstacle.x + @as(i32, @intCast(obstacle.width)), .y = obstacle.y + @as(i32, @intCast(obstacle.height)) });
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

            const boundary_upper_left = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .width = window_size.width, .height = window_size.height }, .{ .x = 0, .y = 0 });
            const boundary_lower_right = sim_to_camera_coord(appstate.zoom_level, appstate.window_pos, .{ .width = window_size.width, .height = window_size.height }, .{ .x = @intCast(width), .y = @intCast(height) });

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

            // Add pause button on the left!
            add_menu(simstate, appstate, ui, window_size.height, &box_index, &button_index);
            ui.button_count = button_index;
            ui.box_count = box_index;
        }
    };
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
