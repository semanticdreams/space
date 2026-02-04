// Inspired from http://www.drdobbs.com/cpp/logging-in-c/201804215
// and https://github.com/zuhd-org/easyloggingpp

#ifndef LOG_H
#define LOG_H

#include <atomic>
#include <sstream>
#include <type_traits>
#include <vector>
#include <string>

#define GL_LOG_FILE "gl.log"

enum LogLevel {
    Error,
    Warning,
    Info,
    Debug
};

struct LogConfig {
    LogLevel reporting_level = Info;
    bool restart = false;
};

struct LogField {
    std::string formatted;
};

extern LogConfig LOG_CONFIG;

void log_init(const LogConfig& config);
void log_shutdown();
void log_set_level(LogLevel level);
void log_set_level_for(const std::string& name, LogLevel level);
bool log_should_log(const std::string& name, LogLevel level);
void log_write(LogLevel level, const std::string& message);
void log_write_named(const std::string& name, LogLevel level, const std::string& message);
void log_write_named_fields(const std::string& name, LogLevel level, const std::string& fields, const std::string& message);
void log_flush();
void log_set_frame_id_provider(const std::atomic<uint64_t>* provider);
void log_set_output_path(const std::string& path);
LogField log_kv_string(const std::string& key, const std::string& value, bool quote_value);
LogField log_kv(const std::string& key, const std::string& value);
LogField log_kv(const std::string& key, const char* value);

template<typename T, typename std::enable_if_t<std::is_arithmetic<T>::value, int> = 0>
LogField log_kv(const std::string& key, T value)
{
    return log_kv_string(key, std::to_string(value), false);
}

// General purpose logging class
// Logs in standard output and in a file, configured
// with the GL_LOG_FILE macro.
// Usage : LOG(MessageLevel) << "Message"
class Log {
public:
    explicit Log(const std::string& logger_name = "space");

    virtual ~Log();

    Log& get(LogLevel level = Info);

    Log& operator<<(const LogField& field);

    template<typename T>
    Log& operator<<(const T& value)
    {
        if (!enabled) {
            return *this;
        }
        os << value;
        return *this;
    }

    static void restart();

private:
    std::ostringstream os;
    std::string name;
    LogLevel level = Info;
    bool enabled = true;
    std::vector<std::string> fields;

    Log(const Log&);

    Log& operator=(const Log&);
};

#ifndef LOG_SUBSYSTEM
#define LOG_SUBSYSTEM "space"
#endif

#define LOG(level)                                \
    if (!log_should_log(LOG_SUBSYSTEM, level))    \
        ;                                         \
    else                                          \
        Log(LOG_SUBSYSTEM).get(level)

#define LOG_NAMED(name, level)                    \
    if (!log_should_log(name, level))             \
        ;                                         \
    else                                          \
        Log(name).get(level)

#endif

#define GL_CHECK_ERROR() \
    do { \
        GLenum err; \
        while ((err = glGetError()) != GL_NO_ERROR) { \
            LOG(Error) << "OpenGL error " << err << " at " << __FILE__ << ":" << __LINE__; \
        } \
    } while (0)
