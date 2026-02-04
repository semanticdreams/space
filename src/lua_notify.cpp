#include "lua_notify.h"

#include <algorithm>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#if defined(NOTIFY_LIBNOTIFY)
#include <libnotify/notify.h>
#endif

namespace {

#if defined(NOTIFY_LIBNOTIFY)

struct ActionRef {
    sol::function fn;
};

struct ClosedRef {
    sol::function fn;
};

struct ManagedNotification {
    NotifyNotification* handle { nullptr };
    std::string replace_key {};
};

#endif

class NotificationCenter {
public:
    NotificationCenter() = default;
    NotificationCenter(const NotificationCenter&) = delete;
    NotificationCenter& operator=(const NotificationCenter&) = delete;
    NotificationCenter(NotificationCenter&&) noexcept = default;
    NotificationCenter& operator=(NotificationCenter&&) noexcept = default;
    ~NotificationCenter()
    {
        reset();
    }

    bool send(const std::string& summary, const sol::optional<std::string>& body,
        const sol::optional<std::string>& icon, const sol::optional<sol::object>& options_obj)
    {
        if (summary.empty()) {
            last_error = "notification summary must be non-empty";
            return false;
        }
#if defined(NOTIFY_LIBNOTIFY)
        ParsedOptions options {};
        if (!parse_options(options_obj, options)) {
            return false;
        }

        if (!ensure_init()) {
            return false;
        }

        ManagedNotification* managed = get_or_create(options.replace_key, summary, body, icon);
        if (managed == nullptr) {
            return false;
        }

        apply_options(*managed, options);

        GError* error = nullptr;
        const gboolean ok = notify_notification_show(managed->handle, &error);
        if (error != nullptr) {
            last_error = error->message ? error->message : "notify_notification_show failed";
            g_error_free(error);
            return false;
        }
        if (!ok) {
            last_error = "notify_notification_show returned false";
            return false;
        }

        last_error.clear();
        return true;
#elif defined(NOTIFY_BACKEND_NONE)
        last_error = get_compile_reason();
        return false;
#else
        last_error = "notification backend not selected during build";
        return false;
#endif
    }

    void set_app_name(const std::string& name)
    {
        if (name.empty()) {
            last_error = "app-name must be non-empty";
            return;
        }

        app_name = name;
#if defined(NOTIFY_LIBNOTIFY)
        if (initialized) {
            notify_set_app_name(app_name.c_str());
        }
#endif
    }

    std::string get_compile_reason() const
    {
#ifdef NOTIFY_BACKEND_REASON
        return std::string { NOTIFY_BACKEND_REASON };
#else
        return "";
#endif
    }

    std::string backend_name() const
    {
#ifdef NOTIFY_BACKEND_NAME
        return std::string { NOTIFY_BACKEND_NAME };
#else
        return "unknown";
#endif
    }

    std::string last_error {};

private:
#if defined(NOTIFY_LIBNOTIFY)
    struct ActionSpec {
        std::string id;
        std::string label;
        sol::function cb;
    };

    struct ParsedOptions {
        std::optional<int> timeout_ms;
        std::optional<NotifyUrgency> urgency;
        std::optional<std::string> category;
        std::optional<std::string> app_name;
        std::optional<std::string> replace_key;
        std::optional<std::string> desktop_entry;
        std::optional<std::string> synchronous_key;
        std::optional<bool> resident;
        std::optional<bool> transient;
        std::optional<bool> suppress_sound;
        std::optional<std::string> sound_file;
        std::vector<ActionSpec> actions;
        sol::optional<sol::function> on_close;
        std::vector<std::pair<std::string, sol::object>> hints;
    };

    static NotifyUrgency parse_urgency(const sol::object& obj, bool& ok_out)
    {
        ok_out = true;
        if (obj.is<std::string>()) {
            const std::string raw = obj.as<std::string>();
            std::string lower = raw;
            std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
            if (lower == "low") {
                return NOTIFY_URGENCY_LOW;
            }
            if (lower == "normal") {
                return NOTIFY_URGENCY_NORMAL;
            }
            if (lower == "critical") {
                return NOTIFY_URGENCY_CRITICAL;
            }
            ok_out = false;
            return NOTIFY_URGENCY_NORMAL;
        }
        if (obj.is<int>()) {
            int val = obj.as<int>();
            switch (val) {
            case NOTIFY_URGENCY_LOW:
            case NOTIFY_URGENCY_NORMAL:
            case NOTIFY_URGENCY_CRITICAL:
                return static_cast<NotifyUrgency>(val);
            default:
                ok_out = false;
                return NOTIFY_URGENCY_NORMAL;
            }
        }
        ok_out = false;
        return NOTIFY_URGENCY_NORMAL;
    }

