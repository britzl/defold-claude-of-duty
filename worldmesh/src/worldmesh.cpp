#include <dmsdk/sdk.h>
#include <dmsdk/gamesys/script.h>
#include "mesh.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdio>

namespace {
using namespace worldmesh;
static const char* META="worldmesh.builder";
static const char* STREAMS[]={"position","normal","color","surface_edges","surface_masks","surface_data"};
static const char* ARRAYS[]={"positions","normals","colors","edges","masks","surfaces"};
static const int COUNTS[]={3,3,4,4,4,2};
static const int OFFSETS[]={0,3,6,10,14,18};
static Builder* Check(lua_State* L) {
    Builder** b=(Builder**)luaL_checkudata(L,1,META);
    luaL_argcheck(L,*b!=0,1,"builder is closed");return *b;
}
static double Number(lua_State* L,int table,const char* key,double fallback,bool& valid,bool required=false) {
    lua_getfield(L,table,key);
    double value=fallback;
    if (lua_isnil(L,-1)) { if (required) valid=false; }
    else if (lua_type(L,-1)!=LUA_TNUMBER || !std::isfinite(value=lua_tonumber(L,-1))) valid=false;
    lua_pop(L,1);return value;
}
static double Element(lua_State* L,int table,int index,bool& valid) {
    lua_rawgeti(L,table,index);double value=lua_tonumber(L,-1);
    if (lua_type(L,-1)!=LUA_TNUMBER || !std::isfinite(value)) valid=false;
    lua_pop(L,1);return value;
}
static std::string String(lua_State* L,int table,const char* key,bool& valid,bool required=false) {
    lua_getfield(L,table,key);std::string result;
    if (lua_isnil(L,-1)) { if (required) valid=false; }
    else if (lua_type(L,-1)!=LUA_TSTRING) valid=false;
    else result=lua_tostring(L,-1);
    lua_pop(L,1);return result;
}
// Parsing reports errors after C++ temporaries are destroyed. luaL_error uses
// longjmp in the engine and must not bypass array/string destructors.
static bool ReadShape(lua_State* L,Shape& s,Material& m,double& shade) {
    if (!lua_istable(L,2) || !lua_istable(L,3) || !lua_isnumber(L,4)) return false;
    bool valid=true;
    s.id=String(L,2,"id",valid);s.kind=String(L,2,"kind",valid);s.material=String(L,2,"material",valid,true);
    const char* pos[]={"x","y","z"};const char* dims[]={"w","h","d"};const char* rot[]={"rotation_x","rotation_y","rotation_z"};
    for (int k=0;k<3;++k) {
        s.center[k]=Number(L,2,pos[k],0,valid,true);s.size[k]=Number(L,2,dims[k],0,valid,true);
        s.rotation[k]=Number(L,2,rot[k],0,valid);
        if (std::abs(s.center[k])>100000 || s.size[k]<0 || s.size[k]>100000) valid=false;
    }
    s.bevel=Number(L,2,"bevel",.06,valid);s.taper=Number(L,2,"taper",1,valid);
    s.masks=s.kind=="card"?Rect{{0,0,0,0}}:Rect{{1,.35,.18,1}};
    lua_getfield(L,2,"weather_masks");
    if (lua_istable(L,-1)) for (int k=0;k<4;++k) s.masks[k]=Element(L,lua_gettop(L),k+1,valid);
    else if (!lua_isnil(L,-1)) valid=false;
    lua_pop(L,1);
    if (s.kind=="prism") {
        lua_getfield(L,2,"profile");
        if (!lua_istable(L,-1) || lua_objlen(L,-1)<3 || lua_objlen(L,-1)>256) valid=false;
        else for (size_t i=1;i<=lua_objlen(L,-1);++i) {
            lua_rawgeti(L,-1,(int)i);
            if (!lua_istable(L,-1)) valid=false;
            else Push(s.profile,ProfilePoint{{Element(L,lua_gettop(L),1,valid),Element(L,lua_gettop(L),2,valid)}});
            lua_pop(L,1);
        }
        lua_pop(L,1);
    }
    if (!s.kind.empty() && s.kind!="card" && s.kind!="prism" && s.kind!="torus" && s.kind!="frond" && s.kind!="bevel" && s.kind!="cylinder") valid=false;
    s.clipped=lua_istable(L,5);
    if (s.clipped) for (int f=0;f<6;++f) {
        lua_rawgeti(L,5,f+1);
        if (!lua_istable(L,-1) || lua_objlen(L,-1)>4096) valid=false;
        else for (size_t i=1;i<=lua_objlen(L,-1);++i) {
            lua_rawgeti(L,-1,(int)i);
            if (!lua_istable(L,-1)) valid=false;
            else { Rect r;for (int k=0;k<4;++k) r[k]=Element(L,lua_gettop(L),k+1,valid);Push(s.faces[f],r); }
            lua_pop(L,1);
        }
        lua_pop(L,1);
    }
    lua_getfield(L,3,"color");
    if (!lua_istable(L,-1)) valid=false;
    else for (int k=0;k<3;++k) m.color[k]=Element(L,lua_gettop(L),k+1,valid);
    lua_pop(L,1);
    m.coverage=Number(L,3,"coverage",1,valid);m.kind=Number(L,3,"kind",0,valid,true);m.weather=Number(L,3,"weather",1,valid);
    shade=lua_tonumber(L,4);return valid && std::isfinite(shade);
}
static int Close(lua_State* L) {
    Builder** b=(Builder**)luaL_checkudata(L,1,META);delete *b;*b=0;return 0;
}
static int Begin(lua_State* L) {
    luaL_checktype(L,1,LUA_TTABLE);
    double chunk=luaL_checknumber(L,2);int limit=luaL_checkint(L,3);
    luaL_argcheck(L,std::isfinite(chunk) && chunk>0,2,"invalid chunk size");
    luaL_argcheck(L,limit>0 && limit<=65536,3,"invalid batch limit");
    Builder** owner=(Builder**)lua_newuserdata(L,sizeof(Builder*));*owner=0;
    luaL_getmetatable(L,META);lua_setmetatable(L,-2);*owner=new Builder(chunk,(size_t)limit);
    bool valid=true;
    lua_pushnil(L);
    while (lua_next(L,1)) {
        if (lua_type(L,-2)!=LUA_TSTRING || !lua_istable(L,-1)) valid=false;
        else {
            dmArray<double>* line=new dmArray<double>;
            uint64_t key=dmHashString64(lua_tostring(L,-2));
            // Keep ownership in the userdata even if a later entry is invalid.
            dmArray<double>** previous=(*owner)->edges.Get(key);
            if (previous) delete *previous;
            Put((*owner)->edges,key,line);
            line->SetCapacity((uint32_t)lua_objlen(L,-1));
            for (size_t i=1;i<=lua_objlen(L,-1);++i) line->Push(Element(L,lua_gettop(L),(int)i,valid));
            if (line->Size()>1) std::sort(line->Begin(),line->End());
        }
        lua_pop(L,1);
    }
    if (!valid) return luaL_error(L,"invalid edge registry");
    return 1;
}
static bool AppendInput(lua_State* L,Builder& b,size_t& count) {
    Shape s;Material m;double shade;
    return ReadShape(L,s,m,shade) && Append(b,s,m,shade,count);
}
static int Add(lua_State* L) {
    Builder* b=Check(L);luaL_argcheck(L,!b->finished,1,"builder already finished");size_t count=0;
    if (!AppendInput(L,*b,count)) return luaL_error(L,"invalid shape or primitive exceeds batch limit");
    lua_pushinteger(L,(lua_Integer)count);return 1;
}
static void SetNumber(lua_State* L,const char* key,double value) { lua_pushnumber(L,value);lua_setfield(L,-2,key); }
static void SetString(lua_State* L,const char* key,const std::string& value) { lua_pushlstring(L,value.data(),value.size());lua_setfield(L,-2,key); }
static int Finish(lua_State* L) {
    Builder* b=Check(L);b->finished=true;ClearEdges(b->edges);b->lookup.Clear();
    lua_createtable(L,(int)b->batches.Size(),0);
    for (size_t i=0;i<b->batches.Size();++i) {
        const Batch& batch=*b->batches[i];lua_createtable(L,0,9);
        SetString(L,"key",batch.key);SetString(L,"material",batch.material);
        SetNumber(L,"chunk_x",batch.chunk_x);SetNumber(L,"chunk_z",batch.chunk_z);
        SetNumber(L,"vertex_count",(double)batch.vertices.Size());SetNumber(L,"boxes",batch.boxes);
        SetNumber(L,"native_index",(double)i+1);
        lua_pushvalue(L,1);lua_setfield(L,-2,"native_builder");
        lua_createtable(L,6,0);for (int k=0;k<6;++k) { lua_pushnumber(L,batch.bounds[k]);lua_rawseti(L,-2,k+1); }
        lua_setfield(L,-2,"bounds");lua_rawseti(L,-2,(int)i+1);
    }
    return 1;
}
static dmBuffer::Result CreateBuffer(const dmArray<Vertex>& vertices,bool glass,const float* bounds,dmBuffer::HBuffer& data) {
    dmBuffer::StreamDeclaration declarations[6]={};int streams=glass?5:6;
    for (int k=0;k<streams;++k) { declarations[k].m_Name=dmHashString64(STREAMS[k]);declarations[k].m_Type=dmBuffer::VALUE_TYPE_FLOAT32;declarations[k].m_Count=COUNTS[k]; }
    dmBuffer::Result result=dmBuffer::Create(vertices.Size(),declarations,(uint8_t)streams,&data);
    if (result!=dmBuffer::RESULT_OK) return result;
    for (int k=0;k<streams;++k) {
        void* pointer=0;uint32_t count=0,components=0,stride=0;
        result=dmBuffer::GetStream(data,dmHashString64(STREAMS[k]),&pointer,&count,&components,&stride);
        if (result!=dmBuffer::RESULT_OK) break;
        float* dest=(float*)pointer;
        for (size_t i=0;i<vertices.Size();++i) std::memcpy(dest+i*stride,vertices[i].values+OFFSETS[k],COUNTS[k]*sizeof(float));
    }
    if (result==dmBuffer::RESULT_OK) result=dmBuffer::SetMetaData(data,dmHashString64("AABB"),bounds,6,dmBuffer::VALUE_TYPE_FLOAT32);
    if (result==dmBuffer::RESULT_OK) result=dmBuffer::UpdateContentVersion(data);
    if (result!=dmBuffer::RESULT_OK) { dmBuffer::Destroy(data);data=0; }
    return result;
}
static int Take(lua_State* L) {
    Builder* b=Check(L);int index=luaL_checkint(L,2);
    luaL_argcheck(L,b->finished,1,"finish builder before taking buffers");
    luaL_argcheck(L,index>=1 && (size_t)index<=b->batches.Size(),2,"invalid batch index");
    Batch& batch=*b->batches[index-1];luaL_argcheck(L,!batch.taken,2,"batch already taken");
    float bounds[6];for (int k=0;k<6;++k) bounds[k]=(float)batch.bounds[k];
    dmBuffer::HBuffer data=0;dmBuffer::Result result=CreateBuffer(batch.vertices,false,bounds,data);
    if (result!=dmBuffer::RESULT_OK) return luaL_error(L,"buffer creation failed: %d",(int)result);
    batch.taken=true;batch.vertices.SetSize(0);batch.vertices.SetCapacity(0);
    dmScript::PushBuffer(L,dmScript::LuaHBuffer(data,dmScript::OWNER_LUA));return 1;
}
// Small existing Lua batches (glass and capture fixtures) share the native
// upload path. Glass translation happens in double before float conversion.
static bool PackInput(lua_State* L,dmBuffer::HBuffer& data) {
    bool valid=true;double value=Number(L,1,"vertex_count",0,valid,true);
    if (!valid || value<1 || value>65536 || std::floor(value)!=value) return false;
    int count=(int)value;
    lua_getfield(L,1,"glass");bool glass=lua_toboolean(L,-1);lua_pop(L,1);
    Vec center={{0,0,0}};
    if (glass) {
        lua_getfield(L,1,"centre");if (!lua_istable(L,-1)) valid=false;
        else { int t=lua_gettop(L);center[0]=Number(L,t,"x",0,valid,true);center[1]=Number(L,t,"y",0,valid,true);center[2]=Number(L,t,"z",0,valid,true); }
        lua_pop(L,1);
    }
    dmArray<Vertex> vertices;vertices.SetCapacity(count);vertices.SetSize(count);
    for (int k=0;k<(glass?5:6);++k) {
        lua_getfield(L,1,ARRAYS[k]);
        if (!lua_istable(L,-1) || lua_objlen(L,-1)!=(size_t)count*COUNTS[k]) valid=false;
        else for (int i=0;i<count;++i) for (int j=0;j<COUNTS[k];++j) {
            double value=Element(L,lua_gettop(L),i*COUNTS[k]+j+1,valid);
            if (k==0 && glass) value=value-center[j];
            vertices[i].values[OFFSETS[k]+j]=(float)value;
        }
        lua_pop(L,1);
    }
    float bounds[6];lua_getfield(L,1,"bounds");
    if (!lua_istable(L,-1)) valid=false;
    else for (int k=0;k<6;++k) { double v=Element(L,lua_gettop(L),k+1,valid);if (glass) v=v-center[k%3];bounds[k]=(float)v; }
    lua_pop(L,1);
    return valid && CreateBuffer(vertices,glass,bounds,data)==dmBuffer::RESULT_OK;
}
static int Pack(lua_State* L) {
    luaL_checktype(L,1,LUA_TTABLE);dmBuffer::HBuffer data=0;
    if (!PackInput(L,data)) return luaL_error(L,"invalid batch or buffer allocation failed");
    dmScript::PushBuffer(L,dmScript::LuaHBuffer(data,dmScript::OWNER_LUA));return 1;
}
static bool VerifyInput(lua_State* L,const Builder& b,char* error,size_t capacity) {
    Shape s;Material m;double shade;
    if (!ReadShape(L,s,m,shade) || !lua_istable(L,6)) { std::snprintf(error,capacity,"invalid verification inputs");return false; }
    Geometry g;Generate(g,s,m,shade,b.edges);bool valid=true;
    double expected_count=Number(L,6,"vertex_count",0,valid,true);
    if (!valid || expected_count!=g.vertices.Size()) { std::snprintf(error,capacity,"%s vertex count: native %u, Lua %.0f",s.id.c_str(),(unsigned)g.vertices.Size(),expected_count);return false; }
    for (int k=0;k<5;++k) {
        lua_getfield(L,6,ARRAYS[k]);if (!lua_istable(L,-1)) { lua_pop(L,1);return false; }
        for (size_t i=0;i<g.vertices.Size();++i) for (int j=0;j<COUNTS[k];++j) {
            float expected=(float)Element(L,lua_gettop(L),(int)i*COUNTS[k]+j+1,valid);
            float actual=g.vertices[i].values[OFFSETS[k]+j];
            if (!valid || std::memcmp(&expected,&actual,sizeof(float))) {
                std::snprintf(error,capacity,"%s %s[%u]: native %.9g, Lua %.9g",s.id.c_str(),ARRAYS[k],(unsigned)(i*COUNTS[k]+j+1),actual,expected);lua_pop(L,1);return false;
            }
        }
        lua_pop(L,1);
    }
    // Empty shapes have infinite bounds; their bounds never reach a batch.
    if (!g.vertices.Empty()) {
        lua_getfield(L,6,"bounds");if (!lua_istable(L,-1)) { lua_pop(L,1);return false; }
        for (int k=0;k<6;++k) if (g.bounds[k]!=Element(L,lua_gettop(L),k+1,valid)) {
            std::snprintf(error,capacity,"%s bounds[%d] differ",s.id.c_str(),k+1);lua_pop(L,1);return false;
        }
        lua_pop(L,1);
    }
    return valid;
}
static int Verify(lua_State* L) {
    Builder* b=Check(L);char error[512]="invalid reference mesh";
    if (!VerifyInput(L,*b,error,sizeof(error))) return luaL_error(L,"geometry mismatch: %s",error);
    lua_pushboolean(L,1);return 1;
}
static int Clock(lua_State* L) { lua_pushnumber(L,dmTime::GetMonotonicTime()/1000000.0);return 1; }
static const luaL_reg METHODS[]={{"begin",Begin},{"append",Add},{"finish",Finish},{"take_buffer",Take},{"pack",Pack},{"verify",Verify},{"close",Close},{"clock",Clock},{0,0}};
static dmExtension::Result Initialize(dmExtension::Params* params) {
    lua_State* L=params->m_L;int top=lua_gettop(L);
    luaL_newmetatable(L,META);lua_pushcfunction(L,Close);lua_setfield(L,-2,"__gc");lua_pop(L,1);
    luaL_register(L,"worldmesh",METHODS);lua_pop(L,1);assert(lua_gettop(L)==top);
    return dmExtension::RESULT_OK;
}
}
DM_DECLARE_EXTENSION(WorldMesh,"WorldMesh",0,0,Initialize,0,0,0)
