struct Oscillator {
    int id;
    int x;
    int y;
    float amplitude;
    float wavelengths[5];
    int wavelength_count;
};

struct Coordinate {
    int x;
    int y;
};

struct Vector {
    float x;
    float y;
    float z;
};

struct Locale {
    float left;
    float right;
    float up;
    float down;
    float here;
};

kernel void wavesim(constant float* data,
                    constant float* prev_data,
                    global float* tmp_data,
                    int width,
                    int height,
                    float grid_spacing,
                    float dt,
                    float propagation_speed
    ) {
    // const size_t lid = get_local_id(0);
    const size_t gid = get_global_id(0) + width;
    int x = gid % width;
    int y = gid / width;


    float value_to_write = 0.0;
    float first_part = data[gid-1] + data[gid + 1] + data[gid-width] + data[gid+width] - data[gid] * 4.0; // roughly 4000
    float divisor = grid_spacing * grid_spacing; // always 1
    float derivative = first_part / divisor; // roughly 4000
    float new_value = propagation_speed * propagation_speed * derivative * dt * dt + 2 * data[gid] - prev_data[gid];
    //                  100 * 100 * 4000 * 0.001 * 0.001 + 2 * 1000 - 1000 = 4

    float modifier = 1;
    float bound = 0.1;
    // if ((x > (1 - bound) * width) || (x < bound * width) || (y > (1 - bound) * height) || (y < bound * height)) {
    //     modifier = 0.90;
    // } else {
    //     modifier = 1;
    // }

    value_to_write = new_value * modifier;

    tmp_data[gid] = value_to_write;
}


kernel void compute_oscillators(
                    global float* tmp_data,
                    int width,
                    float dt,
                    float propagation_speed,
                    int iteration,
                    constant struct Oscillator* oscillators) {
    size_t gid = get_global_id(0);

    struct Oscillator this_oscillator = oscillators[gid];
    float wavelength_sum = 0.0;
    float value_to_write = 0.0;
    for (int i = 0; i < this_oscillator.wavelength_count; i++) {
        wavelength_sum += sin(1 / this_oscillator.wavelengths[i] * (iteration * dt) * propagation_speed * 3.14159265359);
    }
    value_to_write = this_oscillator.amplitude * wavelength_sum;

    tmp_data[this_oscillator.y * width + this_oscillator.x] = value_to_write;
}

kernel void compute_obstacles(
                    global float* tmp_data,
                    int width,
                    int height,
                    constant struct Coordinate* obstacles) {
    size_t gid = get_global_id(0);
    struct Coordinate this_obstacle = obstacles[gid];
    int x = this_obstacle.x;
    int y = this_obstacle.y;
    tmp_data[y * width + x] = 0;
}

struct Vector cross_product(struct Vector v1, struct Vector v2) {
    struct Vector result = {
        .x = v1.y * v2.z - v1.z * v2.y,
        .y = v1.z * v2.x - v1.x * v2.z,
        .z = v1.x * v2.y - v1.y * v2.x,
    };
    return result;
}

float norm(struct Vector v) {
    return sqrt(pow(v.x, 2) + pow(v.y, 2) + pow(v.z, 2));
}

// In degrees.
float angle(struct Vector v1, struct Vector v2) {
    float divisor = (norm(v1) * norm(v2));
    float res = norm(cross_product(v1, v2)) / divisor;
    return asinpi(res) * 180.0;
}

kernel void draw(float* data_to_write, float* simdata, int height, int width) {
    const size_t gid = get_global_id(0);
    int x = gid % width;
    int y = gid / width;

    map_to_color()
}

// Returns the angle of the normal vector to the z axis, with a few conditions:
// - Returns 0 or 255 if angle < 0 or angle > 255.
// - Returns sqrt(angle) if angle > 100.
// - Else, returns angle.
kernel void map_to_color(struct Locale locale) {
    struct Vector q = {
        .x = 0,
        .y = 0,
        .z = locale.here,
    };

    struct Vector r = {
        .x = 0,
        .y = 1,
        .z = (locale.up - locale.down) / 2,
    };

    struct Vector s = {
        .x = 1,
        .y = 0,
        .z = (locale.right - locale.left) / 2,
    };

    struct Vector qr = {
        .x = r.x - q.x,
        .y = r.y - q.y,
        .z = r.z - q.z,
    };

    struct Vector qs = {
        .x = s.x - q.x,
        .y = s.y - q.y,
        .z = s.z - q.z,
    };

    struct Vector normal_vector = cross_product(qr, qs);
    struct Vector z_axis = {
        .x = 0,
        .y = 0,
        .z = 1,
    };

    float angle_to_z_axis = angle(normal_vector, z_axis);

    // If angle is 0, then it will be blue. Otherwise it will be gradually lighter.
    if (angle_to_z_axis < 0) {
        // return 0.0;
    }
    if (angle_to_z_axis > 255) {
        // return 255.0;
    }
    if (angle_to_z_axis > 100) {
        // return pow(angle_to_z_axis, 0.5);
    }
    // write shizzle?
}
