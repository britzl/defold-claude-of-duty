-- Source penetration depths/energy loss from src/physics/surfaces.js.
-- Impact/audio names route to effects and the generated sound bank.
return {
    concrete={depth=.055,loss=.62,fx="chips",audio="concrete"},
    metal={depth=.022,loss=.70,fx="sparks",audio="metal"},
    wood={depth=.32,loss=.30,fx="splinters",audio="wood"},
    dirt={depth=.26,loss=.45,fx="dust",audio="dirt"},
    sand={depth=.19,loss=.55,fx="dust",audio="sand"},
    glass={depth=.45,loss=.12,fx="shards",audio="glass"},
    water={depth=1.1,loss=.50,fx="splash",audio="water"},
    foliage={depth=3,loss=.05,fx="leaves",audio="foliage"},
    fabric={depth=2.2,loss=.06,fx="fibres",audio="fabric"},
    flesh={depth=.55,loss=.35,fx="flesh",audio="flesh"},
    rubber={depth=.28,loss=.40,fx="chips",audio="rubber"},
    plaster={depth=.7,loss=.12,fx="dust",audio="plaster"},
}
