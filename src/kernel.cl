struct Obstacle {
    int x;
    int y;
    int width;
    int height;
};

struct Oscillator {
    int x;
    int y;
    float amplitude;
    float wavelengths[5];
};

kernel void wavesim(global float* data, 
                    global float* prev_data, 
                    global float* tmp_data, 
                    int width, 
                    int height, 
                    float grid_spacing, 
                    float dt, 
                    float propagation_speed, 
                    int iteration, 
                    global struct Obstacle* obstacles, 
                    int obstacle_count,
                    global struct Oscillator* oscillators,
                    int oscillator_count
    ) {

    const size_t gid = get_global_id(0);
    int x = gid % width;
    int y = gid / width;
    
    for (int i = 0; i < obstacle_count; i++) {
        if (x >= obstacles[i].x && x < obstacles[i].x + obstacles[i].width && y >= obstacles[i].y && y < obstacles[i].y + obstacles[i].height) {
            tmp_data[y * width + x] = 0;
            return;
        }
    }

    for (int i = 0; i < oscillator_count; i++) {
        if (x == oscillators[i].x && y == oscillators[i].y) {
            float wavelength_sum = 0.0;
            for (int j = 0; j < 5; j++) {
                wavelength_sum += sin(1 / oscillators[i].wavelengths[j] * (iteration * dt) * propagation_speed * 3.14159265359);
            }
            tmp_data[oscillators[i].y * width + oscillators[i].x] = oscillators[i].amplitude * wavelength_sum;
            return;
        }
    }

    
    float first_part = data[y * width + x - 1] + data[y * width + x + 1] + data[(y - 1) * width + x] + data[(y + 1) * width + x] - data[y * width + x] * 4.0;
    // const first_part = (self.data[@intCast(@max(y * width + x - 1, 0))] + self.data[@intCast(@min(y * width + x + 1, width * height - 1))] + self.data[@intCast(@max((y - 1) * width + x, 0))] + self.data[@intCast(@min((y + 1) * width + x, width * height - 1))] - self.data[@intCast(y * width + x)] * 4.0);
    float divisor = grid_spacing * grid_spacing;
    float derivative = first_part / divisor;
    float new_value = propagation_speed * propagation_speed * derivative * dt * dt + 2 * data[y * width + x] - prev_data[y * width + x];
    float modifier = 0;
    float bound = 0.1;
    if (x > (1 - bound) * width || x < bound * width || y > (1 - bound) * height || y < bound * height) {
        modifier = 0.999;
    } else {
        modifier = 1;
    }
    tmp_data[y * width + x] = new_value * modifier;
}