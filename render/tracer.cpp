// Hi-tech living room — standalone CPU path tracer.
// Та же сцена, что в hitech_room.py, но без Blender: BVH по треугольникам,
// GGX-отражения, тонкое стекло, солнце + небо через оконные порталы,
// NEE по светящимся LED-полосам. Пишет HDR-буфер (float32 RGB).
//
// build:  g++ -O3 -march=native -std=c++17 -pthread tracer.cpp -o tracer
// run:    ./tracer W H SPP out.bin
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <functional>
#include <random>
#include <thread>
#include <vector>

// ------------------------------------------------------------------ math
struct V {
    float x = 0, y = 0, z = 0;
    V() {}
    V(float a, float b, float c) : x(a), y(b), z(c) {}
    V operator+(const V& o) const { return {x + o.x, y + o.y, z + o.z}; }
    V operator-(const V& o) const { return {x - o.x, y - o.y, z - o.z}; }
    V operator*(const V& o) const { return {x * o.x, y * o.y, z * o.z}; }
    V operator/(const V& o) const { return {x / o.x, y / o.y, z / o.z}; }
    V operator*(float s) const { return {x * s, y * s, z * s}; }
    V operator-() const { return {-x, -y, -z}; }
    V& operator+=(const V& o) { x += o.x; y += o.y; z += o.z; return *this; }
    float operator[](int i) const { return i == 0 ? x : (i == 1 ? y : z); }
    float& operator[](int i) { return i == 0 ? x : (i == 1 ? y : z); }
};
static inline float dot(V a, V b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline V cross(V a, V b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
static inline float len(V a) { return std::sqrt(dot(a, a)); }
static inline V norm(V a) { float l = len(a); return l > 0 ? a * (1.f / l) : a; }
static inline V vmin(V a, V b) { return {std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z)}; }
static inline V vmax(V a, V b) { return {std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z)}; }
static inline float lum(V c) { return 0.2126f * c.x + 0.7152f * c.y + 0.0722f * c.z; }
static const float PI = 3.14159265358979f;

struct M3 {  // column-major rotation
    V c0{1, 0, 0}, c1{0, 1, 0}, c2{0, 0, 1};
    V operator*(V v) const { return c0 * v.x + c1 * v.y + c2 * v.z; }
    M3 operator*(const M3& o) const { M3 r; r.c0 = (*this) * o.c0; r.c1 = (*this) * o.c1; r.c2 = (*this) * o.c2; return r; }
};
static M3 rotX(float a) { M3 m; m.c1 = {0, std::cos(a), std::sin(a)}; m.c2 = {0, -std::sin(a), std::cos(a)}; return m; }
static M3 rotY(float a) { M3 m; m.c0 = {std::cos(a), 0, -std::sin(a)}; m.c2 = {std::sin(a), 0, std::cos(a)}; return m; }
static M3 rotZ(float a) { M3 m; m.c0 = {std::cos(a), std::sin(a), 0}; m.c1 = {-std::sin(a), std::cos(a), 0}; return m; }
static M3 eulerXYZ(float x, float y, float z) { return rotZ(z) * rotY(y) * rotX(x); }  // как в Blender
static M3 fromTo(V a, V b) {  // поворот a -> b (Rodrigues)
    a = norm(a); b = norm(b);
    V v = cross(a, b); float c = dot(a, b);
    if (c < -0.9999f) { return rotZ(PI); }
    float k = 1.f / (1.f + c);
    M3 m;
    m.c0 = {v.x * v.x * k + c, v.y * v.x * k + v.z, v.z * v.x * k - v.y};
    m.c1 = {v.x * v.y * k - v.z, v.y * v.y * k + c, v.z * v.y * k + v.x};
    m.c2 = {v.x * v.z * k + v.y, v.y * v.z * k - v.x, v.z * v.z * k + c};
    return m;
}
static void basis(V n, V& t, V& b) {
    float s = n.z >= 0 ? 1.f : -1.f, a = -1.f / (s + n.z), bb = n.x * n.y * a;
    t = {1 + s * n.x * n.x * a, s * bb, -s * n.x};
    b = {bb, s + n.y * n.y * a, -n.y};
}

// ------------------------------------------------------------------ noise
static inline float hash3(int x, int y, int z) {
    uint32_t h = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u + (uint32_t)z * 2147483647u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return ((h ^ (h >> 16)) & 0xffffff) / float(0xffffff);
}
static float vnoise(V p) {
    int ix = (int)std::floor(p.x), iy = (int)std::floor(p.y), iz = (int)std::floor(p.z);
    float fx = p.x - ix, fy = p.y - iy, fz = p.z - iz;
    auto s = [](float t) { return t * t * (3 - 2 * t); };
    fx = s(fx); fy = s(fy); fz = s(fz);
    float r = 0;
    for (int c = 0; c < 8; c++) {
        int dx = c & 1, dy = (c >> 1) & 1, dz = (c >> 2) & 1;
        r += hash3(ix + dx, iy + dy, iz + dz) * (dx ? fx : 1 - fx) * (dy ? fy : 1 - fy) * (dz ? fz : 1 - fz);
    }
    return r;
}
static float fbm(V p) {
    float a = 0.5f, r = 0;
    for (int i = 0; i < 5; i++) { r += a * vnoise(p); p = p * 2.03f; a *= 0.5f; }
    return r / 0.97f;
}

