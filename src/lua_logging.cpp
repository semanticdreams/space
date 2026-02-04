#include "lua_logging.h"

#include <sstream>

#include "log.h"

namespace {

std::string format_args(sol::this_state ts, sol::variadic_args args, std::size_t start_index)
{
    if (args.size() <= start_index) {
        return "";
    }

    sol::state_view lua(ts);
    sol::function tostring = lua["tostring"];
    std::ostringstream out;
    bool first = true;
    std::size_t index = 0;

    for (auto arg : args) {
        if (index++ < start_index) {
            continue;
        }
        sol::object obj = arg;
        sol::object string_obj = tostring(obj);
        if (!string_obj.is<std::string>()) {
            continue;
        }
        if (!first) {
            out << " ";
        }
        out << string_obj.as<std::string>();
        first = false;
    }

    return out.str();
}

std::string format_fields(sol::object fields_obj)
{
    if (!fields_obj.is<sol::table>()) {
        return "";
    }
    sol::table fields = fields_obj.as<sol::table>();
    std::string out;
    for (auto& item : fields) {
        sol::object key_obj = item.first;
        sol::object value_obj = item.second;
        if (!key_obj.is<std::string>()) {
            continue;
        }
        std::string key = key_obj.as<std::string>();
        if (value_obj.is<std::string>()) {
            LogField field = log_kv_string(key, value_obj.as<std::string>(), false);
            if (!out.empty()) {
                out.push_back(' ');
            }
            out.append(field.formatted);
        } else if (value_obj.is<double>()) {
            LogField field = log_kv_string(key, std::to_string(value_obj.as<double>()), false);
            if (!out.empty()) {
                out.push_back(' ');
            }
            out.append(field.formatted);
        } else if (value_obj.is<bool>()) {
            LogField field = log_kv_string(key, value_obj.as<bool>() ? "true" : "false", false);
            if (!out.empty()) {
                out.push_back(' ');
            }
            out.append(field.formatted);
        } else if (value_obj.is<sol::lua_nil_t>()) {
            continue;
        } else {
            sol::state_view lua(fields_obj.lua_state());
            sol::function tostring = lua["tostring"];
            sol::object string_obj = tostring(value_obj);
            if (string_obj.is<std::string>()) {
                LogField field = log_kv_string(key, string_obj.as<std::string>(), false);
                if (!out.empty()) {
                    out.push_back(' ');
                }
                out.append(field.formatted);
            }
        }
    }
    return out;
}

void log_with_level(LogLevel level, sol::this_state ts, sol::variadic_args args)
{
    std::size_t start_index = 0;
    std::string fields;
    if (args.size() > 0 && args.begin()->is<sol::table>()) {
        fields = format_fields(args.begin()->get<sol::object>());
        start_index = 1;
    }
    std::string message = format_args(ts, args, start_index);
    if (message.empty() && fields.empty()) {
        return;
    }
    log_write_named_fields("space", level, fields, message);
}

void log_with_named_level(const std::string& name, LogLevel level, sol::this_state ts, sol::variadic_args args)
{
    std::size_t start_index = 0;
    std::string fields;
    if (args.size() > 0 && args.begin()->is<sol::table>()) {
        fields = format_fields(args.begin()->get<sol::object>());
        start_index = 1;
    }
    std::string message = format_args(ts, args, start_index);
    if (message.empty() && fields.empty()) {
        return;
    }
    log_write_named_fields(name, level, fields, message);
}

bool parse_level(const std::string& level, LogLevel& parsed)
{
    if (level == "debug") {
        parsed = Debug;
    } else if (level == "info") {
        parsed = Info;
    } else if (level == "warn" || level == "warning") {
        parsed = Warning;
    } else if (level == "error") {
        parsed = Error;
    } else {
        return false;
    }
    return true;
}

bool set_level_from_string(const std::string& level)
{
    LogLevel parsed = Info;
    if (!parse_level(level, parsed)) {
        return false;
    }
    log_set_level(parsed);
    return true;
}

bool set_level_for_logger(const std::string& name, const std::string& level)
{
    LogLevel parsed = Info;
    if (!parse_level(level, parsed)) {
        return false;
    }
    log_set_level_for(name, parsed);
    return true;
}

LogConfig parse_config(sol::object options)
{
    LogConfig config;
    if (!options.is<sol::table>()) {
        return config;
    }
    sol::table table = options.as<sol::table>();
    sol::object path_obj = table["path"];
    if (path_obj.is<std::string>()) {
        log_set_output_path(path_obj.as<std::string>());
    }
    sol::object restart_obj = table["restart"];
    if (restart_obj.is<bool>()) {
        config.restart = restart_obj.as<bool>();
    }
    sol::object level_obj = table["level"];
    if (level_obj.is<std::string>()) {
        LogLevel parsed = Info;
        if (parse_level(level_obj.as<std::string>(), parsed)) {
            config.reporting_level = parsed;
        }
    }
    return config;
}

sol::table create_logger_table(sol::this_state state, const std::string& name)
{
    sol::state_view lua_view(state);
    sol::table table = lua_view.create_table();
    table["name"] = name;
    table.set_function("debug", [name](sol::this_state ts, sol::variadic_args args) {
        log_with_named_level(name, Debug, ts, args);
    });
    table.set_function("info", [name](sol::this_state ts, sol::variadic_args args) {
        log_with_named_level(name, Info, ts, args);
    });
    table.set_function("warn", [name](sol::this_state ts, sol::variadic_args args) {
        log_with_named_level(name, Warning, ts, args);
    });
    table.set_function("error", [name](sol::this_state ts, sol::variadic_args args) {
        log_with_named_level(name, Error, ts, args);
    });
    table.set_function("set-level", [name](const std::string& level) {
        return set_level_for_logger(name, level);
    });
    table.set_function("flush", []() {
        log_flush();
    });
    return table;
}

} // namespace

void lua_bind_logging(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("logging", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table logging_table = lua_view.create_table();

        logging_table.set_function("debug", [](sol::this_state ts, sol::variadic_args args) {
            log_with_level(Debug, ts, args);
        });
        logging_table.set_function("info", [](sol::this_state ts, sol::variadic_args args) {
            log_with_level(Info, ts, args);
        });
        logging_table.set_function("warn", [](sol::this_state ts, sol::variadic_args args) {
            log_with_level(Warning, ts, args);
        });
        logging_table.set_function("error", [](sol::this_state ts, sol::variadic_args args) {
            log_with_level(Error, ts, args);
        });
        logging_table.set_function("set-level", sol::overload(
            &set_level_from_string,
            &set_level_for_logger
        ));
        logging_table.set_function("get", [](sol::this_state ts, const std::string& name) {
            return create_logger_table(ts, name);
        });
        logging_table.set_function("init", [](sol::object options) {
            log_init(parse_config(options));
        });
        logging_table.set_function("shutdown", &log_shutdown);
        logging_table.set_function("flush", &log_flush);

        return logging_table;
    });
}