    bool parse_options(const sol::optional<sol::object>& options_obj, ParsedOptions& out)
    {
        if (!options_obj) {
            return true;
        }
        sol::object obj = *options_obj;
        if (obj.is<int>()) {
            int timeout = obj.as<int>();
            if (timeout < NOTIFY_EXPIRES_DEFAULT) {
                last_error = "notification timeout must be >= -1";
                return false;
            }
            out.timeout_ms = timeout;
            return true;
        }
        if (!obj.is<sol::table>()) {
            last_error = "notification options must be a table or timeout integer";
            return false;
        }

        sol::table tbl = obj.as<sol::table>();

        const sol::object timeout_obj = tbl["timeout-ms"];
        if (timeout_obj.valid()) {
            if (!timeout_obj.is<int>()) {
                last_error = "timeout-ms must be an integer";
                return false;
            }
            int timeout = timeout_obj.as<int>();
            if (timeout < NOTIFY_EXPIRES_DEFAULT) {
                last_error = "timeout-ms must be >= -1";
                return false;
            }
            out.timeout_ms = timeout;
        }

        const sol::object urgency_obj = tbl["urgency"];
        if (urgency_obj.valid()) {
            bool ok = false;
            NotifyUrgency parsed = parse_urgency(urgency_obj, ok);
            if (!ok) {
                last_error = "urgency must be low|normal|critical or 0|1|2";
                return false;
            }
            out.urgency = parsed;
        }

        const sol::object category_obj = tbl["category"];
        if (category_obj.is<std::string>()) {
            out.category = category_obj.as<std::string>();
        } else if (category_obj.valid()) {
            last_error = "category must be a string";
            return false;
        }

        const sol::object app_name_obj = tbl["app-name"];
        if (app_name_obj.is<std::string>()) {
            out.app_name = app_name_obj.as<std::string>();
        } else if (app_name_obj.valid()) {
            last_error = "app-name must be a string";
            return false;
        }

        const sol::object replace_obj = tbl["replace-key"];
        if (replace_obj.is<std::string>()) {
            out.replace_key = replace_obj.as<std::string>();
        } else if (replace_obj.valid()) {
            last_error = "replace-key must be a string";
            return false;
        }

        const sol::object desktop_obj = tbl["desktop-entry"];
        if (desktop_obj.is<std::string>()) {
            out.desktop_entry = desktop_obj.as<std::string>();
        } else if (desktop_obj.valid()) {
            last_error = "desktop-entry must be a string";
            return false;
        }

        const sol::object synchronous_obj = tbl["synchronous"];
        if (synchronous_obj.is<std::string>()) {
            out.synchronous_key = synchronous_obj.as<std::string>();
        } else if (synchronous_obj.valid()) {
            last_error = "synchronous must be a string";
            return false;
        }

        const sol::object resident_obj = tbl["resident"];
        if (resident_obj.valid()) {
            if (!resident_obj.is<bool>()) {
                last_error = "resident must be a boolean";
                return false;
            }
            out.resident = resident_obj.as<bool>();
        }

        const sol::object transient_obj = tbl["transient"];
        if (transient_obj.valid()) {
            if (!transient_obj.is<bool>()) {
                last_error = "transient must be a boolean";
                return false;
            }
            out.transient = transient_obj.as<bool>();
        }

        const sol::object suppress_obj = tbl["suppress-sound"];
        if (suppress_obj.valid()) {
            if (!suppress_obj.is<bool>()) {
                last_error = "suppress-sound must be a boolean";
                return false;
            }
            out.suppress_sound = suppress_obj.as<bool>();
        }

        const sol::object sound_obj = tbl["sound-file"];
        if (sound_obj.is<std::string>()) {
            out.sound_file = sound_obj.as<std::string>();
        } else if (sound_obj.valid()) {
            last_error = "sound-file must be a string";
            return false;
        }

        const sol::object close_obj = tbl["on-close"];
        if (close_obj.valid()) {
            if (!close_obj.is<sol::function>()) {
                last_error = "on-close must be a function";
                return false;
            }
            out.on_close = close_obj.as<sol::function>();
        }

        const sol::object actions_obj = tbl["actions"];
        if (actions_obj.valid()) {
            if (!actions_obj.is<sol::table>()) {
                last_error = "actions must be a table";
                return false;
            }
            sol::table actions_tbl = actions_obj.as<sol::table>();
            for (std::size_t i = 1; i <= actions_tbl.size(); ++i) {
                sol::object entry_obj = actions_tbl[i];
                if (!entry_obj.is<sol::table>()) {
                    last_error = "each action must be a table";
                    return false;
                }
                sol::table entry = entry_obj.as<sol::table>();
                sol::object id_obj = entry["id"];
                if (!id_obj.valid()) {
                    id_obj = entry["action"];
                }
                sol::object label_obj = entry["label"];
                if (!id_obj.is<std::string>() || !label_obj.is<std::string>()) {
                    last_error = "action entries require string id and label";
                    return false;
                }
                sol::object cb_obj = entry["cb"];
                if (cb_obj.valid() && !cb_obj.is<sol::function>()) {
                    last_error = "action cb must be a function";
                    return false;
                }
                ActionSpec spec {
                    id_obj.as<std::string>(),
                    label_obj.as<std::string>(),
                    cb_obj.valid() ? cb_obj.as<sol::function>() : sol::function {}
                };
                out.actions.push_back(std::move(spec));
            }
        }

        const sol::object hints_obj = tbl["hints"];
        if (hints_obj.valid()) {
            if (!hints_obj.is<sol::table>()) {
                last_error = "hints must be a table";
                return false;
            }
            sol::table hints_tbl = hints_obj.as<sol::table>();
            for (const auto& kv : hints_tbl) {
                sol::object key_obj = kv.first;
                sol::object value_obj = kv.second;
                if (!key_obj.is<std::string>()) {
                    last_error = "hint keys must be strings";
                    return false;
                }
                out.hints.emplace_back(key_obj.as<std::string>(), value_obj);
            }
        }

        return true;
    }

