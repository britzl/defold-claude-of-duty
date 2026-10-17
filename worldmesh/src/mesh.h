#ifndef WORLD_MESH_H
#define WORLD_MESH_H

#include <dmsdk/dlib/array.h>
#include <dmsdk/dlib/hashtable.h>
#include <string>

namespace worldmesh {
// Fixed-size values stay inline and retain double precision. Dynamic storage
// uses dmArray; its elements must have memcpy semantics.
struct Vec {
    double values[3];
    double& operator[](uint32_t i) { return values[i]; }
    const double& operator[](uint32_t i) const { return values[i]; }
};
struct Rect {
    double values[4];
    double& operator[](uint32_t i) { return values[i]; }
    const double& operator[](uint32_t i) const { return values[i]; }
};
struct ProfilePoint {
    double values[2];
    double& operator[](uint32_t i) { return values[i]; }
    const double& operator[](uint32_t i) const { return values[i]; }
};
template <typename T> inline void Push(dmArray<T>& array,const T& value) {
    if (array.Full()) array.SetCapacity(array.Capacity()?array.Capacity()*2:16);
    array.Push(value);
}
template <typename T> inline void Put(dmHashTable64<T>& table,uint64_t key,const T& value) {
    if (table.Full()) {
        uint32_t capacity=table.Capacity()?table.Capacity()*2:16;
        table.SetCapacity(capacity*2/3,capacity);
    }
    table.Put(key,value);
}
typedef dmHashTable64<dmArray<double>*> Edges;
void ClearEdges(Edges& edges);
struct Shape {
    std::string id, kind, material;
    Vec center, size, rotation;
    Rect masks;
    dmArray<ProfilePoint> profile;
    double bevel, taper;
    bool clipped;
    dmArray<Rect> faces[6];
};
struct Material { Vec color; double coverage, kind, weather; };
// Retain Lua's double arithmetic until the final stream conversion. No fast
// math or fused multiply-add: stream bytes are a compatibility contract.
struct Vertex { float values[20]; };
struct Geometry {
    dmArray<Vertex> vertices;
    double bounds[6];
    Geometry();
};
struct Batch : Geometry {
    std::string key, material;
    int chunk_x, chunk_z, boxes;
    bool taken;
    Batch() : chunk_x(0), chunk_z(0), boxes(0), taken(false) {}
};
struct Builder {
    Edges edges;
    // Containers hold pointers to owning objects, never raw copies of their
    // dmArrays or strings. Builder destroys both batches and edge lines.
    dmArray<Batch*> batches;
    dmHashTable64<uint32_t> lookup;
    double chunk_size;
    size_t max_vertices;
    bool finished;
    Builder(double chunk, size_t limit) : chunk_size(chunk), max_vertices(limit), finished(false) {}
    ~Builder();
};
void Generate(Geometry& out, const Shape& shape, const Material& material, double shade, const Edges& edges);
bool Append(Builder& builder, const Shape& shape, const Material& material, double shade, size_t& vertices);
}
#endif
