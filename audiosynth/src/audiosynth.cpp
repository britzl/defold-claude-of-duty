#include <dmsdk/sdk.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace {
const char* META = "audiosynth.job";
const uint32_t RATE = 22050;
const uint32_t MODULUS = 2147483647;
const uint32_t ECHO_A = 815;  // floor(.037 * RATE)
const uint32_t ECHO_B = 1565; // floor(.071 * RATE)
const double PI = 3.14159265358979323846;
enum Kind { SHOT, IMPACT, STEP, MECHANIC, SHELL, HURT, CLOTH, AMBIENCE };
enum Treatment { DRY, ROOM, MUFFLED };

struct Job {
    Kind kind;
    Treatment treatment;
    uint32_t frames, cursor, random, initial_random, warmup;
    double duration, variant, p[8], hum_a, hum_b;
    double low, mid, muffle, dc, phase, peak, square;
    double history[ECHO_B + 1];
    bool wind, finished;
    dmArray<uint8_t> wav;

    Job() : kind(SHOT), treatment(DRY), frames(0), cursor(0), random(1), initial_random(1), warmup(0),
        duration(0), variant(1), hum_a(0), hum_b(0), low(0), mid(0), muffle(0), dc(0), phase(0),
        peak(0), square(0), wind(false), finished(false) {
        std::memset(p, 0, sizeof(p));
        std::memset(history, 0, sizeof(history));
    }
};

static void U16(uint8_t* out, uint32_t value) {
    out[0] = (uint8_t)value; out[1] = (uint8_t)(value >> 8);
}
static void U32(uint8_t* out, uint32_t value) {
    U16(out, value); U16(out + 2, value >> 16);
}
static Job* Check(lua_State* L) {
    Job** owner = (Job**)luaL_checkudata(L, 1, META);
    luaL_argcheck(L, *owner != 0, 1, "synthesis job is closed");
    return *owner;
}
static int Close(lua_State* L) {
    Job** owner = (Job**)luaL_checkudata(L, 1, META);
    delete *owner; *owner = 0;
    return 0;
}
static double Number(lua_State* L, const char* key) {
    lua_getfield(L, 1, key);
    luaL_argcheck(L, lua_type(L, -1) == LUA_TNUMBER, 1, key);
    double value = lua_tonumber(L, -1);
    luaL_argcheck(L, std::isfinite(value), 1, key);
    lua_pop(L, 1);
    return value;
}
static const char* String(lua_State* L, const char* key) {
    lua_getfield(L, 1, key);
    luaL_argcheck(L, lua_type(L, -1) == LUA_TSTRING, 1, key);
    const char* value = lua_tostring(L, -1);
    lua_pop(L, 1);
    return value; // The recipe table still owns this string.
}
static int New(lua_State* L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    double seed = luaL_checknumber(L, 2);
    luaL_argcheck(L, std::isfinite(seed) && std::abs(seed) <= 9007199254740991.0, 2, "invalid seed");
    luaL_checktype(L, 3, LUA_TTABLE);
    size_t stream_length;
    const char* stream = luaL_checklstring(L, 4, &stream_length);
    const char* kinds[] = {"shot", "impact", "step", "mechanic", "shell", "hurt", "cloth", "ambience"};
    const char* kind_name = String(L, "kind");
    int kind = -1;
    for (int i = 0; i < 8; ++i) if (std::strcmp(kind_name, kinds[i]) == 0) kind = i;
    luaL_argcheck(L, kind >= 0, 1, "invalid synthesis kind");
    const char* name = String(L, "name");
    bool wind = std::strcmp(name, "wind") == 0;
    luaL_argcheck(L, kind != AMBIENCE || wind || std::strcmp(name, "city") == 0, 1, "invalid ambience");
    const char* treatment_name = String(L, "treatment");
    int treatment = std::strcmp(treatment_name, "dry") == 0 ? DRY :
        std::strcmp(treatment_name, "room") == 0 ? ROOM :
        std::strcmp(treatment_name, "muffled") == 0 ? MUFFLED : -1;
    luaL_argcheck(L, treatment >= 0, 1, "invalid treatment");
    double duration = Number(L, "duration"), variant = Number(L, "variant");
    luaL_argcheck(L, duration >= 1.0 / RATE && duration <= 30, 1, "duration must be 1 sample to 30 seconds");
    luaL_argcheck(L, variant >= 1 && variant <= 3 && variant == std::floor(variant), 1, "variant must be 1..3");
    uint32_t frames = (uint32_t)std::floor(duration * RATE);
    luaL_argcheck(L, frames > 0, 1, "empty sound");
    int count = kind == SHOT ? 8 : (kind == IMPACT || kind == STEP) ? 4 :
        (kind == MECHANIC || kind == SHELL) ? 1 : 0;
    luaL_argcheck(L, lua_objlen(L, 3) == (size_t)count, 3, "invalid tuning parameter count");
    double parameters[8] = {};
    for (int i = 0; i < count; ++i) {
        lua_rawgeti(L, 3, i + 1);
        luaL_argcheck(L, lua_type(L, -1) == LUA_TNUMBER, 3, "invalid tuning parameter");
        parameters[i] = lua_tonumber(L, -1);
        luaL_argcheck(L, std::isfinite(parameters[i]) && parameters[i] >= 0 && parameters[i] <= 100000, 3, "invalid tuning parameter");
        lua_pop(L, 1);
    }
    luaL_argcheck(L, kind != SHOT || (parameters[2] > 0 && parameters[4] > 0 && parameters[5] > 0), 3, "invalid shot decay");
    luaL_argcheck(L, (kind != IMPACT && kind != STEP) || parameters[2] > 0, 3, "invalid surface decay");
    // All argument checks precede allocation: Lua errors longjmp, so C++
    // stack destructors cannot be relied on for ownership across Lua calls.
    Job** owner = (Job**)lua_newuserdata(L, sizeof(Job*)); *owner = 0;
    luaL_getmetatable(L, META); lua_setmetatable(L, -2);
    Job* job = new Job; *owner = job;
    job->kind = (Kind)kind; job->treatment = (Treatment)treatment;
    job->duration = duration; job->variant = variant; job->frames = frames; job->wind = wind;
    std::memcpy(job->p, parameters, sizeof(parameters));
    double initial = std::fmod(std::floor(seed), MODULUS - 1.0);
    if (initial < 0) initial += MODULUS - 1.0;
    job->random = (uint32_t)initial + 1;
    for (size_t i = 0; i < stream_length; ++i)
        job->random = (uint32_t)(((uint64_t)job->random * 31 + (uint8_t)stream[i]) % MODULUS);
    if (job->random == 0) job->random = 1;
    job->initial_random = job->random;
    // Whole discarded periods prime the filters for continuous loop playback.
    if (job->kind == AMBIENCE) job->warmup = (uint32_t)std::max(1.0, std::ceil(.5 * RATE / frames));
    job->hum_a = std::floor(75.0 * frames / RATE + .5);
    job->hum_b = std::floor(112.0 * frames / RATE + .5);
    job->wav.SetCapacity(44 + frames * 2); job->wav.SetSize(44 + frames * 2);
    uint8_t* bytes = job->wav.Begin();
    std::memcpy(bytes, "RIFF", 4); U32(bytes + 4, 36 + frames * 2);
    std::memcpy(bytes + 8, "WAVEfmt ", 8); U32(bytes + 16, 16);
    U16(bytes + 20, 1); U16(bytes + 22, 1); U32(bytes + 24, RATE);
    U32(bytes + 28, RATE * 2); U16(bytes + 32, 2); U16(bytes + 34, 16);
    std::memcpy(bytes + 36, "data", 4); U32(bytes + 40, frames * 2);
    return 1;
}