// ------------------------------------------------------------------ materials
enum { STD = 0, GLASS = 1 };
struct Mat {
    V albedo; float rough = 0.5f; float metal = 0; int type = STD; float coat = 0;
    V emit; float nscale = 0; V albedoB;
};
std::vector<Mat> mats;
static int mat(V c, float rough, float metal = 0, float coat = 0) {
    Mat m; m.albedo = c; m.rough = rough; m.metal = metal; m.coat = coat; mats.push_back(m); return (int)mats.size() - 1;
}
static int glass(V tint) { Mat m; m.albedo = tint; m.type = GLASS; m.rough = 0; mats.push_back(m); return (int)mats.size() - 1; }
static int emitter(V e) { Mat m; m.emit = e; mats.push_back(m); return (int)mats.size() - 1; }
static void variation(int id, float scale, V b) { mats[id].nscale = scale; mats[id].albedoB = b; }

// ------------------------------------------------------------------ geometry
struct Tri { V p0, e1, e2, n0, n1, n2; int m; };
std::vector<Tri> tris;
static void tri(V a, V b, V c, V na, V nb, V nc, int m) {
    if (len(cross(b - a, c - a)) < 1e-12f) return;
    tris.push_back({a, b - a, c - a, na, nb, nc, m});
}
static void quad(V a, V b, V c, V d, V na, V nb, V nc, V nd, int m) { tri(a, b, c, na, nb, nc, m); tri(a, c, d, na, nc, nd, m); }

