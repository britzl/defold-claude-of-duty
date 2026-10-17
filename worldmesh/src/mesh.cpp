#include "mesh.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>

namespace worldmesh {
static const double PI = 3.14159265358979323846;
static const double EPSILON = 1e-7;
static void DeleteEdgeLine(void*,const uint64_t*,dmArray<double>** line) { delete *line; }
void ClearEdges(Edges& edges) {
    edges.Iterate(DeleteEdgeLine,(void*)0);
    Edges empty;edges.Swap(empty);
}
Builder::~Builder() {
    ClearEdges(edges);
    for (uint32_t i=0;i<batches.Size();++i) delete batches[i];
}
Geometry::Geometry() {
    for (int k=0;k<3;++k) { bounds[k]=std::numeric_limits<double>::infinity(); bounds[k+3]=-bounds[k]; }
}
struct Rotation {
    double c[3], s[3]; bool active, inverse;
    Rotation(const Vec& angles, bool inv=false) : inverse(inv) {
        active=angles[0]!=0 || angles[1]!=0 || angles[2]!=0;
        for (int k=0;k<3;++k) { double a=angles[k]*(inv?-1:1); c[k]=std::cos(a); s[k]=std::sin(a); }
    }
    Vec apply(Vec p) const {
        if (!active) return p;
        for (int i=0;i<3;++i) {
            int k=inverse?2-i:i;
            double a,b;
            if (k==0) { a=p[1]*c[k]-p[2]*s[k]; b=p[1]*s[k]+p[2]*c[k]; p[1]=a;p[2]=b; }
            else if (k==1) { a=p[0]*c[k]+p[2]*s[k]; b=-p[0]*s[k]+p[2]*c[k]; p[0]=a;p[2]=b; }
            else { a=p[0]*c[k]-p[1]*s[k]; b=p[0]*s[k]+p[1]*c[k]; p[0]=a;p[1]=b; }
        }
        return p;
    }
};
static Vec Sub(const Vec& a,const Vec& b) { return Vec{{a[0]-b[0],a[1]-b[1],a[2]-b[2]}}; }
static void Emit(Geometry& out,const Vec& p,const Vec& n,const Vec& color,double alpha,
                 const Rect& edges,const Rect& masks,const Material& material) {
    Vertex v;
    for (int k=0;k<3;++k) {
        v.values[k]=(float)p[k]; v.values[3+k]=(float)n[k]; v.values[6+k]=(float)color[k];
        out.bounds[k]=std::min(out.bounds[k],p[k]); out.bounds[k+3]=std::max(out.bounds[k+3],p[k]);
    }
    v.values[9]=(float)alpha;
    for (int k=0;k<4;++k) { v.values[10+k]=(float)edges[k]; v.values[14+k]=(float)masks[k]; }
    v.values[18]=(float)material.kind; v.values[19]=(float)material.weather;
    Push(out.vertices,v);
}
static void EdgeVertices(dmArray<Vec>& boundary,const Edges& registry,const Vec& a,const Vec& b) {
    int axis=a[0]!=b[0]?0:a[1]!=b[1]?1:2;
    int u=(axis+1)%3,v=(axis+2)%3;
    char key[128]; std::snprintf(key,sizeof(key),"%d/%.7f/%.7f",axis+1,a[u],a[v]);
    dmArray<double>* const* found=registry.Get(dmHashString64(key));
    if (!found || (*found)->Empty()) return;
    const dmArray<double>& line=**found;
    double lo=std::min(a[axis],b[axis]),hi=std::max(a[axis],b[axis]);
    double last=-std::numeric_limits<double>::infinity();
    size_t start=boundary.Size();
    for (const double* it=std::upper_bound(line.Begin(),line.End(),lo+EPSILON);it!=line.End();++it) {
        double value=*it;
        if (value>=hi-EPSILON) break;
        if (value>last+EPSILON) { Vec p=a;p[axis]=value;Push(boundary,p);last=value; }
    }
    if (a[axis]>b[axis]) std::reverse(boundary.Begin()+start,boundary.End());
}
static const Vec NORMALS[6]={{{1,0,0}},{{-1,0,0}},{{0,1,0}},{{0,-1,0}},{{0,0,1}},{{0,0,-1}}};
static const int CORNERS[6][4][3]={
    {{1,-1,-1},{1,1,-1},{1,1,1},{1,-1,1}},
    {{-1,-1,1},{-1,1,1},{-1,1,-1},{-1,-1,-1}},
    {{-1,1,-1},{-1,1,1},{1,1,1},{1,1,-1}},
    {{-1,-1,1},{-1,-1,-1},{1,-1,-1},{1,-1,1}},
    {{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}},
    {{1,-1,-1},{-1,-1,-1},{-1,1,-1},{1,1,-1}}};
static void Box(Geometry& out,const Shape& s,const Material& m,double shade,const Edges* edge_points) {
    Rotation forward(s.rotation),inverse(s.rotation,true);
    Vec half={{s.size[0]/2,s.size[1]/2,s.size[2]/2}};
    Vec color={{m.color[0]*shade,m.color[1]*shade,m.color[2]*shade}};
    bool ground=s.id.compare(0,5,"road/")==0 || s.id.compare(0,5,"walk/")==0 || s.id.compare(0,7,"ground/")==0;
    const int pairs[6][2]={{1,2},{1,2},{0,2},{0,2},{0,1},{0,1}};
    const int indices[6]={0,1,2,0,2,3};
    for (int face=0;face<6;++face) {
        int u=pairs[face][0],v=pairs[face][1],horizontal=u,vertical=v;
        if (u==1) { horizontal=v;vertical=u; }
        Vec normal=forward.apply(NORMALS[face]);
        dmArray<Rect> fallback;
        if (!s.clipped) Push(fallback,Rect{{s.center[u]-half[u],s.center[v]-half[v],s.center[u]+half[u],s.center[v]+half[v]}});
        const dmArray<Rect>& rectangles=s.clipped?s.faces[face]:fallback;
        for (size_t ri=0;ri<rectangles.Size();++ri) {
            const Rect& r=rectangles[ri]; Vec corners[4];
            for (int i=0;i<4;++i) {
                Vec p={{CORNERS[face][i][0]*half[0],CORNERS[face][i][1]*half[1],CORNERS[face][i][2]*half[2]}};
                p[u]=r[CORNERS[face][i][u]<0?0:2]-s.center[u];
                p[v]=r[CORNERS[face][i][v]<0?1:3]-s.center[v];
                p=forward.apply(p);
                for (int k=0;k<3;++k) corners[i][k]=s.center[k]+p[k];
            }
            dmArray<Vec> boundary,triangles;
            for (int i=0;i<4;++i) {
                Push(boundary,corners[i]);
                if (edge_points) EdgeVertices(boundary,*edge_points,corners[i],corners[(i+1)%4]);
            }
            if (boundary.Size()==4) for (int i=0;i<6;++i) Push(triangles,corners[indices[i]]);
            else {
                Vec middle;for (int k=0;k<3;++k) middle[k]=(corners[0][k]+corners[2][k])*.5;
                for (size_t i=0;i<boundary.Size();++i) {
                    Push(triangles,middle);Push(triangles,boundary[i]);Push(triangles,boundary[(i+1)%boundary.Size()]);
                }
            }
            double top=u==1?r[2]:v==1?r[3]:s.center[1]+half[1];
            Rect masks={{ground?0:s.masks[0],ground?0:s.masks[1],ground?0:s.masks[2],ground?0:s.masks[3]>0?top:-1000}};
            for (size_t i=0;i<triangles.Size();++i) {
                const Vec& vertex=triangles[i];Vec local=inverse.apply(Sub(vertex,s.center));
                Rect edges={{local[horizontal]+half[horizontal],half[horizontal]-local[horizontal],
                    local[vertical]+half[vertical],half[vertical]-local[vertical]}};
                Emit(out,vertex,normal,color,m.coverage,edges,masks,m);
            }
        }
    }
}
struct Primitive {
    Geometry& out;const Shape& s;const Material& m;double shade;Rotation forward;
    Primitive(Geometry& o,const Shape& shape,const Material& material,double sh) : out(o),s(shape),m(material),shade(sh),forward(s.rotation) {}
    void triangle(const Vec& a,const Vec& b,const Vec& c,bool back=false) {
        Vec u=Sub(b,a),v=Sub(c,a);
        Vec n={{u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]}};
        double length=std::sqrt(n[0]*n[0]+n[1]*n[1]+n[2]*n[2]);
        if (length<1e-10) return;
        for (int k=0;k<3;++k) n[k]=n[k]/length;
        n=forward.apply(n);
        const Vec points[3]={a,b,c};Vec color={{m.color[0]*shade,m.color[1]*shade,m.color[2]*shade}};
        for (int i=0;i<3;++i) {
            Vec p=forward.apply(points[i]);for (int k=0;k<3;++k) p[k]=p[k]+s.center[k];
            Emit(out,p,n,color,s.kind=="frond"?1:m.coverage,Rect{{1,1,1,1}},Rect{{0,0,0,-1000}},m);
        }
        if (back) triangle(c,b,a);
    }
    void quad(const Vec& a,const Vec& b,const Vec& c,const Vec& d,bool back=false) { triangle(a,b,c,back);triangle(a,c,d,back); }
    Vec torus(double a,double b) {
        double radius=.72+.28*std::cos(b);
        return Vec{{s.size[0]/2*radius*std::cos(a),s.size[1]/2*std::sin(b),s.size[2]/2*radius*std::sin(a)}};
    }
    void build() {
        double w=s.size[0]/2,h=s.size[1]/2,d=s.size[2]/2;
        if (s.kind=="prism") {
            const dmArray<ProfilePoint>& p=s.profile;
            for (size_t i=1;i+1<p.Size();++i) {
                triangle(Vec{{p[0][0],p[0][1],d}},Vec{{p[i][0],p[i][1],d}},Vec{{p[i+1][0],p[i+1][1],d}});
                triangle(Vec{{p[0][0],p[0][1],-d}},Vec{{p[i+1][0],p[i+1][1],-d}},Vec{{p[i][0],p[i][1],-d}});
            }
            for (size_t i=0;i<p.Size();++i) {
                const ProfilePoint& a=p[i];const ProfilePoint& b=p[(i+1)%p.Size()];
                quad(Vec{{a[0],a[1],-d}},Vec{{b[0],b[1],-d}},Vec{{b[0],b[1],d}},Vec{{a[0],a[1],d}});
            }
        } else if (s.kind=="torus") {
            for (int i=0;i<12;++i) for (int j=0;j<6;++j) {
                double a=i*PI/6,b=j*PI/3;
                quad(torus(a,b),torus(a,b+PI/3),torus(a+PI/6,b+PI/3),torus(a+PI/6,b));
            }
        } else if (s.kind=="frond") {
            for (int i=0;i<12;++i) {
                double a=i/12.0,b=(i+1)/12.0;
                double ya=h*(1-2*a*a),za=-d+2*d*a,yb=h*(1-2*b*b),zb=-d+2*d*b,r=w*.04;
                quad(Vec{{-r,ya,za}},Vec{{-r,yb,zb}},Vec{{r,yb,zb}},Vec{{r,ya,za}},true);
            }
            for (int i=1;i<=12;++i) {
                double t=(i-.5)/12,y=h*(1-2*t*t),z=-d+2*d*t,length=w*(.25+.75*std::sin(PI*t));
                for (int side=-1;side<=1;side+=2)
                    quad(Vec{{0,y,z}},Vec{{side*length*.55,y-.025,z-.055}},Vec{{side*length,y-h*.17,z+d*.16}},Vec{{side*length*.4,y-.04,z+.075}},true);
            }
        } else {
            dmArray<Vec> rings[4];
            uint32_t ring_count=s.kind=="bevel"?4:2;
            if (s.kind=="bevel") {
                double r=std::min(std::min(s.bevel,w*.45),std::min(h*.45,d*.45));
                double spec[4][2]={{-h,r},{-h+r,0},{h-r,0},{h,r}};
                for (int j=0;j<4;++j) {
                    double x=w-spec[j][1],z=d-spec[j][1],y=spec[j][0];
                    Vec points[8]={{{-x+r,y,-z}},{{x-r,y,-z}},{{x,y,-z+r}},{{x,y,z-r}},{{x-r,y,z}},{{-x+r,y,z}},{{-x,y,z-r}},{{-x,y,-z+r}}};
                    rings[j].SetCapacity(8);rings[j].PushArray(points,8);
                    std::reverse(rings[j].Begin(),rings[j].End());
                }
            } else {
                for (int j=0;j<2;++j) {
                    double y=j==0?-h:h,taper=y==h?s.taper:1;
                    rings[j].SetCapacity(12);
                    for (int i=0;i<12;++i) { double a=-(double)i*PI/6;rings[j].Push(Vec{{w*std::cos(a)*taper,y,d*std::sin(a)*taper}}); }
                }
            }
            for (size_t j=0;j+1<ring_count;++j) for (size_t i=0;i<rings[j].Size();++i) {
                size_t next=(i+1)%rings[j].Size();quad(rings[j][i],rings[j][next],rings[j+1][next],rings[j+1][i]);
            }
            for (size_t i=1;i+1<rings[0].Size();++i) {
                triangle(rings[0][0],rings[0][i+1],rings[0][i]);
                const dmArray<Vec>& r=rings[ring_count-1];triangle(r[0],r[i],r[i+1]);
            }
        }
    }
};
void Generate(Geometry& out,const Shape& s,const Material& m,double shade,const Edges& edges) {
    if (s.kind=="card") {
        // Copy only the box attributes; owning dmArrays cannot be copied.
        Shape card;card.id=s.id;card.center=s.center;card.size=s.size;
        card.rotation=s.rotation;card.masks=s.masks;card.size[2]=0;card.clipped=true;
        Rect face={{s.center[0]-s.size[0]/2,s.center[1]-s.size[1]/2,s.center[0]+s.size[0]/2,s.center[1]+s.size[1]/2}};
        Push(card.faces[4],face);Push(card.faces[5],face);Box(out,card,m,shade,0);
    } else if (s.kind.empty()) Box(out,s,m,shade,s.clipped?&edges:0);
    else Primitive(out,s,m,shade).build();
}
bool Append(Builder& b,const Shape& s,const Material& m,double shade,size_t& vertices) {
    Geometry geometry;Generate(geometry,s,m,shade,b.edges);vertices=geometry.vertices.Size();
    if (vertices>b.max_vertices) return false;
    if (vertices==0) return true;
    bool terrain=s.id.compare(0,8,"terrain/")==0;
    double chunk=b.chunk_size*(terrain?4:1);
    int cx=(int)std::floor(s.center[0]/chunk),cz=(int)std::floor(s.center[2]/chunk);
    char key[96];std::snprintf(key,sizeof(key),"%s/%d/%d",terrain?"terrain":"world",cx,cz);
    uint64_t hash=dmHashString64(key);
    const uint32_t* found=b.lookup.Get(hash);
    uint32_t index=found?*found:b.batches.Size();
    if (index==b.batches.Size() || b.batches[index]->vertices.Size()+vertices>b.max_vertices) {
        Batch* batch=new Batch;batch->material=s.material;batch->chunk_x=cx;batch->chunk_z=cz;
        char full_key[128];std::snprintf(full_key,sizeof(full_key),"%s/%u",key,(unsigned)b.batches.Size()+1);batch->key=full_key;
        index=b.batches.Size();Push(b.batches,batch);Put(b.lookup,hash,index);
        batch->vertices.SetCapacity((uint32_t)b.max_vertices);
    }
    Batch& batch=*b.batches[index];batch.vertices.PushArray(geometry.vertices.Begin(),geometry.vertices.Size());
    for (int k=0;k<3;++k) { batch.bounds[k]=std::min(batch.bounds[k],geometry.bounds[k]);batch.bounds[k+3]=std::max(batch.bounds[k+3],geometry.bounds[k+3]); }
    ++batch.boxes;return true;
}
}
