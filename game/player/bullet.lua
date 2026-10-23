local T = require "game.player.tuning"
local M = {}
local mt = { __index = M }

-- static_revision opts in only for movers whose filter sees static world
-- geometry exclusively. It returns nil while changes are pending in Defold.
function M.new(url, surfaces, static_revision)
    local object = assert(bullet3d.get_collision_object(url), "Player collision object missing")
    local query = setmetatable({ object = object, world = bullet3d.get_world(),
        shape = bullet3d.collision_object.get_shape(object, 1), surfaces = surfaces,
        position = vmath.vector3(), translation = vmath.vector3(),
        shape_position = vmath.vector3(), identity = vmath.quat(),
        filter = { category_bits = bullet3d.collision_object.get_collision_filter_group(object),
            mask_bits = bullet3d.collision_object.get_collision_filter_mask(object),
            include_triggers = false, ignore = object },
        definition = { type = bullet3d.shape.SHAPE_TYPE_CAPSULE, diameter = 2*T.radius },
        sphere = { type = bullet3d.shape.SHAPE_TYPE_SPHERE },
        contacts_result = {}, contacts_pool = {},
    }, mt)
    if static_revision then
        query.static_clearance = { revision = static_revision, object = object,
            world = query.world, shape = query.shape,
            category = query.filter.category_bits, mask = query.filter.mask_bits }
    end
    return query
end

function M:clearance_revision()
    local c, f = self.static_clearance, self.filter
    if c and self.object == c.object and self.world == c.world and self.shape == c.shape
        and f.category_bits == c.category and f.mask_bits == c.mask
        and f.ignore == c.object and f.include_triggers == false then
        return c.revision()
    end
end

function M:begin_step()
    -- Defold can synchronize kinematic bodies between fixed ticks. Only skip
    -- duplicate writes within our current movement/synchronization phase.
    self.body_x=nil
end

function M:sync(feet, height)
    local resized = self.height ~= height
    if resized then
        bullet3d.shape.set_shape(self.shape, { type = bullet3d.shape.SHAPE_TYPE_CAPSULE,
            diameter = 2*T.radius, height = height-2*T.radius })
        self.shape_position.y = height/2
        bullet3d.shape.set_local_transform(self.shape, self.shape_position, self.identity)
        self.height = height
    end
    -- This adapter owns the kinematic mover. Query vectors are shared scratch,
    -- so cache the last BODY coordinates separately from ray/sweep origins.
    if resized or self.body_x~=feet.x or self.body_y~=feet.y or self.body_z~=feet.z then
        self.position.x, self.position.y, self.position.z = feet.x, feet.y, feet.z
        bullet3d.collision_object.set_position(self.object, self.position)
        self.body_x,self.body_y,self.body_z=feet.x,feet.y,feet.z
    end
end

function M:contacts(feet, height)
    self:sync(feet, height)
    -- Contacts are consumed before the next contacts() call. Reuse their flat
    -- Lua view, but always ask Bullet again: other bodies can move between calls.
    local out,pool = self.contacts_result,self.contacts_pool
    local count=0
    if profiler then profiler.scope_begin("capsule.contacts") end
    local contacts=bullet3d.world.contact_test(self.world, self.object, self.filter)
    if profiler then profiler.scope_end() end
    for i, c in ipairs(contacts) do
        local value=pool[i] or {};pool[i]=value;out[i]=value;count=i
        value.distance,value.nx,value.ny,value.nz=c.distance,c.normal_on_b.x,c.normal_on_b.y,c.normal_on_b.z
    end
    for i=#out,count+1,-1 do out[i]=nil end
    return out
end

function M:fits(feet, height)
    -- Contact distances distinguish penetration from harmless touching.
    self:sync(feet, height)
    for _, contact in ipairs(bullet3d.world.contact_test(self.world, self.object, self.filter)) do
        if contact.distance < -0.0001 then return false end
    end
    return true
end

function M:ray(origin, dx, dy, dz)
    self.position.x, self.position.y, self.position.z = origin.x, origin.y, origin.z
    self.translation.x, self.translation.y, self.translation.z = dx, dy, dz
    local hit = bullet3d.world.cast_ray_closest(self.world, self.position, self.translation, self.filter)
    if not hit then return nil end
    local shape = self.surfaces[bullet3d.get_gameobject_id(hit.object)]
    return { x = hit.point.x, y = hit.point.y, z = hit.point.z,
        nx = hit.normal.x, ny = hit.normal.y, nz = hit.normal.z,
        surface = shape and shape.surface or "concrete" }
end

function M:camera_fraction(origin, dx, dy, dz, radius)
    local distance = math.sqrt(dx*dx+dy*dy+dz*dz)
    if distance < 1e-6 then return 1 end
    self.position.x, self.position.y, self.position.z = origin.x, origin.y, origin.z
    self.sphere.position, self.sphere.diameter = self.position, radius*2
    if #bullet3d.world.overlap_shape(self.world, self.sphere, self.filter, 1) > 0 then return 0 end
    self.translation.x, self.translation.y, self.translation.z = dx, dy, dz
    local hit = bullet3d.world.cast_shape_closest(self.world, self.sphere, self.translation, self.filter)
    return hit and math.max(0, hit.fraction-T.skin/distance) or 1
end

function M:sweep(feet, height, dx, dy, dz)
    local distance = math.sqrt(dx*dx+dy*dy+dz*dz)
    if distance < 1e-6 then return nil end
    local definition = self.definition
    self.position.x, self.position.y, self.position.z = feet.x, feet.y+height/2, feet.z
    definition.position, definition.height = self.position, height-2*T.radius
    self.translation.x, self.translation.y, self.translation.z = dx, dy, dz
    if profiler then profiler.scope_begin("capsule.sweep") end
    local hits=bullet3d.world.cast_shape(self.world, definition, self.translation, self.filter)
    if profiler then profiler.scope_end() end
    for _, hit in ipairs(hits) do
        local n = hit.normal
        -- Tangent contacts on a floor must not mask a wall further ahead.
        if dx*n.x+dy*n.y+dz*n.z < -distance*0.0001 then
            local shape = self.surfaces[bullet3d.get_gameobject_id(hit.object)]
            return { fraction = hit.fraction, nx = n.x, ny = n.y, nz = n.z,
                surface = shape and shape.surface or "concrete" }
        end
    end
end

return M