    ManagedNotification* create_notification(const std::optional<std::string>& replace_key,
        const std::string& summary, const sol::optional<std::string>& body,
        const sol::optional<std::string>& icon)
    {
        NotifyNotification* handle = notify_notification_new(summary.c_str(),
            body ? body->c_str() : nullptr,
            icon ? icon->c_str() : nullptr);
        if (handle == nullptr) {
            last_error = "notify_notification_new returned null";
            return nullptr;
        }

        g_object_ref(G_OBJECT(handle));

        auto managed = std::make_unique<ManagedNotification>();
        managed->handle = handle;
        managed->replace_key = replace_key.value_or(std::string {});
        ManagedNotification* ptr = managed.get();
        notifications_.push_back(std::move(managed));
        if (replace_key && !replace_key->empty()) {
            replace_index_[*replace_key] = ptr;
        }

        return ptr;
    }

    ManagedNotification* get_or_create(const std::optional<std::string>& replace_key,
        const std::string& summary, const sol::optional<std::string>& body,
        const sol::optional<std::string>& icon)
    {
        ManagedNotification* managed = nullptr;
        if (replace_key && !replace_key->empty()) {
            auto it = replace_index_.find(*replace_key);
            if (it != replace_index_.end()) {
                managed = it->second;
                const gboolean ok = notify_notification_update(managed->handle,
                    summary.c_str(),
                    body ? body->c_str() : nullptr,
                    icon ? icon->c_str() : nullptr);
                if (!ok) {
                    last_error = "notify_notification_update failed";
                    return nullptr;
                }
            }
        }

        if (managed == nullptr) {
            managed = create_notification(replace_key, summary, body, icon);
        }

        return managed;
    }

    static void action_callback(NotifyNotification*, char* action, gpointer user_data)
    {
        auto* ref = reinterpret_cast<ActionRef*>(user_data);
        if (ref == nullptr) {
            return;
        }
        if (ref->fn.valid()) {
            ref->fn(action ? std::string { action } : std::string {});
        }
    }

