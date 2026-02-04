#include "log.h"

#include <atomic>
#include <cctype>
#include <mutex>

#include <spdlog/async.h>
#include <spdlog/fmt/fmt.h>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>

namespace {

std::mutex log_mutex;
std::shared_ptr<spdlog::logger> async_logger;
std::vector<spdlog::sink_ptr> log_sinks;
bool log_ready = false;
std::atomic<const std::atomic<uint64_t>*> frame_id_provider { nullptr };
std::string log_output_path = std::string(GL_LOG_FILE);

spdlog::level::level_enum to_spd_level(LogLevel level)
{
    switch (level) {
        case Debug:
            return spdlog::level::debug;
        case Info:
            return spdlog::level::info;
        case Warning:
            return spdlog::level::warn;
        case Error:
            return spdlog::level::err;
    }
    return spdlog::level::info;
}

void ensure_logger()
{
    if (!log_ready) {
        LogConfig config;
        log_init(config);
    }
}

std::string escape_value(const std::string& value)
{
    std::string escaped;
    escaped.reserve(value.size());
    for (char ch : value) {
        if (ch == '\\' || ch == '"') {
            escaped.push_back('\\');
            escaped.push_back(ch);
        } else if (ch == '\n') {
            escaped.append("\\n");
        } else if (ch == '\r') {
            escaped.append("\\r");
        } else if (ch == '\t') {
            escaped.append("\\t");
        } else {
            escaped.push_back(ch);
        }
    }
    return escaped;
}

bool needs_quotes(const std::string& value)
{
    for (char ch : value) {
        if (std::isspace(static_cast<unsigned char>(ch)) || ch == '"' || ch == '\\') {
            return true;
        }
    }
    return value.empty();
}

std::string format_kv(const std::string& key, const std::string& value, bool quote)
{
    std::string out = key;
    out.push_back('=');
    if (quote || needs_quotes(value)) {
        out.push_back('"');
        out.append(escape_value(value));
        out.push_back('"');
    } else {
        out.append(value);
    }
    return out;
}

std::string build_payload(const std::string& fields, const std::string& message)
{
    if (fields.empty()) {
        return message;
    }
    std::string payload = fields;
    payload.push_back('\n');
    payload.append(message);
    return payload;
}

struct PayloadParts {
    std::string_view fields;
    std::string_view message;
};

std::string_view extract_fields(std::string_view payload, std::string_view& out_message)
{
    std::size_t sep = payload.find('\n');
    if (sep == std::string_view::npos) {
        out_message = payload;
        return {};
    }
    out_message = payload.substr(sep + 1);
    return payload.substr(0, sep);
}

PayloadParts split_payload(const spdlog::details::log_msg& msg)
{
    std::string_view payload_view(msg.payload.data(), msg.payload.size());
    std::string_view message_view;
    std::string_view fields_view = extract_fields(payload_view, message_view);
    return { fields_view, message_view };
}

void append_prefix_and_fields(const spdlog::details::log_msg& msg,
                              spdlog::memory_buf_t& dest,
                              std::string_view fields_view)
{
    using namespace std::chrono;
    const auto time = msg.time;
    const auto tt = spdlog::log_clock::to_time_t(time);
    std::tm tm = spdlog::details::os::gmtime(tt);
    auto ms = duration_cast<milliseconds>(time.time_since_epoch()) % 1000;

    fmt::format_to(std::back_inserter(dest),
                   "ts={:04d}-{:02d}-{:02d}T{:02d}:{:02d}:{:02d}.{:03d}Z ",
                   tm.tm_year + 1900,
                   tm.tm_mon + 1,
                   tm.tm_mday,
                   tm.tm_hour,
                   tm.tm_min,
                   tm.tm_sec,
                   static_cast<int>(ms.count()));

    auto level_view = spdlog::level::to_string_view(msg.level);
    std::string level(level_view.data(), level_view.size());
    for (char& ch : level) {
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    fmt::format_to(std::back_inserter(dest),
                   "level={} logger={} thread={} ",
                   level,
                   msg.logger_name,
                   msg.thread_id);

    const auto* provider = frame_id_provider.load(std::memory_order_relaxed);
    if (provider) {
        uint64_t value = provider->load(std::memory_order_relaxed);
        fmt::format_to(std::back_inserter(dest), "frame={} ", value);
    } else {
        fmt::format_to(std::back_inserter(dest), "frame=- ");
    }

    if (!fields_view.empty()) {
        fmt::format_to(std::back_inserter(dest), "{} ", fields_view);
    }
}

class KeyValueFormatter : public spdlog::formatter {
public:
    void format(const spdlog::details::log_msg& msg, spdlog::memory_buf_t& dest) override
    {
        PayloadParts parts = split_payload(msg);
        append_prefix_and_fields(msg, dest, parts.fields);

        std::string message(parts.message);
        fmt::format_to(std::back_inserter(dest), "msg=\"{}\"\n", escape_value(message));
    }

    std::unique_ptr<spdlog::formatter> clone() const override
    {
        return spdlog::details::make_unique<KeyValueFormatter>();
    }
};

class ColorKeyValueFormatter : public spdlog::formatter {
public:
    void format(const spdlog::details::log_msg& msg, spdlog::memory_buf_t& dest) override
    {
        PayloadParts parts = split_payload(msg);
        append_prefix_and_fields(msg, dest, parts.fields);

        fmt::format_to(std::back_inserter(dest), "msg=\"");
        size_t color_start = dest.size();

        std::string message(parts.message);
        fmt::format_to(std::back_inserter(dest), "{}", escape_value(message));
        size_t color_end = dest.size();

        fmt::format_to(std::back_inserter(dest), "\"\n");

        auto& mutable_msg = const_cast<spdlog::details::log_msg&>(msg);
        mutable_msg.color_range_start = color_start;
        mutable_msg.color_range_end = color_end;
    }

    std::unique_ptr<spdlog::formatter> clone() const override
    {
        return spdlog::details::make_unique<ColorKeyValueFormatter>();
    }
};

} // namespace

std::shared_ptr<spdlog::logger> log_get_logger(const std::string& name)
{
    ensure_logger();

    if (auto existing = spdlog::get(name)) {
        return existing;
    }

    auto logger = std::make_shared<spdlog::async_logger>(
        name,
        log_sinks.begin(),
        log_sinks.end(),
        spdlog::thread_pool(),
        spdlog::async_overflow_policy::block
    );
    logger->set_level(to_spd_level(LOG_CONFIG.reporting_level));
    spdlog::register_logger(logger);
    return logger;
}

void log_init(const LogConfig& config)
{
    std::lock_guard<std::mutex> lock(log_mutex);
    spdlog::shutdown();

    auto stdout_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
    stdout_sink->set_formatter(std::make_unique<ColorKeyValueFormatter>());
    auto file_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
        log_output_path,
        5 * 1024 * 1024,
        3
    );
    file_sink->set_formatter(std::make_unique<KeyValueFormatter>());
    log_sinks.clear();
    log_sinks.push_back(stdout_sink);
    log_sinks.push_back(file_sink);

