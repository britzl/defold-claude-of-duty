// Double-precision port of game/ai/rig.lua, transform.lua and ik.lua. Preserve
// operation order and disable FP contraction; Lua remains the parity oracle.
#include "pose.h"
#include <algorithm>
#include <cmath>

namespace soldier_pose {
namespace {
const double Pi=3.14159265358979323846;
double Clamp(double x,double lo,double hi) { return std::max(lo,std::min(hi,x)); }
double Lerp(double a,double b,double t) { return a+(b-a)*t; }
double Smooth(double t) { t=Clamp(t,0,1);return t*t*t*(t*(t*6-15)+10); }
Vec Sub(Vec a,Vec b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
Vec Point(Vec p,Vec d,double t) { return {p.x+d.x*t,p.y+d.y*t,p.z+d.z*t}; }
double Dot(Vec a,Vec b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
double Length(Vec a) { return std::sqrt(Dot(a,a)); }
Vec Unit(Vec a) { double n=Length(a);return {a.x/n,a.y/n,a.z/n}; }
Vec Cross(Vec a,Vec b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
Vec Origin(const Mat& a) { return {a.m[3],a.m[7],a.m[11]}; }
Mat Identity(Vec p={0,0,0}) { return {{1,0,0,p.x,0,1,0,p.y,0,0,1,p.z}}; }
Mat Rotation(double x,double y,double z) {
    double a=std::cos(x),b=std::sin(x),c=std::cos(y),d=std::sin(y),e=std::cos(z),f=std::sin(z);
    return {{c*e+d*b*f,-c*f+d*b*e,d*a,0,a*f,a*e,-b,0,-d*e+c*b*f,d*f+c*b*e,c*a,0}};
}
Mat Mul(const Mat& aa,const Mat& bb) {
    const double* a=aa.m;const double* b=bb.m;Mat out;
    for(int r=0;r<3;++r) {
        int i=r*4;
        for(int c=0;c<3;++c) out.m[i+c]=a[i]*b[c]+a[i+1]*b[4+c]+a[i+2]*b[8+c];
        out.m[i+3]=a[i]*b[3]+a[i+1]*b[7]+a[i+2]*b[11]+a[i+3];
    }
    return out;
}
Mat Inverse(const Mat& a) {
    const double* m=a.m;
    return {{m[0],m[4],m[8],-(m[0]*m[3]+m[4]*m[7]+m[8]*m[11]),
        m[1],m[5],m[9],-(m[1]*m[3]+m[5]*m[7]+m[9]*m[11]),
        m[2],m[6],m[10],-(m[2]*m[3]+m[6]*m[7]+m[10]*m[11])}};
}
Vec Transform(const Mat& a,Vec p) {
    const double* m=a.m;
    return {m[0]*p.x+m[1]*p.y+m[2]*p.z+m[3],m[4]*p.x+m[5]*p.y+m[6]*p.z+m[7],m[8]*p.x+m[9]*p.y+m[10]*p.z+m[11]};
}
Mat Between(Vec a,Vec b) {
    double na=Length(a),nb=Length(b);
    if(na<1e-9 || nb<1e-9) return Identity();
    a={a.x/na,a.y/na,a.z/na};b={b.x/nb,b.y/nb,b.z/nb};
    double c=Clamp(Dot(a,b),-1,1);
    if(c>1-1e-12) return Identity();
    Vec axis=Cross(a,b);
    if(c<-1+1e-9) axis=Cross(a,std::abs(a.y)<.9?Vec{0,1,0}:Vec{1,0,0});
    axis=Unit(axis);double x=axis.x,y=axis.y,z=axis.z;
    double s=std::sqrt(std::max(0.0,1-c*c)),d=1-c;
    return {{c+x*x*d,x*y*d-z*s,x*z*d+y*s,0,y*x*d+z*s,c+y*y*d,y*z*d-x*s,0,z*x*d-y*s,z*y*d+x*s,c+z*z*d,0}};
}
void Rotate(Pose& pose,const Rig& rig,int index,const Mat& rotation) {
    Vec pivot=Origin(pose.worlds[index]);const double* r=rotation.m;
    Vec delta={r[0]*(-pivot.x)+r[1]*(-pivot.y)+r[2]*(-pivot.z)+(r[3]+pivot.x),
        r[4]*(-pivot.x)+r[5]*(-pivot.y)+r[6]*(-pivot.z)+(r[7]+pivot.y),
        r[8]*(-pivot.x)+r[9]*(-pivot.y)+r[10]*(-pivot.z)+(r[11]+pivot.z)};
    bool affected[BoneCount]={};affected[index]=true;
    for(int i=index;i<BoneCount;++i) {
        int parent=rig.bones[i].parent;
        if(i!=index && (parent<0 || !affected[parent])) continue;
        affected[i]=true;
        Mat out=Mul(rotation,pose.worlds[i]);
        // Lua's specialized product folds the pivot into the translation before
        // applying it. Match that order (rotation translations are always zero).
        const double* m=pose.worlds[i].m;
        out.m[3]=r[0]*m[3]+r[1]*m[7]+r[2]*m[11]+delta.x;
        out.m[7]=r[4]*m[3]+r[5]*m[7]+r[6]*m[11]+delta.y;
        out.m[11]=r[8]*m[3]+r[9]*m[7]+r[10]*m[11]+delta.z;
        pose.worlds[i]=out;
    }
}
void Orient(Pose& pose,const Rig& rig,int index,const Mat& frame) {
    Mat inverse=Inverse(pose.worlds[index]);inverse.m[3]=inverse.m[7]=inverse.m[11]=0;
    Mat rotation=Mul(frame,inverse);rotation.m[3]=rotation.m[7]=rotation.m[11]=0;
    Rotate(pose,rig,index,rotation);
}
void Solve(Pose& pose,const Rig& rig,int upper,int lower,int last,Vec target,Vec pole) {
    Vec a=Origin(pose.worlds[upper]),b=Origin(pose.worlds[lower]),c=Origin(pose.worlds[last]);
    double l1=Length(Sub(b,a)),l2=Length(Sub(c,b));
    Vec delta=Sub(target,a);double distance=Length(delta);
    Vec axis=distance>1e-8?Point({0,0,0},delta,1/distance):Unit(Sub(c,a));
    if(Length(axis)<.5) axis={0,-1,0};
    double d=Clamp(distance,std::abs(l1-l2)+1e-6,l1+l2-1e-6);
    double along=(l1*l1-l2*l2+d*d)/(2*d);
    Vec perp=Point(pole,axis,-Dot(pole,axis));
    if(Length(perp)<1e-8) {
        Vec fallback=std::abs(axis.y)<.9?Vec{0,1,0}:Vec{1,0,0};
        perp=Point(fallback,axis,-Dot(fallback,axis));
    }
    perp=Unit(perp);
    Vec bend=Point(Point(a,axis,along),perp,std::sqrt(std::max(0.0,l1*l1-along*along)));
    Vec endpoint=Point(a,axis,d);
    Rotate(pose,rig,upper,Between(Sub(b,a),Sub(bend,a)));
    b=Origin(pose.worlds[lower]);c=Origin(pose.worlds[last]);
    Rotate(pose,rig,lower,Between(Sub(c,b),Sub(endpoint,b)));
}
void Add(Vec* angles,int i,double x=0,double y=0,double z=0) {
    angles[i].x+=x;angles[i].y+=y;angles[i].z+=z;
}
Vec Blend(Vec a,Vec b,double w) { return {Lerp(a.x,b.x,w),Lerp(a.y,b.y,w),Lerp(a.z,b.z,w)}; }
}

void Evaluate(const Rig& rig,const State& s,Pose& out) {
    Vec angles[BoneCount]={};
    double death=Smooth(s.death),live=1-death;
    double crouch=Clamp(s.crouch,0,1)*live,walk=Clamp(s.walk,0,1)*live;
    double run=Clamp(s.run,0,1)*walk*(1-crouch),phase=s.phase,aim=Clamp(s.aim,0,1)*live;
    double hurt=Clamp(s.wounded,0,1)*live,breathe=std::sin(s.time*2.1)*.008*live;
    double turn=std::sin(Pi*Clamp(s.turn,0,1))*s.turn_weight*live;
    int turn_side=s.turn_direction>=0?0:1;
    double vault=std::sin(Pi*Clamp(s.vault,0,1))*s.vault_weight*live;
    double reload=std::min(1.0,std::min(s.reload*6,(1-s.reload)*6))*s.reload_weight*live;
    double pitch=Clamp(s.pitch,-.6,.6)*aim,yaw=Clamp(s.aim_yaw,-.75,.75)*aim,recoil=s.recoil*live;
    Add(angles,Hips,-.85*crouch-.10*walk-.12*run-.12*hurt-.32*vault,turn*.08,.025*std::sin(phase)*walk+.04*hurt);
    Add(angles,Spine,breathe+.32*crouch-.12*hurt-.20*vault,0,-.03*hurt);
    Add(angles,Spine1,.22*crouch+pitch*.4+.05*aim-.09*hurt-.12*vault,yaw*.4-reload*.10,0);
    Add(angles,Spine2,.30*crouch+pitch*.6+.05*aim+recoil*.055-.05*hurt-.10*vault,yaw*.6-reload*.28,-reload*.05);
    Add(angles,Head,-.07*aim+.12*crouch-pitch*.25,std::sin(s.time*.7)*.07*(1-aim)+yaw*.15,0);
    Add(angles,Neck,-.07*hurt);Add(angles,ClavicleR,.12*crouch);Add(angles,ClavicleL,.12*crouch);
    const int hips[]={UpLegR,UpLegL},knees[]={LegR,LegL},ankles[]={FootR,FootL};
    for(int side=0;side<2;++side) {
        double swing=std::sin(phase+(side==0?0:Pi)),stride=walk*(1-crouch*.55);
        Add(angles,hips[side],swing*(.42+.30*run)*stride-.8*vault);
        Add(angles,knees[side],-std::max(0.0,swing)*(.65+.65*run)*stride-1.0*vault);
        Add(angles,ankles[side],-swing*.13*stride+.35*vault);
        if(side==turn_side) {Add(angles,hips[side],-.18*turn);Add(angles,knees[side],-.5*turn);}
    }
    double hit=s.hit*live,side=s.hit_side;
    if(hit>0) {
        if(s.hit_region==1) {Add(angles,Head,-.35*hit,side*.24*hit,side*.14*hit);Add(angles,Neck,-.22*hit);}
        else if(s.hit_region==2) {Add(angles,side>0?ClavicleR:ClavicleL,-.24*hit,side*.1*hit,side*.18*hit);Add(angles,Spine2,-.09*hit,side*.10*hit);}
        else if(s.hit_region==3) {Add(angles,Hips,-.14*hit,0,-side*.10*hit);Add(angles,side>0?UpLegR:UpLegL,-.24*hit,0,side*.1*hit);}
        else {Add(angles,Spine,-.10*hit,side*.05*hit,side*.03*hit);Add(angles,Spine1,-.16*hit,side*.08*hit,side*.05*hit);Add(angles,Spine2,-.19*hit,side*.10*hit,side*.07*hit);}
    }
    for(int i=0;i<BoneCount;++i) {
        const Bone& b=rig.bones[i];Vec a=angles[i];Mat m=Rotation(a.x,a.y,a.z);
        m.m[3]=b.local.x;m.m[7]=b.local.y;m.m[11]=b.local.z;
        if(i==Hips) {
            m=Mul(Rotation(death*Pi*.49,0,death*.10),m);
            m.m[7]=.98-.77*death-.70*crouch-.10*hurt+breathe*.3+std::abs(std::sin(phase))*.025*walk+s.pelvis*live+.10*vault;
            m.m[11]=.005+.38*death+.12*crouch+.03*hurt;
        }
        out.worlds[i]=b.parent>=0?Mul(out.worlds[b.parent],m):m;
    }
    double drop=0;
    if(live>0 && vault<.001) {
        for(int side=0;side<2;++side) {
            const Foot& foot=s.feet[side];if(!foot.present || foot.weight<=0) continue;
            Vec hip=Origin(out.worlds[hips[side]]),knee=Origin(out.worlds[knees[side]]),ankle=Origin(out.worlds[ankles[side]]),p=foot.target;
            double reach=Length(Sub(hip,knee))+Length(Sub(knee,ankle))-.003;
            double vertical=std::sqrt(std::max(.01,reach*reach-(hip.x-p.x)*(hip.x-p.x)-(hip.z-p.z)*(hip.z-p.z)));
            drop=std::min(drop,(p.y+vertical-hip.y)*foot.weight*live);
        }
        drop=std::max(-.32,drop);
        for(int i=0;i<BoneCount;++i) out.worlds[i].m[7]+=drop;
    }
    out.reach_drop=drop;
    for(int side=0;side<2;++side) {
        const Foot& foot=s.feet[side];
        if(!(live>0 && vault<.001 && ((foot.present && foot.weight>1e-6) || (!foot.present && (crouch>0 || hurt>0))))) continue;
        Vec at=Origin(out.worlds[ankles[side]]),target=foot.present?foot.target:Vec{side==0?.103:-.103,.088,.022};
        target=Blend(at,target,(foot.present?foot.weight:1)*live);
        Solve(out,rig,hips[side],knees[side],ankles[side],target,{side==0?.10:-.10,.05,-1});
        Vec normal=foot.present?foot.normal:Vec{0,1,0};double ny=std::max(std::cos(.35),normal.y);
        double horizontal=std::sqrt(normal.x*normal.x+normal.z*normal.z),limit=std::sqrt(std::max(0.0,1-ny*ny));
        double k=horizontal>1e-7?std::min(1.0,limit/horizontal):0;
        Orient(out,rig,ankles[side],Between({0,1,0},Unit({normal.x*k,ny,normal.z*k})));
    }
    Vec bind=rig.bones[Spine2].bind,pivot=rig.grip;
    Mat gun=Mul(out.worlds[Spine2],Identity({-bind.x,-bind.y,-bind.z}));
    Mat layer=Mul(Identity(pivot),Rotation(-.24*run+.08*reload,.10*reload,-.10*run-.20*reload));
    layer=Mul(layer,Identity({-pivot.x,-pivot.y,-pivot.z}));gun=Mul(gun,layer);
    Solve(out,rig,UpperArmR,ForearmR,HandR,Transform(gun,pivot),{.35,-1,.45});
    Orient(out,rig,HandR,gun);
    gun=Mul(out.worlds[HandR],Identity({-pivot.x,-pivot.y,-pivot.z}));
    Vec support=Transform(gun,rig.variants[s.variant].support);
    if(reload>0) {
        Vec mag=Transform(gun,rig.magazine),pouch=Transform(out.worlds[Spine2],{.02,-.155,-.164});
        double t=s.reload,w;Vec a,b;
        if(t<.18) {a=support;b=mag;w=t/.18;}
        else if(t<.42) {a=mag;b=pouch;w=(t-.18)/.24;}
        else if(t<.62) {a=pouch;b=mag;w=(t-.42)/.20;}
        else if(t<.78) {a=mag;b=mag;w=0;}
        else {a=mag;b=support;w=(t-.78)/.22;}
        support=Blend(a,b,Smooth(w));
    }
    if(vault>0) {
        Vec shoulder=Origin(out.worlds[UpperArmL]);
        Vec plant=s.has_vault_hand?s.vault_hand:Vec{shoulder.x-.10,shoulder.y-.35,shoulder.z-.18};
        support=Blend(support,plant,vault);
    }
    if(s.throw_weight>0) {
        double t=s.throw_phase,w;Vec from,to,shoulder=Origin(out.worlds[UpperArmL]);
        Vec windup={shoulder.x-.12,shoulder.y+.24,shoulder.z+.20},release={shoulder.x-.10,shoulder.y+.18,shoulder.z-.40};
        if(t<.35) {from=support;to=windup;w=t/.35;}
        else if(t<.54) {from=windup;to=release;w=(t-.35)/.19;}
        else {from=release;to=support;w=(t-.54)/.46;}
        support=Blend(support,Blend(from,to,Smooth(w)),s.throw_weight*live);
    }
    Solve(out,rig,UpperArmL,ForearmL,HandL,support,{-.55,-1,.2});Orient(out,rig,HandL,gun);
    out.support_error=Length(Sub(Origin(out.worlds[HandL]),support));out.support=support;out.weapon=gun;
    double scale=rig.variants[s.variant].scale;
    for(int i=0;i<BoneCount;++i) {
        Mat& w=out.worlds[i];w.m[3]*=scale;w.m[7]*=scale;w.m[11]*=scale;
        Mat& p=out.palette[i];p=w;Vec b=rig.bones[i].bind;
        p.m[3]=w.m[3]-(w.m[0]*b.x+w.m[1]*b.y+w.m[2]*b.z)*scale;
        p.m[7]=w.m[7]-(w.m[4]*b.x+w.m[5]*b.y+w.m[6]*b.z)*scale;
        p.m[11]=w.m[11]-(w.m[8]*b.x+w.m[9]*b.y+w.m[10]*b.z)*scale;
    }
}
}