static double Sample(Job& j, double t) {
    j.random = (uint32_t)(((uint64_t)j.random * 16807) % MODULUS);
    double noise = ((j.random - 1.0) / (MODULUS - 1.0)) * 2 - 1;
    j.low = j.low + .055 * (noise - j.low);
    j.mid = j.mid + .42 * (noise - j.mid);
    double x = 0, detune = 1 + (j.variant - 2) * .025;
    const double* p = j.p;
    switch (j.kind) {
    case SHOT: {
        double f = p[1] + (p[0] - p[1]) * std::exp(-t / .035);
        j.phase = j.phase + 2 * PI * f * detune / RATE;
        double transient = (noise - j.mid) * .5 * std::exp(-t / .002);
        double body = std::sin(j.phase) * .72 * std::exp(-t / p[2]);
        double crack = (noise - j.low) * std::sin(2 * PI * p[3] * t * detune) * .65 * std::exp(-t / p[4]);
        double tail = j.mid * .55 * std::exp(-t / p[5]);
        double mt = t - p[6];
        double mech = mt >= 0 ? (.12 * std::sin(2 * PI * p[7] * mt) + .07 * noise) * std::exp(-mt / .022) : 0;
        x = transient + body + crack + tail + mech;
        x = x / (1 + std::abs(x) * .7);
        break;
    }
    case IMPACT: case STEP: {
        bool step = j.kind == STEP;
        double f = p[0] * (step ? .48 : 1) * detune;
        double attack = std::min(1.0, t / (step ? .007 : .001));
        double texture = p[1] > 2000 ? noise - j.low : j.mid;
        x = (std::sin(2 * PI * f * t) * .45 * std::exp(-t / .035) + texture * .4 * std::exp(-t / p[2])) * attack;
        if (p[3] > 0) x = x + std::sin(2 * PI * p[3] * t * detune) * .23 * std::exp(-t / (step ? .055 : .12)) * attack;
        if (step) x = x * .75;
        break;
    }
    case MECHANIC: case SHELL: {
        double f = p[0], t2 = t - .044;
        x = (std::sin(2 * PI * f * t) * .3 + noise * .35) * std::exp(-t / .013);
        if (t2 > 0) x = x + std::sin(2 * PI * f * 1.63 * t2) * .18 * std::exp(-t2 / .027);
        break;
    }
    case HURT:
        x = (std::sin(2 * PI * (95 * t - 65 * t * t)) * .55 + j.low * .8) * std::exp(-t / .075);
        break;
    case CLOTH:
        x = j.mid * .7 * std::pow(std::sin(PI * std::min(1.0, t / .32)), 2);
        break;
    case AMBIENCE: {
        double phase = 2 * PI * j.cursor / j.frames;
        double mod = .7 + .3 * std::sin(phase);
        x = j.wind ? (j.low * 1.8 + j.mid * .05) * mod :
            (j.low * .65 + std::sin(phase * j.hum_a) * .035 + std::sin(phase * j.hum_b) * .025) * mod;
        break;
    }
    }
    if (j.treatment == ROOM) {
        double a = j.cursor >= ECHO_A ? j.history[(j.cursor - ECHO_A) % (ECHO_B + 1)] : 0;
        double b = j.cursor >= ECHO_B ? j.history[(j.cursor - ECHO_B) % (ECHO_B + 1)] : 0;
        j.history[j.cursor % (ECHO_B + 1)] = x;
        x = (x + a * .32 + b * .18) * .82;
    } else if (j.treatment == MUFFLED) {
        j.muffle = j.muffle + .10 * (x - j.muffle); x = j.muffle;
    }
    j.dc = j.dc + .002 * (x - j.dc);
    x = x - j.dc;
    if (j.kind != AMBIENCE)
        x = x * std::min(std::min(1.0, t / .0005), (j.frames - 1.0 - j.cursor) / (RATE * .018));
    return std::max(-.92, std::min(.92, x * .9));
}
static void Field(lua_State* L, const char* name, double value) {
    lua_pushnumber(L, value); lua_setfield(L, -2, name);
}
static int Step(lua_State* L) {
    Job* job = Check(L);
    luaL_argcheck(L, !job->finished, 1, "synthesis job is finished");
    double budget = luaL_checknumber(L, 2);
    luaL_argcheck(L, std::isfinite(budget) && budget >= 1 && budget <= 65536 && budget == std::floor(budget), 2, "budget must be 1..65536 samples");
    for (uint32_t i = 0; i < (uint32_t)budget; ++i) {
        double x = Sample(*job, job->cursor / (double)RATE);
        if (job->warmup == 0) {
            job->peak = std::max(job->peak, std::abs(x)); job->square = job->square + x * x;
            int32_t pcm = (int32_t)std::floor(x * 32767 + .5);
            U16(job->wav.Begin() + 44 + job->cursor * 2, (uint16_t)pcm);
        }
        ++job->cursor;
        if (job->cursor == job->frames) {
            if (job->warmup == 0) break;
            --job->warmup; job->cursor = 0;
            job->random = job->initial_random;
        }
    }
    if (job->cursor != job->frames) return 0;
    lua_pushlstring(L, (const char*)job->wav.Begin(), job->wav.Size());
    lua_newtable(L);
    Field(L, "frames", job->frames); Field(L, "duration", job->frames / (double)RATE);
    Field(L, "peak", job->peak); Field(L, "rms", std::sqrt(job->square / job->frames));
    job->finished = true;
    return 2;
}
static int Fingerprint(lua_State* L) {
    size_t size;
    const char* bytes = luaL_checklstring(L, 1, &size);
    luaL_argcheck(L, size <= 0xffffffffu, 1, "sound data is too large");
    // Lua's hash(string) uses a zero-terminated string. WAV data contains
    // embedded zeros, so comparisons must explicitly hash the full length.
    uint64_t value = dmHashBuffer64(bytes, (uint32_t)size);
    char hex[17]; std::snprintf(hex, sizeof(hex), "%016llx", (unsigned long long)value);
    lua_pushstring(L, hex);
    return 1;
}
const luaL_reg METHODS[] = {{"new", New}, {"step", Step}, {"close", Close}, {"fingerprint", Fingerprint}, {0, 0}};
static dmExtension::Result Initialize(dmExtension::Params* params) {
    lua_State* L = params->m_L; int top = lua_gettop(L);
    luaL_newmetatable(L, META); lua_pushcfunction(L, Close); lua_setfield(L, -2, "__gc"); lua_pop(L, 1);
    luaL_register(L, "audiosynth", METHODS); lua_pop(L, 1);
    assert(lua_gettop(L) == top);
    return dmExtension::RESULT_OK;
}
}
DM_DECLARE_EXTENSION(AudioSynth, "AudioSynth", 0, 0, Initialize, 0, 0, 0)
