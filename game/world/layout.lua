-- Small, unrotated excerpt of the reference src/world/layout.js.
-- Preserve STREET and W2/E2 footprints. W2 has a shop and an upstairs apartment.
-- Bounds are metres in level space, +Y up, street towards -Z.
return {
    seed = 1337,
    chunk_size = 16,
    street = { half_width = 4.5, kerb = 6.5, walk_height = 0.145, z_min = -16, z_max = 12 },
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
            material = "plaster_blue", side = -1 },
    },
    wall = 0.3,
    storey = 3.2,
    slab = 0.2,
    -- Large props have intentional simple collision; tiny trim is visual only.
    stalls = { { x = -3.2, z = 6.4, w = 2.4 }, { x = 3, z = -9, w = 2.2 } },
    crates = { { x = -10, z = -5.5 }, { x = -11.2, z = -5.5 }, { x = 5.4, z = -4.5 } },
    spawn = { x = 0, y = 0, z = 10 },
    views = {
        street = { position = { x = 0, y = 1.66, z = 10 }, yaw = 0, pitch = 0, title = "MARKET STREET" },
        shop = { position = { x = -2.8, y = 1.805, z = 4.8 }, yaw = 0.68, pitch = 0, title = "THE SHOPFRONT" },
        room = { position = { x = -14.5, y = 1.805, z = -3.2 }, yaw = -2.05, pitch = 0, title = "INSIDE W2" },
        stairs = { position = { x = -17, y = 1.805, z = 3.2 }, yaw = 0.36, pitch = 0.24, title = "W2 STAIRCASE" },
        upstairs = { position = { x = -12.5, y = 5.005, z = -6.4 }, yaw = -2.85, pitch = -0.1, title = "W2 UPSTAIRS" },
    },
}
