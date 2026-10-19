-- Source penetration depths/energy loss from src/physics/surfaces.js.
-- Impact/audio names route to effects and the generated sound bank.
return {
    concrete={depth=.055,loss=.62,deflect=.055,fx="chips",audio="concrete"},
    metal={depth=.022,loss=.70,deflect=.075,fx="sparks",audio="metal"},
    wood={depth=.32,loss=.30,deflect=.030,fx="splinters",audio="wood"},
    dirt={depth=.26,loss=.45,deflect=.050,fx="dust",audio="dirt"},
    sand={depth=.19,loss=.55,deflect=.060,fx="dust",audio="sand"},
    glass={depth=.45,loss=.12,deflect=.012,fx="shards",audio="glass"},
    water={depth=1.1,loss=.50,deflect=.090,fx="splash",audio="water"},
    foliage={depth=3,loss=.05,deflect=.008,fx="leaves",audio="foliage"},
    fabric={depth=2.2,loss=.06,deflect=.010,fx="fibres",audio="fabric"},
    flesh={depth=.55,loss=.35,deflect=.020,fx="flesh",audio="flesh"},
    rubber={depth=.28,loss=.40,deflect=.040,fx="chips",audio="rubber"},
    plaster={depth=.7,loss=.12,deflect=.020,fx="dust",audio="plaster"},
}
