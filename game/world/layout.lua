-- Unrotated market excerpt of the reference src/world/layout.js.
-- W1/W3 frame a west flank around W2; W2/E2 have shops and upper rooms.
-- Bounds are metres in level space, +Y up, street towards -Z.
return {
    seed = 1337,
    chunk_size = 16,
    street = { half_width = 4.5, kerb = 6.5, walk_height = 0.145, z_min = -28, z_max = 22 },
    buildings = {
        { id = "W2", x = -14, z = -1.5, w = 15, d = 13, floors = 2,
            material = "plaster_sand", side = 1, room = true,
            door = { z = 0, width = 2.8, height = 2.65 },
            -- One straight flight; its opening follows the reference W2 stair hole.
            stairs = { x = -19.2, z = 1.5, width = 1.8, run = 6.3, steps = 16,
                hole_width = 2.4, landing = 0.75 },
            upper = { partition_x = -14, door_z = -5.55, door_width = 1.6,
                bedroom_z = -0.8, bedroom_door_x = -10, bedroom_door_width = 1.6,
                door_height = 2.4,
                bed = { x = -10.9, z = 2.5, w = 2, d = 2.5 },
                desk = { x = -7.8, z = -5.8, w = 1.2, d = 1.6 },
                cabinet = { x = -7.5, z = 2.4, w = .8, d = 2 },
                rug = { x = -11, z = -3, w = 3, d = 2 } },
            -- Furniture centres in normalized footprint coordinates.
            counter = { x = 0.72, z = 0.83, w = 3.5, d = 0.8 },
            shelves = { x = 0.035, z = 0.46, w = 0.7, d = 4 } },
        { id = "E2", x = 13.5, z = -5, w = 14, d = 14, floors = 3,
            material = "plaster_blue", side = -1, room = true,
            door = { z = -6.5, width = 2.4, height = 2.65 },
            -- Mirrored entrance and a +Z flight repeated between all three floors.
            stairs = { x = 18.1, z = -9, direction = 1, width = 1.8,
                run = 6.4, steps = 16, hole_width = 2.4, landing = .75 },
            upper = { partition_x = 13.5, door_z = -1.85, door_width = 1.6,
                bedroom_z = -6, bedroom_side = -1, bedroom_door_x = 10,
                bedroom_door_width = 1.6, door_height = 2.4,
                bed = { x = 10.5, z = -9.6, w = 2, d = 2.5 },
                desk = { x = 7.8, z = -.3, w = 1.2, d = 1.6 },
                cabinet = { x = 7.5, z = -9, w = .8, d = 2 },
                rug = { x = 10, z = -3.5, w = 3, d = 2 } },
            counter = { x = .16, z = .83, w = 3.5, d = .8 },
            shelves = { x = .96, z = .55, w = .7, d = 4 } },
        { id = "W1", x = -13.5, z = 15, w = 14, d = 10, floors = 2,
            material = "plaster_cream", side = 1 },
        { id = "W3", x = -13, z = -19, w = 13, d = 14, floors = 2,
            material = "plaster_blue", side = 1 },
    },
    -- Reference west courtyard and mid-street alley, widened to meet the actual
    -- building edges without unsupported strips. The rear lane closes the loop.
    ground = {
        { id = "west_courtyard", x0 = -25.5, x1 = -6.5, z0 = 5, z1 = 10, y = 0, material = "dirt", surface = "dirt" },
        { id = "west_alley", x0 = -25.5, x1 = -6.5, z0 = -12, z1 = -8, y = 0, material = "dirt", surface = "dirt" },
        { id = "west_rear", x0 = -25.5, x1 = -21.5, z0 = -8, z1 = 5, y = 0, material = "dirt", surface = "dirt" },
    },
    -- Endpoints create street/kerb links; intermediate points stay on the ground
    -- rectangles above. All links are bidirectional and validated with Bullet.
    routes = {
        { id = "west_loop", points = {
            { id = "north_entry", x = -7.5, y = 0, z = 7.5 },
            { id = "courtyard", x = -18, y = 0, z = 7.5 },
            { id = "rear_north", x = -23.5, y = 0, z = 7.5 },
            { id = "rear_mid", x = -23.5, y = 0, z = -1.5 },
            { id = "rear_south", x = -23.5, y = 0, z = -10 },
            { id = "alley", x = -18, y = 0, z = -10 },
            { id = "south_entry", x = -7.5, y = 0, z = -10 },
        } },
    },
    -- Yard walls bound the rear route where neighbouring footprints stop.
    walls = {
        { id = "west_boundary", x = -25.7, z = -1, w = .4, d = 22.8, h = 2.4 },
        { id = "courtyard_end", x = -23, z = 10.2, w = 5, d = .4, h = 2.4 },
        { id = "alley_end", x = -22.5, z = -12.2, w = 6, d = .4, h = 2.4 },
    },
    covers = {
        { id = "barrier", x = 1.6, z = -2.5, w = .6, h = .9, d = 2.5, normal_x = -1, normal_z = 0 },
        { id = "courtyard", x = -13.5, z = 8.9, w = 2.4, h = 1.1, d = .65, normal_x = 0, normal_z = 1 },
        { id = "alley", x = -13.5, z = -10.9, w = 2.4, h = 1.1, d = .65, normal_x = 0, normal_z = -1 },
    },
    wall = 0.3,
    storey = 3.2,
    slab = 0.2,
    -- Large props have intentional simple collision; tiny trim is visual only.
    stalls = { { x = -3.2, z = 6.4, w = 2.4 }, { x = 3, z = -9, w = 2.2 } },
    crates = { { x = -10, z = -5.5, normal_x = 1 }, { x = -11.2, z = -5.5 }, { x = 5.4, z = -4.5 },
        { x = -24.8, z = 1.5, y = 0, normal_x = 1, normal_z = 0 } },
    spawn = { x = 0, y = 0, z = 10 },
    views = {
        courtyard = { position = { x = -7.8, y = 1.66, z = 7.4 }, yaw = 1.5, pitch = 0, title = "WEST COURTYARD" },
        alley = { position = { x = -8, y = 1.66, z = -10 }, yaw = 1.57, pitch = 0, title = "WEST ALLEY" },
        rear = { position = { x = -23.5, y = 1.66, z = 6.8 }, yaw = 0, pitch = 0, title = "BEHIND W2" },
        street = { position = { x = 0, y = 1.66, z = 10 }, yaw = 0, pitch = 0, title = "MARKET STREET" },
        shop = { position = { x = -2.8, y = 1.805, z = 4.8 }, yaw = 0.68, pitch = 0, title = "THE SHOPFRONT" },
        room = { position = { x = -14.5, y = 1.805, z = -3.2 }, yaw = -2.05, pitch = 0, title = "INSIDE W2" },
        stairs = { position = { x = -17, y = 1.805, z = 3.2 }, yaw = 0.36, pitch = 0.24, title = "W2 STAIRCASE" },
        e2_shop = { position = { x = 9.5, y = 1.805, z = -6.5 }, yaw = -1.25, pitch = 0, title = "INSIDE E2" },
        e2_stairs = { position = { x = 15.7, y = 1.805, z = -10 }, yaw = -2.82, pitch = .22, title = "E2 STAIRCASE" },
        e2_upstairs = { position = { x = 11.5, y = 5.005, z = -.5 }, yaw = .2, pitch = -.05, title = "E2 FIRST FLOOR" },
        e2_top = { position = { x = 11.5, y = 8.205, z = -.5 }, yaw = .2, pitch = -.05, title = "E2 SECOND FLOOR" },
        upstairs = { position = { x = -12.5, y = 5.005, z = -6.4 }, yaw = -2.85, pitch = -0.1, title = "W2 UPSTAIRS" },
    },
}
