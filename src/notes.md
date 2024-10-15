Measurements taken for:
simwidth = 3000
simheight = 2048

Everything:     20000us
-osc:           2113us
-obs:           2001us
-calculations:  1941us
-global write:  421us


Time for each operation:
obstacles + oscillators:    18000us
calculations:                  60us
global write:                1500us


calculation for 256 elements per iter: 60us
to precalculate the next frame




---

Measurements taken for:
simwidth = 3000
simheight = 2048

Everything:     2221us
-osc+obs        2025us
-calculations:  1944us
-global write:  438us

Time for each operation:
obs + osc:      200us
calculations:   80us
global write:   1500us


----


Measuring kernel enqueue overhead:
1 enqueue: 438us        (438us per task)
3 enqueue: 740us        (247us per task)
10 enqueue: 1240us      (124us per task)
100 enqueue: 5270us     (52 per task)
1000 enqueue: 45937us   (45 per task)

With global write:
1000 enqueues: 118092us     (118us per task)

With calculations and global write and modifier:
1000 enqueues: 1544510us    (1544us per task)
1000 enqueues: 1514704us    (1514us per task)

With 
1000 enqueues: 1514704us    (1514us per task)

