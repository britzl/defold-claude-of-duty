#include "pose.h"
#include <cmath>
#include <cstring>
#ifdef SOLDIERPOSE_STANDALONE
#include <lua.hpp>
#define POSE_PROFILE(name)
#else
#include <dmsdk/sdk.h>
#include <dmsdk/dlib/profile.h>
#define POSE_PROFILE(name) DM_PROFILE(name)
#endif

namespace {
using namespace soldier_pose;
const char* Meta="soldierpose.context";
const char* Names[]={"Hips","Spine","Spine1","Spine2","Neck","Head","HeadTop",
    "ClavicleR","UpperArmR","ForearmR","HandR","FingersR",
    "ClavicleL","UpperArmL","ForearmL","HandL","FingersL",
    "UpLegR","LegR","FootR","ToeR","UpLegL","LegL","FootL","ToeL"};
// Fixed-size userdata owns all native storage. No external allocations or Lua
// registry references, so errors and abandoned/reset actors are reclaimed by GC.
struct Context { Rig rig;Pose pose;State previous;bool valid,closed;unsigned evaluations,reuses; };
Context* Check(lua_State* L) {
    Context* c=(Context*)luaL_checkudata(L,1,Meta);
    luaL_argcheck(L,!c->closed,1,"pose context is closed");return c;
}
double Number(lua_State* L,int table,const char* key,double fallback=0,bool required=false,bool* valid=0) {
    lua_getfield(L,table,key);double value=fallback;
    if(lua_isnil(L,-1) && !required) {lua_pop(L,1);return value;}
    if(lua_type(L,-1)!=LUA_TNUMBER || !std::isfinite(value=lua_tonumber(L,-1))) {
        if(valid) {*valid=false;value=fallback;} else luaL_error(L,"%s must be a finite number",key);
    }
    lua_pop(L,1);return value;
}
Vec Vector(lua_State* L,int table,bool* valid=0) {
    if(!lua_istable(L,table)) {
        if(valid) {*valid=false;return {0,0,0};} else luaL_checktype(L,table,LUA_TTABLE);
    }
    return {Number(L,table,"x",0,true,valid),Number(L,table,"y",0,true,valid),Number(L,table,"z",0,true,valid)};
}
bool VectorField(lua_State* L,int table,const char* key,Vec& out,bool required=false,bool* valid=0) {
    lua_getfield(L,table,key);
    if(lua_isnil(L,-1) && !required) {lua_pop(L,1);return false;}
    out=Vector(L,lua_gettop(L),valid);lua_pop(L,1);return true;
}
bool ReadState(lua_State* L,State& s) {
    // Initialize padding too: exact state memoization uses memcmp, with no
    // tolerances that could conceal a moving target or a partial clip blend.
    std::memset(&s,0,sizeof(s));bool valid=true;
#define READ_FIELD(member,key,value) s.member=Number(L,2,key,value,false,&valid);
    SOLDIER_POSE_FIELDS(READ_FIELD)
#undef READ_FIELD
    lua_getfield(L,2,"variant");const char* variant=lua_tostring(L,-1);
    s.variant=variant && !std::strcmp(variant,"irregular")?1:variant && !std::strcmp(variant,"breacher")?2:0;
    lua_pop(L,1);
    lua_getfield(L,2,"hit_region");const char* region=lua_tostring(L,-1);
    s.hit_region=region && !std::strcmp(region,"head")?1:region && !std::strcmp(region,"arm")?2:region && !std::strcmp(region,"leg")?3:0;
    lua_pop(L,1);
    s.has_vault_hand=VectorField(L,2,"vault_hand",s.vault_hand,false,&valid);
    lua_getfield(L,2,"feet");
    if(!lua_isnil(L,-1)) {
        if(!lua_istable(L,-1)) {lua_pop(L,1);return false;}
        for(int side=0;side<2;++side) {
            lua_getfield(L,-1,side==0?"R":"L");
            if(!lua_isnil(L,-1)) {
                int t=lua_gettop(L);
                if(!lua_istable(L,t)) {lua_pop(L,2);return false;}
                Foot& f=s.feet[side];f.present=true;
                f.weight=Number(L,t,"weight",0,true,&valid);f.normal={0,1,0};
                VectorField(L,t,"target",f.target,f.weight>0,&valid);VectorField(L,t,"normal",f.normal,false,&valid);
            }
            lua_pop(L,1);
        }
    }
    lua_pop(L,1);
    return valid;
}
int New(lua_State* L) {
    luaL_checktype(L,1,LUA_TTABLE);luaL_checktype(L,2,LUA_TTABLE);luaL_checktype(L,3,LUA_TTABLE);
    Context* c=(Context*)lua_newuserdata(L,sizeof(Context));std::memset(c,0,sizeof(*c));
    luaL_getmetatable(L,Meta);lua_setmetatable(L,-2);
    for(int i=0;i<BoneCount;++i) {
        lua_rawgeti(L,1,i+1);int t=lua_gettop(L);luaL_checktype(L,t,LUA_TTABLE);
        lua_getfield(L,t,"name");const char* name=lua_tostring(L,-1);
        if(!name || std::strcmp(name,Names[i])) return luaL_error(L,"unexpected bone at index %d",i+1);
        lua_pop(L,1);double parent=Number(L,t,"parent",0,true);
        if(parent<0 || parent>i || std::floor(parent)!=parent) return luaL_error(L,"invalid bone parent");
        c->rig.bones[i].parent=(int)parent-1;
        VectorField(L,t,"bind",c->rig.bones[i].bind,true);
        VectorField(L,t,"local_position",c->rig.bones[i].local,true);lua_pop(L,1);
    }
    lua_rawgeti(L,1,BoneCount+1);bool extra=!lua_isnil(L,-1);lua_pop(L,1);
    if(extra) return luaL_error(L,"expected exactly 25 bones");
    c->rig.grip=Vector(L,2);
    VectorField(L,3,"magazine",c->rig.magazine,true);
    const char* variants[]={"vanguard","irregular","breacher"};
    for(int i=0;i<3;++i) {
        lua_getfield(L,3,variants[i]);int t=lua_gettop(L);luaL_checktype(L,t,LUA_TTABLE);
        c->rig.variants[i].scale=Number(L,t,"scale",0,true);
        if(c->rig.variants[i].scale<=0) return luaL_error(L,"variant scale must be positive");
        VectorField(L,t,"support",c->rig.variants[i].support,true);lua_pop(L,1);
    }
    return 1;
}
void SetNumber(lua_State* L,int table,const char* key,double value) {lua_pushnumber(L,value);lua_setfield(L,table,key);}
// Destinations are caller-owned reusable tables, matching rig.pose's API.
// Keep references on the Lua stack, not in a cross-actor/native registry.
int TableField(lua_State* L,int table,const char* key,int array) {
    lua_getfield(L,table,key);
    if(!lua_istable(L,-1)) {lua_pop(L,1);lua_createtable(L,array,0);lua_pushvalue(L,-1);lua_setfield(L,table,key);}
    return lua_gettop(L);
}
void WriteMatrix(lua_State* L,int table,const Mat& m) {
    for(int k=0;k<12;++k) {lua_pushnumber(L,m.m[k]);lua_rawseti(L,table,k+1);}
}
void WriteMatrices(lua_State* L,int table,const Mat* matrices) {
    for(int i=0;i<BoneCount;++i) {
        lua_rawgeti(L,table,i+1);
        if(!lua_istable(L,-1)) {lua_pop(L,1);lua_createtable(L,12,0);lua_pushvalue(L,-1);lua_rawseti(L,table,i+1);}
        WriteMatrix(L,lua_gettop(L),matrices[i]);lua_pop(L,1);
    }
}
int EvalProfiled(lua_State* L,Context* c) {
    POSE_PROFILE("rig.native");
    State state;bool valid;
    {POSE_PROFILE("rig.native_input");valid=ReadState(L,state);}
    if(!valid) return 0;
    bool reused=c->valid && !std::memcmp(&state,&c->previous,sizeof(state));
    if(reused) {POSE_PROFILE("rig.native_reuse");++c->reuses;}
    else {
        POSE_PROFILE("rig.native_math");Evaluate(c->rig,state,c->pose);
        std::memcpy(&c->previous,&state,sizeof(state));c->valid=true;++c->evaluations;
    }
    {
        POSE_PROFILE("rig.native_output");
        int palette=TableField(L,3,"palette",BoneCount);WriteMatrices(L,palette,c->pose.palette);
        int worlds=TableField(L,3,"worlds",BoneCount);WriteMatrices(L,worlds,c->pose.worlds);
        int weapon=TableField(L,3,"weapon_frame",12);WriteMatrix(L,weapon,c->pose.weapon);lua_pop(L,1);
        int support=TableField(L,3,"support_target",0);
        SetNumber(L,support,"x",c->pose.support.x);SetNumber(L,support,"y",c->pose.support.y);SetNumber(L,support,"z",c->pose.support.z);lua_pop(L,1);
        SetNumber(L,3,"support_error",c->pose.support_error);SetNumber(L,3,"reach_drop",c->pose.reach_drop);
    }
    return 2;
}
int Eval(lua_State* L) {
    Context* c=Check(L);luaL_checktype(L,2,LUA_TTABLE);luaL_checktype(L,3,LUA_TTABLE);
    int result=EvalProfiled(L,c);
    // luaL_error longjmps: leave C++ profiling scopes before reporting errors.
    return result?result:luaL_error(L,"invalid pose state: expected finite numbers and complete vectors");
}
int Close(lua_State* L) {Context* c=(Context*)luaL_checkudata(L,1,Meta);c->closed=true;return 0;}
int Stats(lua_State* L) {
    Context* c=Check(L);lua_createtable(L,0,3);int t=lua_gettop(L);
    SetNumber(L,t,"evaluations",c->evaluations);SetNumber(L,t,"reuses",c->reuses);SetNumber(L,t,"bytes",sizeof(Context));return 1;
}
const luaL_Reg Methods[]={{"new",New},{"evaluate",Eval},{"close",Close},{"stats",Stats},{0,0}};
void RegisterMeta(lua_State* L) {luaL_newmetatable(L,Meta);lua_pop(L,1);}
#ifndef SOLDIERPOSE_STANDALONE
dmExtension::Result Initialize(dmExtension::Params* params) {
    lua_State* L=params->m_L;int top=lua_gettop(L);RegisterMeta(L);
    luaL_register(L,"soldierpose",Methods);lua_pop(L,1);assert(lua_gettop(L)==top);return dmExtension::RESULT_OK;
}
#endif
}
#ifdef SOLDIERPOSE_STANDALONE
extern "C" int luaopen_soldierpose(lua_State* L) {RegisterMeta(L);luaL_newlib(L,Methods);return 1;}
#else
DM_DECLARE_EXTENSION(SoldierPose,"SoldierPose",0,0,Initialize,0,0,0)
#endif
