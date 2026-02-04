#include <sol/sol.hpp>

#include <algorithm>
#include <cstdint>
#include <random>
#include <string>
#include <vector>

namespace {

struct RandomState
{
    std::mt19937_64 engine;
    bool seeded = false;
};

thread_local RandomState random_state;

void seed_from_entropy()
{
    std::random_device rd;
    std::seed_seq seq{rd(), rd(), rd(), rd(), rd(), rd(), rd(), rd()};
    random_state.engine.seed(seq);
    random_state.seeded = true;
}

std::mt19937_64& get_engine()
{
    if (!random_state.seeded) {
        seed_from_entropy();
    }
    return random_state.engine;
}

void random_seed(sol::optional<uint64_t> seed_opt)
{
    if (seed_opt) {
        get_engine().seed(static_cast<std::mt19937_64::result_type>(seed_opt.value()));
        random_state.seeded = true;
        return;
    }

    seed_from_entropy();
}

int64_t random_randint(int64_t a, int64_t b)
{
    if (a > b) {
        throw sol::error("random.randint requires a <= b");
    }

    std::uniform_int_distribution<int64_t> dist(a, b);
    return dist(get_engine());
}

int64_t random_randrange(sol::variadic_args args)
{
    if (args.size() < 1 || args.size() > 3) {
        throw sol::error("random.randrange expects 1 to 3 arguments");
    }

    for (const auto& arg : args) {
        if (!arg.is<int64_t>()) {
            throw sol::error("random.randrange expects integer arguments");
        }
    }

    int64_t start = 0;
    int64_t stop = 0;
    int64_t step = 1;

    if (args.size() == 1) {
        stop = args[0].as<int64_t>();
    } else if (args.size() == 2) {
        start = args[0].as<int64_t>();
        stop = args[1].as<int64_t>();
    } else {
        start = args[0].as<int64_t>();
        stop = args[1].as<int64_t>();
        step = args[2].as<int64_t>();
    }

    if (step == 0) {
        throw sol::error("random.randrange step must not be 0");
    }

    int64_t span = stop - start;
    if ((span > 0 && step < 0) || (span < 0 && step > 0) || span == 0) {
        throw sol::error("random.randrange empty range");
    }

    int64_t count = 0;
    if (step > 0) {
        count = (span + step - 1) / step;
    } else {
        int64_t neg_step = -step;
        int64_t neg_span = -span;
        count = (neg_span + neg_step - 1) / neg_step;
    }

    if (count <= 0) {
        throw sol::error("random.randrange empty range");
    }

    std::uniform_int_distribution<int64_t> dist(0, count - 1);
    int64_t offset = dist(get_engine());
    return start + offset * step;
}

double random_random()
{
    std::uniform_real_distribution<double> dist(0.0, 1.0);
    return dist(get_engine());
}

double random_uniform(double a, double b)
{
    double u = random_random();
    return a + (b - a) * u;
}

std::string random_randbytes(int64_t n)
{
    if (n < 0) {
        throw sol::error("random.randbytes requires n >= 0");
    }

    std::string out;
    out.resize(static_cast<size_t>(n));
    uint64_t remaining = static_cast<uint64_t>(n);
    size_t offset = 0;

    while (remaining > 0) {
        uint64_t value = get_engine()();
        for (int i = 0; i < 8 && remaining > 0; i++) {
            out[offset] = static_cast<char>(value & 0xFF);
            value >>= 8;
            offset++;
            remaining--;
        }
    }

    return out;
}

std::string bytes_to_hex(const std::string& bytes)
{
    static const char* digits = "0123456789abcdef";
    std::string out;
    out.resize(bytes.size() * 2);
    size_t out_i = 0;
    for (unsigned char c : bytes) {
        out[out_i++] = digits[(c >> 4) & 0x0F];
        out[out_i++] = digits[c & 0x0F];
    }
    return out;
}

std::string random_randbytes_hex(int64_t n)
{
    if (n < 0) {
        throw sol::error("random.randbytes-hex requires n >= 0");
    }

    return bytes_to_hex(random_randbytes(n));
}

sol::object random_choice(sol::table seq, sol::this_state ts)
{
    sol::state_view lua(ts);
    size_t count = seq.size();
    if (count == 0) {
        throw sol::error("random.choice requires a non-empty sequence");
    }

    std::uniform_int_distribution<int64_t> dist(1, static_cast<int64_t>(count));
    int64_t index = dist(get_engine());
    return seq.get<sol::object>(index);
}

sol::table random_shuffle(sol::table seq)
{
    size_t count = seq.size();
    if (count <= 1) {
        return seq;
    }

    for (size_t i = count; i >= 2; i--) {
        std::uniform_int_distribution<int64_t> dist(1, static_cast<int64_t>(i));
        int64_t j = dist(get_engine());
        sol::object a = seq.get<sol::object>(static_cast<int64_t>(i));
        sol::object b = seq.get<sol::object>(j);
        seq.set(static_cast<int64_t>(i), b);
        seq.set(j, a);
    }

    return seq;
}

sol::table random_sample(sol::table seq, int64_t k, sol::this_state ts)
{
    sol::state_view lua(ts);
    size_t count = seq.size();
    if (k < 0) {
        throw sol::error("random.sample requires k >= 0");
    }
    if (static_cast<size_t>(k) > count) {
        throw sol::error("random.sample requires k <= len(seq)");
    }

    std::vector<int64_t> indices;
    indices.reserve(count);
    for (size_t i = 1; i <= count; i++) {
        indices.push_back(static_cast<int64_t>(i));
    }

    for (int64_t i = 0; i < k; i++) {
        std::uniform_int_distribution<int64_t> dist(i, static_cast<int64_t>(count - 1));
        int64_t j = dist(get_engine());
        std::swap(indices[static_cast<size_t>(i)], indices[static_cast<size_t>(j)]);
    }

    sol::table out = lua.create_table();
    for (int64_t i = 0; i < k; i++) {
        out[i + 1] = seq.get<sol::object>(indices[static_cast<size_t>(i)]);
    }

    return out;
}

sol::table create_random_table(sol::state_view lua)
{
    sol::table random_table = lua.create_table();
    random_table.set_function("seed", &random_seed);
    random_table.set_function("randint", &random_randint);
    random_table.set_function("randrange", &random_randrange);
    random_table.set_function("random", &random_random);
    random_table.set_function("uniform", &random_uniform);
    random_table.set_function("randbytes", &random_randbytes);
    random_table.set_function("randbytes-hex", &random_randbytes_hex);
    random_table.set_function("choice", &random_choice);
    random_table.set_function("shuffle", &random_shuffle);
    random_table.set_function("sample", &random_sample);
    return random_table;
}

} // namespace

void lua_bind_random(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("random", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_random_table(lua);
    });
}
