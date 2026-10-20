components {
  id: "script"
  component: "/main/controller.script"
}
components {
  id: "world_mesh"
  component: "/world/batch.factory"
}
components {
  id: "world_collision"
  component: "/world/box.factory"
}
components { id: "weapon_mesh" component: "/weapons/part.factory" }
components { id: "weapon_arm" component: "/weapons/arm.factory" }
components { id: "weapon_effect" component: "/weapons/effect.factory" }
components { id: "soldier_mesh" component: "/soldiers/soldier.factory" }
components { id: "soldier_mover" component: "/soldiers/mover.factory" }
components { id: "soldier_hit" component: "/soldiers/hit.factory" }
components { id: "audio_voice" component: "/audio/voice.factory" }
components { id: "audio_loop" component: "/audio/loop.factory" }
components { id: "capture_mesh" component: "/render/laboratory.factory" }
components { id: "glass_mesh" component: "/render/glass.factory" }
components { id: "capture_glass" component: "/render/glass_lab.factory" }
components { id: "combat_particle" component: "/weapons/particle.factory" }
components { id: "weapon_flash" component: "/weapons/flash.factory" }
components { id: "physics_body" component: "/physics/body.factory" }
components { id: "grenade_body" component: "/physics/grenade.factory" }
