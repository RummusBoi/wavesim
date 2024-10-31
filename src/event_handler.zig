const Simstate = @import("simstate.zig").Simstate;
const c = @import("window.zig").c;
const Appstate = @import("appstate.zig").Appstate;
const sqrt = @import("std").math.sqrt;
const pow = @import("std").math.pow;
const OpenCLSolverWithSize = @import("opencl_solver.zig").OpenCLSolverWithSize;
const UI = @import("ui.zig").UI;
const std = @import("std");
pub fn handle_events_with_size(width: comptime_int, height: comptime_int) type {
    return struct {
        pub fn handle_events(ui: *UI, appstate: *Appstate, simstate: *Simstate, solver: *OpenCLSolverWithSize(width, height)) void {
            var event: c.SDL_Event = undefined;
            appstate.updates = .{ .simstate = false };
            const simdata_scratch = simstate.alloc_scratch(f32, width * height);
            const scroll_sensitivity = 2;
            if (appstate.button_states.is_holding_up) {
                appstate.window_pos.y -= @intFromFloat(10 * appstate.zoom_level * appstate.ui_movement_scalor);
            }
            if (appstate.button_states.is_holding_down) {
                appstate.window_pos.y += @intFromFloat(10 * appstate.zoom_level * appstate.ui_movement_scalor);
            }
            if (appstate.button_states.is_holding_left) {
                appstate.window_pos.x -= @intFromFloat(10 * appstate.zoom_level * appstate.ui_movement_scalor);
            }
            if (appstate.button_states.is_holding_right) {
                appstate.window_pos.x += @intFromFloat(10 * appstate.zoom_level * appstate.ui_movement_scalor);
            }
            if (appstate.button_states.held_zoom_button_counter > 0) {
                appstate.zoom_level *= 1 - (0.02 * appstate.ui_movement_scalor);
            }
            if (appstate.button_states.is_holding_zoom_out) {
                appstate.zoom_level *= 1 + (0.02 * appstate.ui_movement_scalor);
            }
            while (c.SDL_PollEvent(&event) != 0) {
                switch (event.type) {
                    c.SDL_QUIT => {
                        appstate.keep_going = false;
                        break;
                    },
                    c.SDL_MOUSEBUTTONDOWN => {
                        if (event.button.button == c.SDL_BUTTON_LEFT) {
                            if (ui.find_intersecting_button(appstate.mouse_pos.x, appstate.mouse_pos.y)) |button| {
                                button.on_click(simstate, appstate);
                                appstate.is_dragging_sim = false;
                            } else {
                                appstate.selected_entity = null;
                                appstate.is_dragging_sim = true;
                            }
                            appstate.button_states.is_holding_left_button = true;
                        }
                    },
                    c.SDL_MOUSEBUTTONUP => {
                        if (event.button.button == c.SDL_BUTTON_LEFT) {
                            appstate.button_states.is_holding_left_button = false;
                            appstate.is_dragging_sim = false;
                            appstate.drag_obstacle_id = null;
                        }
                    },
                    c.SDL_MOUSEMOTION => {
                        const xrel = event.motion.x - appstate.mouse_pos.x;
                        const yrel = event.motion.y - appstate.mouse_pos.y;

                        if (appstate.button_states.is_holding_left_button) {
                            if (appstate.is_dragging_sim) {
                                appstate.window_pos.x -= @intFromFloat(@as(f32, @floatFromInt(xrel)) * appstate.zoom_level);
                                appstate.window_pos.y -= @intFromFloat(@as(f32, @floatFromInt(yrel)) * appstate.zoom_level);
                            } else if (ui.find_intersecting_button(appstate.mouse_pos.x, appstate.mouse_pos.y)) |button| {
                                button.on_mouse_drag(simstate, appstate, xrel, yrel);
                            }
                        }
                        appstate.mouse_pos.x = event.motion.x;
                        appstate.mouse_pos.y = event.motion.y;
                    },
                    c.SDL_MOUSEWHEEL => {
                        const x = event.wheel.preciseX;
                        const y = event.wheel.preciseY;

                        const norm = @min(sqrt(pow(f32, x, 2) + pow(f32, y, 2)), 200);

                        if (norm == 0) {
                            break;
                        }

                        const norm_scaled = pow(f32, @as(f32, norm), 1.5);
                        const norms_ratio = norm_scaled / norm;

                        appstate.window_pos.x += @intFromFloat(x * norms_ratio * scroll_sensitivity * appstate.zoom_level);
                        appstate.window_pos.y -= @intFromFloat(y * norms_ratio * scroll_sensitivity * appstate.zoom_level);
                    },
                    c.SDL_KEYDOWN => {
                        const scancode = event.key.keysym.scancode;
                        if (scancode == c.SDL_SCANCODE_ESCAPE) {
                            appstate.keep_going = false;
                            break;
                        }
                        if (scancode == c.SDL_SCANCODE_LEFT) {
                            appstate.button_states.is_holding_left = true;
                        }
                        if (scancode == c.SDL_SCANCODE_RIGHT) {
                            appstate.button_states.is_holding_right = true;
                        }
                        if (scancode == c.SDL_SCANCODE_UP) {
                            appstate.button_states.is_holding_up = true;
                        }
                        if (scancode == c.SDL_SCANCODE_DOWN) {
                            appstate.button_states.is_holding_down = true;
                        }
                        if (event.key.keysym.sym == c.SDLK_PLUS) {
                            appstate.button_states.held_zoom_button_counter =
                                appstate.button_states.held_zoom_button_counter | 1;
                        }
                        if (event.key.keysym.sym == c.SDLK_EQUALS) {
                            appstate.button_states.held_zoom_button_counter =
                                appstate.button_states.held_zoom_button_counter | 2;
                        }
                        if (event.key.keysym.sym == c.SDLK_MINUS) {
                            appstate.button_states.is_holding_zoom_out = true;
                        }
                        if (event.key.keysym.sym == c.SDLK_r) {
                            solver.reset(simdata_scratch);
                        }
                        if (event.key.keysym.sym == c.SDLK_SPACE) {
                            appstate.paused = !appstate.paused;
                        }
                    },
                    c.SDL_KEYUP => {
                        const scancode = event.key.keysym.scancode;

                        if (event.key.keysym.sym == c.SDLK_PLUS) {
                            appstate.button_states.held_zoom_button_counter =
                            appstate.button_states.held_zoom_button_counter ^ 1;
                        }
                        if (event.key.keysym.sym == c.SDLK_EQUALS) {
                            appstate.button_states.held_zoom_button_counter =
                            appstate.button_states.held_zoom_button_counter ^ 2;
                        }
                        if (scancode == c.SDL_SCANCODE_LEFT) {
                            appstate.button_states.is_holding_left = false;
                        }
                        if (scancode == c.SDL_SCANCODE_RIGHT) {
                            appstate.button_states.is_holding_right = false;
                        }
                        if (scancode == c.SDL_SCANCODE_UP) {
                            appstate.button_states.is_holding_up = false;
                        }
                        if (scancode == c.SDL_SCANCODE_DOWN) {
                            appstate.button_states.is_holding_down = false;
                        }
                        if (event.key.keysym.sym == c.SDLK_MINUS) {
                            appstate.button_states.is_holding_zoom_out = false;
                        }
                    },
                    else => {},
                }
            }
        }
    };
}
