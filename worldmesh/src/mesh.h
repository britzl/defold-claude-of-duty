#ifndef WORLD_MESH_H
#define WORLD_MESH_H

#include <array>
#include <map>
#include <string>
#include <vector>

namespace worldmesh {
typedef std::array<double, 3> Vec;
typedef std::array<double, 4> Rect;
typedef std::map<std::string, std::vector<double> > Edges;
struct Shape {
    std::string id, kind, material;
    Vec center, size, rotation;
    std::array<double, 4> masks;
    std::vector<std::array<double, 2> > profile;
    double bevel, taper;
    bool clipped;
    std::array<std::vector<Rect>, 6> faces;
};
struct Material { Vec color; double coverage, kind, weather; };
// Retain Lua's double arithmetic until the final stream conversion. No fast
// math or fused multiply-add: stream bytes are a compatibility contract.
struct Vertex { float values[20]; };
struct Geometry {
    std::vector<Vertex> vertices;
    std::array<double, 6> bounds;
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
    std::vector<Batch> batches;
    std::map<std::string, size_t> lookup;
    double chunk_size;
    size_t max_vertices;
    bool finished;
    Builder(double chunk, size_t limit) : chunk_size(chunk), max_vertices(limit), finished(false) {}
};
void Generate(Geometry& out, const Shape& shape, const Material& material, double shade, const Edges& edges);
bool Append(Builder& builder, const Shape& shape, const Material& material, double shade, size_t& vertices);
}
#endif
