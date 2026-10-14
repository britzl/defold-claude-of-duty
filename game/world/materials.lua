-- sRGB tint multiplied by the recipe's linear albedo. The four reference
-- recipes supply their own base colour; wood/asphalt must not be tinted twice.
return {
    asphalt = { color = { 1, 1, 1 }, kind = 1 },
    concrete = { color = { .663, .643, .604 }, kind = 5 },
    plaster_sand = { color = { .725, .647, .510 }, kind = 0 },
    plaster_blue = { color = { .561, .604, .627 }, kind = 0 },
    plaster_cream = { color = { .812, .753, .643 }, kind = 0 },
    dirt = { color = { 1, .88, .69 }, kind = 1 },
    plaster_inside = { color = { 0.70, 0.67, 0.55 }, kind = 0 },
    trim = { color = { 0.82, 0.76, 0.60 }, kind = 0 },
    wood = { color = { 1, 1, 1 }, kind = 2 },
    shutters = { color = { .35, .70, .68 }, kind = 2 },
    metal = { color = { 0.19, 0.22, 0.23 }, kind = 3 },
    dark = { color = { 0.065, 0.075, 0.07 }, kind = 0 },
    awning_red = { color = { 0.67, 0.23, 0.12 }, kind = 4 },
    awning_cream = { color = { 0.86, 0.77, 0.53 }, kind = 4 },
    produce = { color = { 0.62, 0.43, 0.13 }, kind = 0 },
}
