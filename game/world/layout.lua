-- Small, unrotated excerpt of the reference src/world/layout.js.
-- Preserve STREET and W2/E2 footprints; simplify W2 to one ground-floor shop.
-- Bounds are metres in level space, +Y up, street towards -Z.
return {
    seed = 1337,
    chunk_size = 16,
    street = { half_width = 4.5, kerb = 6.5, walk_height = 0.145, z_min = -16, z_max = 12 },
    buildings = {
        { id = "W2", x = -14, z = -1.5, w = 15, d = 13, floors = 2,
            material = "plaster_sand", side = 1, room = true,
            door = { z = 0, width = 2.8, height = 2.65 },
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
    },
}
