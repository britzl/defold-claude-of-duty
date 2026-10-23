#ifndef SOLDIER_POSE_H
#define SOLDIER_POSE_H

namespace soldier_pose {
const int BoneCount=25;
enum Joint { Hips,Spine,Spine1,Spine2,Neck,Head,HeadTop,
    ClavicleR,UpperArmR,ForearmR,HandR,FingersR,
    ClavicleL,UpperArmL,ForearmL,HandL,FingersL,
    UpLegR,LegR,FootR,ToeR,UpLegL,LegL,FootL,ToeL };
struct Vec { double x,y,z; };
struct Mat { double m[12]; };
struct Bone { int parent; Vec bind,local; };
struct Variant { double scale; Vec support; };
struct Rig { Bone bones[BoneCount]; Vec grip,magazine; Variant variants[3]; };
struct Foot { bool present; double weight; Vec target,normal; };
// Shared by the Lua input reader and the standalone evaluator. Keep defaults
// aligned with game/ai/rig.lua's reference evaluator.
#define SOLDIER_POSE_FIELDS(X) \
    X(time,"time",0) X(phase,"phase",0) X(walk,"walk",0) X(aim,"aim",0) \
    X(pitch,"pitch",0) X(recoil,"recoil",0) X(death,"death",0) X(crouch,"crouch",0) \
    X(run,"run",0) X(wounded,"wounded",0) X(aim_yaw,"aim_yaw",0) X(pelvis,"pelvis",0) \
    X(hit,"hit",0) X(hit_side,"hit_side",1) X(turn,"turn",0) X(turn_weight,"turn_weight",0) \
    X(turn_direction,"turn_direction",1) X(reload,"reload",0) X(reload_weight,"reload_weight",0) \
    X(vault,"vault",0) X(vault_weight,"vault_weight",0) \
    X(throw_phase,"throw",0) X(throw_weight,"throw_weight",0)
struct State {
#define DECLARE_FIELD(member,key,value) double member;
    SOLDIER_POSE_FIELDS(DECLARE_FIELD)
#undef DECLARE_FIELD
    int variant,hit_region; // vanguard/irregular/breacher; torso/head/arm/leg
    Foot feet[2];
    bool has_vault_hand;
    Vec vault_hand;
};
struct Pose {
    Mat worlds[BoneCount],palette[BoneCount],weapon;
    Vec support;
    double support_error,reach_drop;
};
void Evaluate(const Rig& rig,const State& state,Pose& output);
}
#endif