    spdlog::init_thread_pool(8192, 1);
    LOG_CONFIG.reporting_level = config.reporting_level;
    log_ready = true;

    static const std::vector<std::string> default_loggers = {
        "space",
        "engine",
        "window",
        "shader",
        "resources",
        "opengl",
        "audio",
        "physics",
        "lua",
        "jobs",
        "http",
        "input",
        "render"
    };

    for (const auto& name : default_loggers) {
        auto logger = log_get_logger(name);
        logger->set_level(to_spd_level(config.reporting_level));
    }
    log_set_level_for("shader", Warning);

    async_logger = log_get_logger("space");
    async_logger->flush_on(spdlog::level::warn);
    spdlog::set_default_logger(async_logger);
}

void log_shutdown()
{
    std::lock_guard<std::mutex> lock(log_mutex);
    spdlog::shutdown();
    async_logger.reset();
    log_sinks.clear();
    log_ready = false;
}

void log_set_level(LogLevel level)
{
    LOG_CONFIG.reporting_level = level;
    log_set_level_for("space", level);
}

void log_set_level_for(const std::string& name, LogLevel level)
{
    auto logger = log_get_logger(name);
    logger->set_level(to_spd_level(level));
}

bool log_should_log(const std::string& name, LogLevel level)
{
    auto logger = log_get_logger(name);
    return logger->should_log(to_spd_level(level));
}

void log_write(LogLevel level, const std::string& message)
{
    log_write_named_fields("space", level, "", message);
}

void log_write_named(const std::string& name, LogLevel level, const std::string& message)
{
    log_write_named_fields(name, level, "", message);
}

void log_write_named_fields(const std::string& name, LogLevel level, const std::string& fields, const std::string& message)
{
    auto logger = log_get_logger(name);
    logger->log(to_spd_level(level), build_payload(fields, message));
}

void log_flush()
{
    auto logger = log_get_logger("space");
    logger->flush();
}

void log_set_frame_id_provider(const std::atomic<uint64_t>* provider)
{
    frame_id_provider.store(provider, std::memory_order_relaxed);
}

void log_set_output_path(const std::string& path)
{
    log_output_path = path.empty() ? std::string(GL_LOG_FILE) : path;
    LogConfig config = LOG_CONFIG;
    config.restart = false;
    log_init(config);
}

Log::Log(const std::string& logger_name)
    : name(logger_name)
{
}

Log::~Log()
{
    if (!enabled || (os.str().empty() && fields.empty())) {
        return;
    }
    std::string field_blob;
    for (const auto& field : fields) {
        if (!field_blob.empty()) {
            field_blob.push_back(' ');
        }
        field_blob.append(field);
    }
    log_write_named_fields(name, level, field_blob, os.str());
    os.str("");
    os.clear();
}

void Log::restart()
{
    LogConfig config = LOG_CONFIG;
    config.restart = true;
    log_init(config);
}

Log& Log::get(LogLevel new_level)
{
    level = new_level;
    enabled = log_should_log(name, new_level);
    return *this;
}

Log& Log::operator<<(const LogField& field)
{
    if (!enabled) {
        return *this;
    }
    fields.push_back(field.formatted);
    return *this;
}

LogField log_kv_string(const std::string& key, const std::string& value, bool quote_value)
{
    return { format_kv(key, value, quote_value) };
}

LogField log_kv(const std::string& key, const std::string& value)
{
    return log_kv_string(key, value, false);
}

LogField log_kv(const std::string& key, const char* value)
{
    return log_kv_string(key, value ? std::string(value) : std::string(), false);
}