    static void action_ref_free(gpointer data)
    {
        auto* ref = reinterpret_cast<ActionRef*>(data);
        delete ref;
    }

    void apply_actions(ManagedNotification& managed, const std::vector<ActionSpec>& actions)
    {
        notify_notification_clear_actions(managed.handle);
        for (const auto& action : actions) {
            auto* ref = new ActionRef { action.cb };
            notify_notification_add_action(managed.handle,
                action.id.c_str(),
                action.label.c_str(),
                NOTIFY_ACTION_CALLBACK(action_callback),
                ref,
                action_ref_free);
        }
    }

    static void closed_callback(NotifyNotification* notification, gpointer user_data)
    {
        auto* pair = reinterpret_cast<std::pair<NotificationCenter*, ClosedRef*>*>(user_data);
        if (pair == nullptr) {
            return;
        }
        NotificationCenter* center = pair->first;
        ClosedRef* ref = pair->second;
        if (ref && ref->fn.valid()) {
            const int reason = notify_notification_get_closed_reason(notification);
            ref->fn(reason);
        }
        if (center) {
            center->remove_notification(notification);
        }
    }

    static void closed_ref_free(gpointer user_data, GClosure*)
    {
        auto* pair = reinterpret_cast<std::pair<NotificationCenter*, ClosedRef*>*>(user_data);
        if (pair != nullptr) {
            delete pair->second;
            delete pair;
        }
    }

    void connect_closed(ManagedNotification& managed, const sol::optional<sol::function>& on_close)
    {
        g_signal_handlers_disconnect_by_func(managed.handle, reinterpret_cast<gpointer>(closed_callback), nullptr);
        auto* ref_pair = new std::pair<NotificationCenter*, ClosedRef*> { this, nullptr };
        if (on_close && on_close->valid()) {
            ref_pair->second = new ClosedRef { *on_close };
        }
        g_signal_connect_data(managed.handle, "closed",
            G_CALLBACK(closed_callback), ref_pair,
            closed_ref_free, static_cast<GConnectFlags>(0));
    }

    static GVariant* make_hint_variant(const sol::object& obj)
    {
        if (obj.is<bool>()) {
            return g_variant_new_boolean(obj.as<bool>());
        }
        if (obj.is<int>()) {
            return g_variant_new_int32(obj.as<int>());
        }
        if (obj.is<double>()) {
            return g_variant_new_double(obj.as<double>());
        }
        if (obj.is<std::string>()) {
            const std::string val = obj.as<std::string>();
            return g_variant_new_string(val.c_str());
        }
        return nullptr;
    }

    void apply_hints(ManagedNotification& managed, const ParsedOptions& options)
    {
        notify_notification_clear_hints(managed.handle);

        if (options.transient && *options.transient) {
            notify_notification_set_hint(managed.handle, "transient", g_variant_new_boolean(TRUE));
        }
        if (options.resident && *options.resident) {
            notify_notification_set_hint(managed.handle, "resident", g_variant_new_boolean(TRUE));
        }
        if (options.suppress_sound && *options.suppress_sound) {
            notify_notification_set_hint(managed.handle, "suppress-sound", g_variant_new_boolean(TRUE));
        }
        if (options.sound_file && !options.sound_file->empty()) {
            notify_notification_set_hint(managed.handle, "sound-file",
                g_variant_new_string(options.sound_file->c_str()));
        }
        if (options.desktop_entry && !options.desktop_entry->empty()) {
            notify_notification_set_hint(managed.handle, "desktop-entry",
                g_variant_new_string(options.desktop_entry->c_str()));
        }
        if (options.synchronous_key && !options.synchronous_key->empty()) {
            notify_notification_set_hint(managed.handle, "x-canonical-private-synchronous",
                g_variant_new_string(options.synchronous_key->c_str()));
        }

        for (const auto& kv : options.hints) {
            GVariant* variant = make_hint_variant(kv.second);
            if (variant != nullptr) {
                notify_notification_set_hint(managed.handle, kv.first.c_str(), variant);
            }
        }
    }