// скруглённый бокс (центр, полуразмеры, радиус фаски, поворот)
static void rbox(V ctr, V h, float r, int m, M3 R = M3(), int k = 4) {
    r = std::min(r, 0.49f * std::min(h.x, std::min(h.y, h.z)));
    std::vector<float> cs[3];
    for (int a = 0; a < 3; a++) {
        float H = h[a];
        if (r <= 0) { cs[a] = {-H, H}; continue; }
        for (int i = 0; i <= k; i++) cs[a].push_back(-H + r * i / k);
        for (int i = 0; i <= k; i++) cs[a].push_back(H - r + r * i / k);
    }
    auto map = [&](V p, V fn, V& P, V& N) {
        if (r <= 0) { P = p; N = fn; }
        else {
            V in = {std::clamp(p.x, -h.x + r, h.x - r), std::clamp(p.y, -h.y + r, h.y - r), std::clamp(p.z, -h.z + r, h.z - r)};
            V d = p - in; float l = len(d);
            N = l > 1e-9f ? d * (1.f / l) : fn;
            P = in + N * r;
        }
        P = R * P + ctr; N = R * N;
    };
    for (int a = 0; a < 3; a++)
        for (int s = -1; s <= 1; s += 2) {
            int u = (a + 1) % 3, v = (a + 2) % 3;
            V fn; fn[a] = (float)s;
            auto& cu = cs[u]; auto& cv = cs[v];
            for (size_t i = 0; i + 1 < cu.size(); i++)
                for (size_t j = 0; j + 1 < cv.size(); j++) {
                    if (cu[i + 1] - cu[i] < 1e-7f || cv[j + 1] - cv[j] < 1e-7f) continue;
                    V P[4], N[4];
                    float uu[4] = {cu[i], cu[i + 1], cu[i + 1], cu[i]}, vv[4] = {cv[j], cv[j], cv[j + 1], cv[j + 1]};
                    for (int q = 0; q < 4; q++) { V p; p[a] = s * h[a]; p[u] = uu[q]; p[v] = vv[q]; map(p, fn, P[q], N[q]); }
                    quad(P[0], P[1], P[2], P[3], N[0], N[1], N[2], N[3], m);
                }
        }
}
static void box(float x0, float x1, float y0, float y1, float z0, float z1, int m, float bevel = 0) {
    rbox({(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2}, {(x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2}, bevel, m);
}
// усечённый конус / цилиндр между точками
static void frustum(V p0, V p1, float r0, float r1, int m, int seg = 48, bool caps = true) {
    V w = p1 - p0; float L = len(w); w = norm(w);
    V u, v; basis(w, u, v);
    for (int i = 0; i < seg; i++) {
        float a0 = 2 * PI * i / seg, a1 = 2 * PI * (i + 1) / seg;
        V d0 = u * std::cos(a0) + v * std::sin(a0), d1 = u * std::cos(a1) + v * std::sin(a1);
        V n0 = norm(d0 * L + w * (r0 - r1)), n1 = norm(d1 * L + w * (r0 - r1));
        quad(p0 + d0 * r0, p0 + d1 * r0, p1 + d1 * r1, p1 + d0 * r1, n0, n1, n1, n0, m);
        if (caps) {
            if (r0 > 0) tri(p0, p0 + d1 * r0, p0 + d0 * r0, -w, -w, -w, m);
            if (r1 > 0) tri(p1, p1 + d0 * r1, p1 + d1 * r1, w, w, w, m);
        }
    }
}
static void cyl(V c, float r, float depth, int m, int seg = 64) { frustum(c - V(0, 0, depth / 2), c + V(0, 0, depth / 2), r, r, m, seg); }
static void ellipsoid(V c, V s, int m, M3 R = M3(), int seg = 24, int rings = 12) {
    auto P = [&](int i, int j, V& p, V& n) {
        float th = PI * j / rings, ph = 2 * PI * i / seg;
        V u = {std::sin(th) * std::cos(ph), std::sin(th) * std::sin(ph), std::cos(th)};
        p = R * (u * s) + c; n = norm(R * (u / s));
    };
    for (int i = 0; i < seg; i++)
        for (int j = 0; j < rings; j++) {
            V a, b, cc, d, na, nb, nc, nd;
            P(i, j, a, na); P(i + 1, j, b, nb); P(i + 1, j + 1, cc, nc); P(i, j + 1, d, nd);
            quad(a, b, cc, d, na, nb, nc, nd, m);
        }
}
static void torus(V c, float R0, float r, int m, int seg = 128, int mseg = 16) {
    auto P = [&](int i, int j, V& p, V& n) {
        float a = 2 * PI * i / seg, b = 2 * PI * j / mseg;
        V d = {std::cos(a), std::sin(a), 0};
        n = d * std::cos(b) + V(0, 0, std::sin(b));
        p = c + d * R0 + n * r;
    };
    for (int i = 0; i < seg; i++)
        for (int j = 0; j < mseg; j++) {
            V a, b, cc, d, na, nb, nc, nd;
            P(i, j, a, na); P(i + 1, j, b, nb); P(i + 1, j + 1, cc, nc); P(i, j + 1, d, nd);
            quad(a, b, cc, d, na, nb, nc, nd, m);
        }
}

// ------------------------------------------------------------------ BVH
struct Node { V lo, hi; int left, start, count; };
std::vector<Node> nodes;
std::vector<int> tidx;
static V tlo(const Tri& t) { return vmin(t.p0, vmin(t.p0 + t.e1, t.p0 + t.e2)); }
static V thi(const Tri& t) { return vmax(t.p0, vmax(t.p0 + t.e1, t.p0 + t.e2)); }
struct Ray { V o, d; };
struct Hit { float t; int tri; float u, v; };
static inline bool slab(const Node& n, const Ray& r, V inv, float tmax, float& tn) {
    float t0 = 0, t1 = tmax;
    for (int a = 0; a < 3; a++) {
        float ta = (n.lo[a] - r.o[a]) * inv[a], tb = (n.hi[a] - r.o[a]) * inv[a];
        if (ta > tb) std::swap(ta, tb);
        t0 = std::max(t0, ta); t1 = std::min(t1, tb);
        if (t0 > t1) return false;
    }
    tn = t0; return true;
}
static bool intersect(const Ray& r, Hit& h, float tmax = 1e30f, bool shadow = false) {
    V inv = {1.f / r.d.x, 1.f / r.d.y, 1.f / r.d.z};
    int stack[64], sp = 0; stack[sp++] = 0;
    bool found = false; h.t = tmax;
    while (sp) {
        const Node& n = nodes[stack[--sp]];
        float tn;
        if (!slab(n, r, inv, h.t, tn)) continue;
        if (n.left < 0) {
            for (int i = n.start; i < n.start + n.count; i++) {
                const Tri& t = tris[tidx[i]];
                if (shadow && mats[t.m].type == GLASS) continue;  // стекло не отбрасывает тень
                V p = cross(r.d, t.e2); float det = dot(t.e1, p);
                if (std::fabs(det) < 1e-12f) continue;
                float id = 1.f / det; V s = r.o - t.p0;
                float u = dot(s, p) * id; if (u < 0 || u > 1) continue;
                V q = cross(s, t.e1); float v = dot(r.d, q) * id; if (v < 0 || u + v > 1) continue;
                float tt = dot(t.e2, q) * id;
                if (tt > 1e-5f && tt < h.t) {
                    h.t = tt; h.tri = tidx[i]; h.u = u; h.v = v; found = true;
                    if (shadow) return true;
                }
            }
        } else {
            stack[sp++] = n.start;  // правый ребёнок
            stack[sp++] = n.left;
        }
    }
    return found;
}
static bool occluded(V o, V d, float tmax) { Hit h; Ray r{o, d}; return intersect(r, h, tmax, true); }

// ------------------------------------------------------------------ scene
const float W = 2.1f, D = 5.0f, H = 2.8f, T = 0.15f, SILL = 0.86f, WTOP = 2.5f;
const float WIN[2][2] = {{-1.7f, -0.4f}, {0.4f, 1.7f}};
const float GLASS_Y = D + 0.074f;
V SUN_L;                       // направление на солнце
V SUN_E = {19.f, 17.5f, 15.f};  // освещённость от солнца
float SUN_COS;

static V sky(V d) {
    if (d.z < 0) {  // земля/улица
        float t = std::min(1.f, -d.z * 4);
        return V(0.42f, 0.46f, 0.36f) * (1 - t) + V(0.3f, 0.34f, 0.25f) * t;
    }
    float t = std::pow(1 - d.z, 3.f);
    V c = V(0.35f, 0.55f, 1.05f) * (1 - t) + V(1.35f, 1.4f, 1.45f) * t;
    float g = std::max(0.f, dot(d, SUN_L));
    return c + V(1.2f, 1.0f, 0.75f) * (2.5f * std::pow(g, 12.f));
}

std::vector<int> emTris; std::vector<float> emCdf; float emTotal = 0;

static void buildScene() {
    std::mt19937 rng(7);
    std::uniform_real_distribution<float> U(0, 1);
    auto ur = [&](float a, float b) { return a + (b - a) * U(rng); };

    int concrete = mat({0.42f, 0.42f, 0.41f}, 0.22f, 0, 0.3f); variation(concrete, 1.6f, {0.3f, 0.3f, 0.29f});
    int wall = mat({0.8f, 0.8f, 0.79f}, 0.7f);
    int graphite = mat({0.055f, 0.057f, 0.06f}, 0.5f); variation(graphite, 7.f, {0.085f, 0.087f, 0.09f});
    int ceiling = mat({0.85f, 0.85f, 0.85f}, 0.85f);
    int aluBlack = mat({0.03f, 0.03f, 0.032f}, 0.3f, 1);
    int chrome = mat({0.9f, 0.9f, 0.92f}, 0.06f, 1);
    int winGlass = glass({1, 1, 1});
    int tabGlass = glass({0.82f, 0.9f, 0.87f});
    int lacquer = mat({0.8f, 0.8f, 0.8f}, 0.18f, 0, 1);
    int screen = mat({0.004f, 0.004f, 0.005f}, 0.05f, 0, 1);
    int quartz = mat({0.78f, 0.78f, 0.76f}, 0.15f, 0, 0.6f);
    int fabric = mat({0.075f, 0.078f, 0.082f}, 0.9f); variation(fabric, 180.f, {0.05f, 0.052f, 0.056f});
    int pillowW = mat({0.7f, 0.7f, 0.68f}, 0.9f);
    int pillowG = mat({0.24f, 0.32f, 0.25f}, 0.9f);
    int leather = mat({0.025f, 0.025f, 0.025f}, 0.35f, 0, 0.3f);
    int rug = mat({0.2f, 0.2f, 0.195f}, 1.f); variation(rug, 90.f, {0.14f, 0.14f, 0.135f});
    int pot = mat({0.78f, 0.78f, 0.76f}, 0.55f);
    int soil = mat({0.03f, 0.02f, 0.015f}, 1.f);
    int stem = mat({0.08f, 0.16f, 0.05f}, 0.6f);
    int leaf = mat({0.04f, 0.17f, 0.05f}, 0.35f); variation(leaf, 30.f, {0.06f, 0.22f, 0.06f});
    int cat = mat({0.11f, 0.11f, 0.12f}, 0.8f);
    int art = mat({0.36f, 0.45f, 0.37f}, 0.9f);
    int ledWarm = emitter(V(1.0f, 0.86f, 0.7f) * 7.f);
    int ledNeutral = emitter(V(1.0f, 0.94f, 0.86f) * 9.f);
    int ledCool = emitter(V(0.65f, 0.8f, 1.0f) * 6.f);

    // коробка комнаты (передняя стена за камерой закрывает объём)
    box(-W - T, W + T, -0.6f, D + T, -0.1f, 0, concrete);
    box(-W - T, W + T, -0.6f, D + T, H, H + 0.1f, ceiling);
    box(-W - T, -W, -0.6f, D + T, 0, H, wall);
    box(W, W + T, -0.6f, D + T, 0, H, wall);
    box(-W, W, -0.75f, -0.6f, 0, H, wall);
    box(-W, W, D, D + T, 0, SILL, wall);
    box(-W, W, D, D + T, WTOP, H, wall);
    float xs[6] = {-W, WIN[0][0], WIN[0][1], WIN[1][0], WIN[1][1], W};
    for (int i = 0; i < 6; i += 2) box(xs[i], xs[i + 1], D, D + T, SILL, WTOP, wall);

    float fy0 = D + 0.04f, fy1 = D + 0.11f, f = 0.05f;
    for (auto& w : WIN) {
        float a = w[0], b = w[1], c = (a + b) / 2;
        box(a, a + f, fy0, fy1, SILL, WTOP, aluBlack);
        box(b - f, b, fy0, fy1, SILL, WTOP, aluBlack);
        box(a, b, fy0, fy1, WTOP - f, WTOP, aluBlack);
        box(a, b, fy0, fy1, SILL, SILL + f, aluBlack);
        box(c - 0.02f, c + 0.02f, fy0, fy1, SILL, WTOP, aluBlack);
        V n = {0, 1, 0};
        quad({a, GLASS_Y, SILL}, {b, GLASS_Y, SILL}, {b, GLASS_Y, WTOP}, {a, GLASS_Y, WTOP}, n, n, n, n, winGlass);
    }
    box(-W, W, D - 0.28f, D + 0.04f, SILL - 0.04f, SILL, quartz, 0.004f);
    box(-W + 0.05f, W - 0.05f, D - 0.06f, D - 0.03f, SILL - 0.05f, SILL - 0.04f, ledWarm);
    box(-0.28f, 0.28f, D - 0.03f, D, 1.35f, 2.15f, aluBlack);
    box(-0.25f, 0.25f, D - 0.035f, D - 0.03f, 1.38f, 2.12f, art);

    // ТВ-зона
    box(-W, -W + 0.02f, 1.5f, 4.1f, 0, H, graphite);
    box(-W + 0.02f, -W + 0.025f, 2.2f, 3.4f, 1.05f, 1.66f, ledCool);
    box(-W + 0.03f, -W + 0.06f, 2.08f, 3.52f, 0.95f, 1.76f, aluBlack, 0.005f);
    box(-W + 0.06f, -W + 0.064f, 2.1f, 3.5f, 0.97f, 1.74f, screen);
    box(-W + 0.02f, -W + 0.44f, 1.85f, 3.75f, 0.28f, 0.62f, lacquer, 0.006f);
    for (float y : {2.48f, 3.12f}) box(-W + 0.44f, -W + 0.443f, y - 0.002f, y + 0.002f, 0.3f, 0.6f, aluBlack);
    box(-W + 0.08f, -W + 0.36f, 1.95f, 3.65f, 0.265f, 0.28f, ledWarm);
    cyl({-W + 0.22f, 3.5f, 0.75f}, 0.06f, 0.26f, aluBlack);

    // диван
    float sx0 = W - 0.95f, sx1 = W - 0.02f, sy0 = 1.6f, sy1 = 4.3f, sm = (sy0 + sy1) / 2;
    box(sx0, sx1, sy0, sy1, 0.1f, 0.38f, fabric, 0.03f);
    box(sx1 - 0.22f, sx1, sy0 + 0.2f, sy1 - 0.2f, 0.38f, 0.85f, fabric, 0.05f);
    box(sx0 + 0.02f, sx1 - 0.22f, sy0 + 0.205f, sm - 0.005f, 0.38f, 0.52f, fabric, 0.05f);
    box(sx0 + 0.02f, sx1 - 0.22f, sm + 0.005f, sy1 - 0.205f, 0.38f, 0.52f, fabric, 0.05f);
    box(sx0, sx1, sy0, sy0 + 0.2f, 0.1f, 0.64f, fabric, 0.04f);
    box(sx0, sx1, sy1 - 0.2f, sy1, 0.1f, 0.64f, fabric, 0.04f);
    for (float y : {sy0 + 0.1f, sy1 - 0.1f}) box(sx0 + 0.05f, sx1 - 0.05f, y - 0.012f, y + 0.012f, 0, 0.1f, chrome, 0.004f);
    rbox({sx1 - 0.32f, sy1 - 0.55f, 0.72f}, {0.07f, 0.24f, 0.22f}, 0.06f, pillowW, eulerXYZ(0, -0.244f, 0.14f), 6);
    rbox({sx1 - 0.34f, sy1 - 0.95f, 0.70f}, {0.07f, 0.22f, 0.20f}, 0.06f, pillowG, eulerXYZ(0, -0.21f, -0.105f), 6);
    box(W - 0.02f, W, 1.7f, 4.2f, 1.95f, 1.97f, ledNeutral);

    // столик, пуф, ковёр
    float tx = -0.25f, ty = 2.55f;
    box(-1.45f, 1.05f, 1.3f, 3.9f, 0, 0.012f, rug, 0.004f);
    cyl({tx, ty, 0.02f}, 0.25f, 0.016f, chrome);
    cyl({tx, ty, 0.22f}, 0.028f, 0.39f, chrome);
    cyl({tx, ty, 0.425f}, 0.48f, 0.012f, tabGlass, 128);
    box(tx + 0.05f, tx + 0.29f, ty - 0.2f, ty, 0.431f, 0.451f, aluBlack, 0.002f);
    box(tx + 0.07f, tx + 0.27f, ty - 0.18f, ty - 0.03f, 0.451f, 0.468f, quartz, 0.002f);
    box(0.32f, 0.82f, 2.1f, 2.6f, 0.03f, 0.44f, leather, 0.04f);
    box(0.36f, 0.78f, 2.14f, 2.56f, 0, 0.03f, chrome);

    // растения
    auto plant = [&](float x, float y, float z, float pr, float ph, float height, int leaves, float ll, float spread) {
        cyl({x, y, z + ph / 2}, pr, ph, pot);
        cyl({x, y, z + ph - 0.01f}, pr * 0.93f, 0.01f, soil);
        V base = {x, y, z + ph - 0.01f};
        for (int i = 0; i < leaves; i++) {
            float ang = i * 2.39996f + ur(-0.3f, 0.3f);
            float h = height * ur(0.55f, 1.0f), r = height * spread * ur(0.4f, 0.8f);
            V tip = base + V(std::cos(ang) * r, std::sin(ang) * r, h);
            frustum(base, tip, std::max(0.003f, ll * 0.025f), std::max(0.003f, ll * 0.025f), stem, 8, false);
            V out = norm(V(std::cos(ang), std::sin(ang), -0.35f));
            float L = ll * ur(0.75f, 1.1f);
            ellipsoid(tip + out * (L * 0.45f), {L * 0.5f, L * 0.36f, L * 0.03f}, leaf, fromTo({1, 0, 0}, out));
        }
    };
    plant(-1.72f, 4.4f, 0, 0.2f, 0.45f, 1.1f, 11, 0.32f, 0.6f);
    plant(0.95f, D - 0.14f, SILL, 0.07f, 0.14f, 0.32f, 7, 0.08f, 0.6f);
    plant(1.5f, D - 0.14f, SILL, 0.06f, 0.12f, 0.42f, 6, 0.07f, 0.3f);
    plant(tx - 0.2f, ty + 0.12f, 0.431f, 0.05f, 0.09f, 0.14f, 6, 0.05f, 0.6f);

    // кот
    float cx = -1.15f, cy = D - 0.15f, cz = SILL;
    ellipsoid({cx, cy, cz + 0.13f}, {0.1f, 0.09f, 0.14f}, cat);
    ellipsoid({cx, cy - 0.01f, cz + 0.06f}, {0.12f, 0.11f, 0.07f}, cat);
    ellipsoid({cx, cy + 0.02f, cz + 0.32f}, {0.075f, 0.07f, 0.065f}, cat);
    for (int s = -1; s <= 1; s += 2) {
        V b = {cx + s * 0.042f, cy + 0.02f, cz + 0.36f};
        V top = b + V(s * 0.012f, 0, 0.065f);
        frustum(b, top, 0.028f, 0.0f, cat, 16);
    }
    V tail[3] = {{cx + 0.08f, cy - 0.06f, cz + 0.02f}, {cx + 0.18f, cy - 0.12f, cz + 0.015f}, {cx + 0.26f, cy - 0.1f, cz + 0.015f}};
    for (int i = 0; i < 2; i++) frustum(tail[i], tail[i + 1], 0.018f, 0.016f, cat, 12);

    // свет
    for (int s = -1; s <= 1; s += 2) box(s * 1.3f - 0.015f, s * 1.3f + 0.015f, 0.6f, 4.6f, H - 0.012f, H, ledNeutral);
    torus({tx, ty, 2.15f}, 0.42f, 0.016f, aluBlack);
    torus({tx, ty, 2.138f}, 0.42f, 0.009f, ledWarm, 128, 12);
    for (int k = 0; k < 3; k++) {
        float a = k * 2 * PI / 3;
        V p = {tx + std::cos(a) * 0.42f, ty + std::sin(a) * 0.42f, 2.166f};
        frustum(p, {p.x, p.y, H}, 0.0012f, 0.0012f, chrome, 6, false);
    }
}

// ------------------------------------------------------------------ rendering
struct Rng { uint64_t s; float next() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return (s >> 40) * (1.f / 16777216.f); } };

static V albedoAt(const Mat& m, V p) {
    if (m.nscale <= 0) return m.albedo;
    float t = std::clamp((fbm(p * m.nscale) - 0.25f) * 2.f, 0.f, 1.f);
    return m.albedo * (1 - t) + m.albedoB * t;
}
static inline float schlick(float f0, float c) { float m = 1 - c; return f0 + (1 - f0) * m * m * m * m * m; }
static inline V schlickV(V f0, float c) { float m = 1 - c, p = m * m * m * m * m; return f0 + (V(1, 1, 1) - f0) * p; }
static inline float G1(float a2, float c) { c = std::max(c, 1e-4f); float t2 = (1 - c * c) / (c * c); return 2.f / (1.f + std::sqrt(1 + a2 * t2)); }

// GGX: возвращает направление и вес (f*cos/pdf без Френеля)
static bool sampleGGX(V n, V wo, float rough, Rng& g, V& wi, float& w, float& woh) {
    float a = std::max(rough * rough, 1e-3f), a2 = a * a;
    float u1 = g.next(), u2 = g.next();
    float ct = std::sqrt((1 - u2) / (1 + (a2 - 1) * u2)), st = std::sqrt(std::max(0.f, 1 - ct * ct)), ph = 2 * PI * u1;
    V t, b; basis(n, t, b);
    V h = norm(t * (st * std::cos(ph)) + b * (st * std::sin(ph)) + n * ct);
    woh = dot(wo, h);
    if (woh <= 0) return false;
    wi = h * (2 * woh) - wo;
    float ni = dot(n, wi), no = dot(n, wo);
    if (ni <= 0 || no <= 0) return false;
    w = G1(a2, ni) * G1(a2, no) * woh / (no * ct);
    return true;
}

// прямой свет на диффузную часть: солнце + небо через порталы + LED
int DBG = 7;
static V direct(V p, V n, Rng& g) {
    V L;
    // солнце (маленький конус)
    if (DBG & 1) {
        V t, b; basis(SUN_L, t, b);
        float r = std::sqrt(g.next()) * std::sqrt(1 - SUN_COS * SUN_COS), ph = 2 * PI * g.next();
        V d = norm(SUN_L + t * (r * std::cos(ph)) + b * (r * std::sin(ph)));
        float c = dot(n, d);
        if (c > 0 && !occluded(p, d, 1e30f)) L += SUN_E * c;
    }
    // небо через окно-портал
    if (DBG & 2) {
        int wi = g.next() < 0.5f ? 0 : 1;
        float a = WIN[wi][0], bb = WIN[wi][1];
        V q = {a + (bb - a) * g.next(), GLASS_Y + 0.01f, SILL + (WTOP - SILL) * g.next()};
        V d = q - p; float dist = len(d); d = d * (1.f / dist);
        float c = dot(n, d), cw = std::fabs(d.y);
        if (c > 0 && cw > 0 && p.y < D && !occluded(p, d, dist)) {
            float area = (bb - a) * (WTOP - SILL);
            L += sky(d) * (c * cw / (dist * dist) * area * 2.f);
        }
    }
    // LED-источники
    if ((DBG & 4) && emTotal > 0) {
        float u = g.next() * emTotal;
        int k = int(std::lower_bound(emCdf.begin(), emCdf.end(), u) - emCdf.begin());
        k = std::min(k, (int)emTris.size() - 1);
        const Tri& t = tris[emTris[k]];
        float su = std::sqrt(g.next()), v = g.next();
        V q = t.p0 + t.e1 * (1 - v) * su + t.e2 * (v * su);
        V d = q - p; float dist = len(d); d = d * (1.f / dist);
        V nl = cross(t.e1, t.e2); float area = len(nl) * 0.5f; nl = nl * (0.5f / area);
        float c = dot(n, d), cl = std::fabs(dot(nl, d));
        if (c > 0 && cl > 0 && !occluded(p, d, dist * 0.999f)) {
            V Le = mats[t.m].emit;
            float pdfA = lum(Le) * area / emTotal / area;
            L += Le * (c * cl / (dist * dist) / pdfA);
        }
    }
    return L;
}

struct Aux { V alb, nrm; float depth = 0, filt = 0; bool set = false; };
static V trace(Ray r, Rng& g, Aux& ax) {
    V L, beta(1, 1, 1);
    bool countEmit = true;
    for (int depth = 0; depth < 14; depth++) {
        Hit h;
        if (!intersect(r, h)) {
            if (!ax.set) { ax.set = true; ax.alb = V(1, 1, 1); ax.nrm = -r.d; ax.depth = 1e3f; }
            if (countEmit) L += beta * sky(r.d);
            break;
        }
        const Tri& t = tris[h.tri];
        const Mat& m = mats[t.m];
        V p = r.o + r.d * h.t, wo = -r.d;
        V ng = norm(cross(t.e1, t.e2));
        if (dot(ng, wo) < 0) ng = -ng;
        V n = norm(t.n0 * (1 - h.u - h.v) + t.n1 * h.u + t.n2 * h.v);
        if (dot(n, ng) < 0) n = -n;
        if (dot(n, wo) < 0.02f) n = norm(n + ng * (0.02f - dot(n, wo)));

        if (!ax.set && m.type != GLASS) {
            ax.set = true; ax.nrm = n; ax.depth = h.t;
            bool mirror = m.metal > 0.5f || m.rough < 0.1f;
            ax.alb = mirror || lum(m.emit) > 0 ? V(1, 1, 1) : albedoAt(m, p);
            ax.filt = lum(m.emit) > 0 || (m.metal > 0.5f && m.rough < 0.1f) ? 0.f : 1.f;
        }
        if (lum(m.emit) > 0) { if (countEmit) L += beta * m.emit; break; }

        if (m.type == GLASS) {
            float F = schlick(0.04f, std::fabs(dot(ng, wo)));
            if (g.next() < F) { r = {p + ng * 1e-4f, r.d - ng * (2 * dot(r.d, ng))}; countEmit = true; }
            else { beta = beta * m.albedo; r = {p - ng * 1e-4f, r.d}; }
            continue;
        }

        V po = p + ng * 2e-4f;
        V alb = albedoAt(m, p);
        float no = std::max(dot(n, wo), 1e-4f);
        V wi; float w, woh;
        if (m.metal > 0.5f) {
            if (!sampleGGX(n, wo, m.rough, g, wi, w, woh)) break;
            beta = beta * schlickV(alb, woh) * w;
            countEmit = true;
        } else {
            float Fc = m.coat * schlick(0.04f, no), Fb = schlick(0.04f, no);
            float kd = (1 - Fc) * (1 - Fb);
            V Ld = direct(po, n, g);
            V c = beta * alb * Ld * (kd / PI);
            float cl = lum(c), cap = depth == 0 ? 60.f : 6.f;
            if (cl > cap) c = c * (cap / cl);
            L += c;
            float u = g.next();
            if (u < Fc) {
                if (!sampleGGX(n, wo, 0.03f, g, wi, w, woh)) break;
                beta = beta * w; countEmit = true;
            } else if (u < Fc + (1 - Fc) * Fb) {
                if (!sampleGGX(n, wo, m.rough, g, wi, w, woh)) break;
                beta = beta * w; countEmit = m.rough < 0.35f;  // шероховатый блик ловит LED только через NEE
            } else {
                V tt, bb; basis(n, tt, bb);
                float r1 = std::sqrt(g.next()), ph = 2 * PI * g.next();
                wi = norm(tt * (r1 * std::cos(ph)) + bb * (r1 * std::sin(ph)) + n * std::sqrt(std::max(0.f, 1 - r1 * r1)));
                beta = beta * alb; countEmit = false;
            }
        }
        if (dot(wi, ng) <= 0) break;
        // ограничение светлячков на непрямых бликах
        float bl = lum(beta);
        if (depth > 0 && bl > 4.f) beta = beta * (4.f / bl);
        if (depth >= 3) {
            float q = std::min(0.95f, std::max(0.05f, bl));
            if (g.next() > q) break;
            beta = beta * (1.f / q);
        }
        r = {po, wi};
    }
    return L;
}

int main(int argc, char** argv) {
    int Wd = argc > 1 ? atoi(argv[1]) : 800, Hd = argc > 2 ? atoi(argv[2]) : 600, spp = argc > 3 ? atoi(argv[3]) : 64;
    const char* out = argc > 4 ? argv[4] : "out.bin";
    if (getenv("DBG")) DBG = atoi(getenv("DBG"));
    SUN_L = norm(V(0.3f, 0.75f, 0.65f));
    SUN_COS = std::cos(0.3f * PI / 180.f);
    buildScene();
    tidx.resize(tris.size());
    for (size_t i = 0; i < tris.size(); i++) tidx[i] = (int)i;
    nodes.reserve(tris.size());
    std::function<int(int, int)> go = [&](int start, int count) -> int {
        Node nd; nd.lo = {1e30f, 1e30f, 1e30f}; nd.hi = {-1e30f, -1e30f, -1e30f};
        V clo = nd.lo, chi = nd.hi;
        for (int i = start; i < start + count; i++) {
            const Tri& t = tris[tidx[i]];
            nd.lo = vmin(nd.lo, tlo(t)); nd.hi = vmax(nd.hi, thi(t));
            V c = (tlo(t) + thi(t)) * 0.5f; clo = vmin(clo, c); chi = vmax(chi, c);
        }
        int id = (int)nodes.size(); nodes.push_back(nd);
        if (count <= 4) { nodes[id].left = -1; nodes[id].start = start; nodes[id].count = count; return id; }
        const int B = 16;
        int bestAxis = -1, bestSplit = 0; float bestCost = 1e30f;
        auto area = [](V lo, V hi) { V d = hi - lo; return d.x * d.y + d.y * d.z + d.z * d.x; };
        for (int a = 0; a < 3; a++) {
            float ext = chi[a] - clo[a]; if (ext < 1e-9f) continue;
            V blo[B], bhi[B]; int bc[B] = {0};
            for (int b = 0; b < B; b++) { blo[b] = {1e30f, 1e30f, 1e30f}; bhi[b] = {-1e30f, -1e30f, -1e30f}; }
            for (int i = start; i < start + count; i++) {
                const Tri& t = tris[tidx[i]];
                float c = (tlo(t)[a] + thi(t)[a]) * 0.5f;
                int b = std::min(B - 1, (int)((c - clo[a]) / ext * B));
                bc[b]++; blo[b] = vmin(blo[b], tlo(t)); bhi[b] = vmax(bhi[b], thi(t));
            }
            for (int s = 1; s < B; s++) {
                V l0 = {1e30f, 1e30f, 1e30f}, l1 = {-1e30f, -1e30f, -1e30f}, r0 = l0, r1 = l1; int nl = 0, nr = 0;
                for (int b = 0; b < s; b++) if (bc[b]) { l0 = vmin(l0, blo[b]); l1 = vmax(l1, bhi[b]); nl += bc[b]; }
                for (int b = s; b < B; b++) if (bc[b]) { r0 = vmin(r0, blo[b]); r1 = vmax(r1, bhi[b]); nr += bc[b]; }
                if (!nl || !nr) continue;
                float cost = nl * area(l0, l1) + nr * area(r0, r1);
                if (cost < bestCost) { bestCost = cost; bestAxis = a; bestSplit = s; }
            }
        }
        int mid;
        if (bestAxis < 0) mid = start + count / 2;
        else {
            float ext = chi[bestAxis] - clo[bestAxis];
            auto it = std::partition(tidx.begin() + start, tidx.begin() + start + count, [&](int ti) {
                const Tri& t = tris[ti];
                float c = (tlo(t)[bestAxis] + thi(t)[bestAxis]) * 0.5f;
                return std::min(B - 1, (int)((c - clo[bestAxis]) / ext * B)) < bestSplit;
            });
            mid = (int)(it - tidx.begin());
            if (mid == start || mid == start + count) mid = start + count / 2;
        }
        int l = go(start, mid - start);
        int r = go(mid, start + count - mid);
        nodes[id].left = l; nodes[id].start = r; nodes[id].count = 0;
        return id;
    };
    go(0, (int)tris.size());

    for (size_t i = 0; i < tris.size(); i++) {
        V e = mats[tris[i].m].emit;
        if (lum(e) <= 0) continue;
        float a = len(cross(tris[i].e1, tris[i].e2)) * 0.5f;
        emTotal += lum(e) * a; emTris.push_back((int)i); emCdf.push_back(emTotal);
    }
    fprintf(stderr, "tris=%zu nodes=%zu emissive=%zu\n", tris.size(), nodes.size(), emTris.size());

    // камера: как в Blender-скрипте (18 мм, кадр 36 мм, наклон 87°)
    V camPos = {0.f, -0.1f, 1.3f};
    float tilt = 87.f * PI / 180.f;
    V fwd = {0, std::sin(tilt), -std::cos(tilt)}, right = {1, 0, 0}, up = cross(right, fwd);
    float halfW = 18.f / 18.f, halfH = halfW * Hd / Wd;

    std::vector<float> img((size_t)Wd * Hd * 3, 0.f), aux((size_t)Wd * Hd * 8, 0.f);
    std::atomic<int> nextRow{0};
    auto t0 = std::chrono::steady_clock::now();
    int nth = std::max(1u, std::thread::hardware_concurrency());
    std::vector<std::thread> th;
    for (int k = 0; k < nth; k++)
        th.emplace_back([&, k] {
            int y;
            while ((y = nextRow++) < Hd) {
                for (int x = 0; x < Wd; x++) {
                    Rng g{(uint64_t)(y * 9781 + x * 6271 + 1) * 0x9E3779B97F4A7C15ull | 1};
                    for (int i = 0; i < 4; i++) g.next();
                    V acc, aA, aN; float aD = 0, aF = 0;
                    for (int s = 0; s < spp; s++) {
                        float px = (x + g.next()) / Wd * 2 - 1, py = 1 - (y + g.next()) / Hd * 2;
                        V d = norm(fwd + right * (px * halfW) + up * (py * halfH));
                        Aux ax;
                        acc += trace({camPos, d}, g, ax);
                        aA += ax.alb; aN += ax.nrm; aD += ax.depth; aF += ax.filt;
                    }
                    float is = 1.f / spp;
                    acc = acc * is;
                    size_t o = ((size_t)y * Wd + x) * 3, q = ((size_t)y * Wd + x) * 8;
                    img[o] = acc.x; img[o + 1] = acc.y; img[o + 2] = acc.z;
                    V nn = norm(aN);
                    float a8[8] = {aA.x * is, aA.y * is, aA.z * is, nn.x, nn.y, nn.z, aD * is, aF * is};
                    for (int i = 0; i < 8; i++) aux[q + i] = a8[i];
                }
                if (k == 0 && y % 20 == 0) {
                    double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
                    fprintf(stderr, "row %d/%d  %.0fs\n", (int)nextRow, Hd, el);
                }
            }
        });
    for (auto& t : th) t.join();
    FILE* f = fopen(out, "wb");
    int hdr[2] = {Wd, Hd};
    fwrite(hdr, sizeof(int), 2, f);
    fwrite(img.data(), sizeof(float), img.size(), f);
    fwrite(aux.data(), sizeof(float), aux.size(), f);
    fclose(f);
    double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    fprintf(stderr, "done %.1fs\n", el);
}
