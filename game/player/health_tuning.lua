-- Shared Three.js/Kaigen health tuning. Health itself is owned by game.combat.
return {
    regeneration = { delay=4.6, rate=34, ramp=0.55 },
    fall_speed=15, fall_damage_per_speed=7,
    low=0.36, critical=0.18,
    suppression = { radius=3.2, near_miss=0.28, hit=0.5, explosion=0.85, decay=0.62 },
    effect_tau=0.25, flash=0.85, flash_tau=0.22,
    heartbeat_min=1.05, heartbeat_max=2.05,
}