    void apply_options(ManagedNotification& managed, const ParsedOptions& options)
    {
        if (options.app_name && !options.app_name->empty()) {
            notify_notification_set_app_name(managed.handle, options.app_name->c_str());
        } else if (!app_name.empty()) {
            notify_notification_set_app_name(managed.handle, app_name.c_str());
        }

        if (options.timeout_ms) {
            notify_notification_set_timeout(managed.handle, *options.timeout_ms);
        }
        if (options.urgency) {
            notify_notification_set_urgency(managed.handle, *options.urgency);
        }
        if (options.category && !options.category->empty()) {
            notify_notification_set_category(managed.handle, options.category->c_str());
        }

        apply_hints(managed, options);
        apply_actions(managed, options.actions);
        connect_closed(managed, options.on_close);
    }

    void remove_notification(NotifyNotification* handle)
    {
        auto it = std::find_if(notifications_.begin(), notifications_.end(),
            [handle](const std::unique_ptr<ManagedNotification>& m) { return m->handle == handle; });
        if (it != notifications_.end()) {
            if (!(*it)->replace_key.empty()) {
                replace_index_.erase((*it)->replace_key);
            }
            g_object_unref(G_OBJECT((*it)->handle));
            notifications_.erase(it);
        }
    }
#endif

    bool ensure_init()
    {
#if defined(NOTIFY_BACKEND_NONE)
        last_error = get_compile_reason();
        return false;
#elif defined(NOTIFY_LIBNOTIFY)
        if (initialized) {
            return true;
        }

        if (!notify_init(app_name.c_str())) {
            last_error = "notify_init failed";
            initialized = false;
            return false;
        }

        initialized = true;
        return true;
#else
        last_error = "notification backend not configured";
        return false;
#endif
    }

    void reset()
    {
#if defined(NOTIFY_LIBNOTIFY)
        for (auto& managed : notifications_) {
            g_signal_handlers_disconnect_by_func(managed->handle, reinterpret_cast<gpointer>(closed_callback), nullptr);
            g_object_unref(G_OBJECT(managed->handle));
        }
        notifications_.clear();
        replace_index_.clear();
        if (initialized) {
            notify_uninit();
            initialized = false;
        }
#endif
    }

    std::string app_name { "space" };
    bool initialized { false };
#if defined(NOTIFY_LIBNOTIFY)
    std::vector<std::unique_ptr<ManagedNotification>> notifications_ {};
    std::unordered_map<std::string, ManagedNotification*> replace_index_ {};
#endif
};

NotificationCenter& default_center()
{
    static NotificationCenter center {};
    return center;
}

sol::table support_info(sol::state_view lua)
{
    sol::table t = lua.create_table();
#if defined(NOTIFY_BACKEND_NONE)
    t["supported"] = false;
    t["backend"] = std::string { NOTIFY_BACKEND_NAME };
    t["reason"] = std::string { NOTIFY_BACKEND_REASON };
#elif defined(NOTIFY_LIBNOTIFY)
    t["supported"] = true;
    t["backend"] = std::string { NOTIFY_BACKEND_NAME };
    t["reason"] = "";
#else
    t["supported"] = false;
    t["backend"] = "unknown";
    t["reason"] = "notification backend not configured";
#endif
    return t;
}

} // namespace

namespace {

sol::table create_notify_table(sol::state_view lua)
{
    sol::table notification = lua.create_table();
    notification.new_usertype<NotificationCenter>("Notification",
        sol::no_constructor,
        "send", &NotificationCenter::send,
        "set-app-name", &NotificationCenter::set_app_name,
        "last-error", [](NotificationCenter& self) { return self.last_error; },
        "backend", [](NotificationCenter& self) { return self.backend_name(); });
    notification["supported"] = support_info(lua);
    notification["support"] = [](sol::this_state s) {
        return support_info(sol::state_view { s });
    };
    notification["create"] = []() {
        return NotificationCenter {};
    };
    notification["send"] = [](const std::string& summary, sol::optional<std::string> body,
                               sol::optional<std::string> icon, sol::optional<sol::object> options) {
        return default_center().send(summary, body, icon, options);
    };
    notification["set-app-name"] = [](const std::string& name) {
        default_center().set_app_name(name);
    };
    notification["last-error"] = []() {
        return default_center().last_error;
    };
    notification["backend"] = []() {
        return default_center().backend_name();
    };
    return notification;
}

} // namespace

void lua_bind_notify(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("notify", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_notify_table(lua);
    });
}
