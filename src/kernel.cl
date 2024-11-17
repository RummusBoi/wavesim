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
