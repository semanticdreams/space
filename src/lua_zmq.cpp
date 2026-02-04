#include <sol/sol.hpp>

#include <chrono>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include <zmq.hpp>

namespace {

struct ZmqContext;

struct ZmqSocket {
    ZmqSocket(std::shared_ptr<zmq::context_t> ctx_ref, int type)
        : ctx(std::move(ctx_ref))
        , socket(*ctx, type)
    {
    }

    ~ZmqSocket()
    {
        close();
    }

    void bind(const std::string& endpoint)
    {
        ensure_open("bind");
        socket.bind(endpoint);
    }

    void connect(const std::string& endpoint)
    {
        ensure_open("connect");
        socket.connect(endpoint);
    }

    void unbind(const std::string& endpoint)
    {
        ensure_open("unbind");
        socket.unbind(endpoint);
    }

    void disconnect(const std::string& endpoint)
    {
        ensure_open("disconnect");
        socket.disconnect(endpoint);
    }

    void close()
    {
        if (!closed) {
            socket.close();
            closed = true;
        }
    }

    bool is_closed() const { return closed; }

    int get_option_int(const std::string& name)
    {
        ensure_open("get-option");
        if (name == "linger") {
            return socket.get(zmq::sockopt::linger);
        }
        if (name == "rcvtimeo") {
            return socket.get(zmq::sockopt::rcvtimeo);
        }
        if (name == "sndtimeo") {
            return socket.get(zmq::sockopt::sndtimeo);
        }
        if (name == "rcvhwm") {
            return socket.get(zmq::sockopt::rcvhwm);
        }
        if (name == "sndhwm") {
            return socket.get(zmq::sockopt::sndhwm);
        }
        if (name == "immediate") {
            return socket.get(zmq::sockopt::immediate);
        }
        if (name == "ipv6") {
            return socket.get(zmq::sockopt::ipv6);
        }
        throw sol::error("zmq.get-option-int unsupported option: " + name);
    }

    std::string get_option_string(const std::string& name)
    {
        ensure_open("get-option");
        if (name == "routing-id" || name == "identity") {
            return socket.get(zmq::sockopt::routing_id);
        }
        throw sol::error("zmq.get-option-string unsupported option: " + name);
    }

    void set_option_int(const std::string& name, int value)
    {
        ensure_open("set-option");
        if (name == "linger") {
            socket.set(zmq::sockopt::linger, value);
            return;
        }
        if (name == "rcvtimeo") {
            socket.set(zmq::sockopt::rcvtimeo, value);
            return;
        }
        if (name == "sndtimeo") {
            socket.set(zmq::sockopt::sndtimeo, value);
            return;
        }
        if (name == "rcvhwm") {
            socket.set(zmq::sockopt::rcvhwm, value);
            return;
        }
        if (name == "sndhwm") {
            socket.set(zmq::sockopt::sndhwm, value);
            return;
        }
        if (name == "immediate") {
            socket.set(zmq::sockopt::immediate, value);
            return;
        }
        if (name == "ipv6") {
            socket.set(zmq::sockopt::ipv6, value);
            return;
        }
        throw sol::error("zmq.set-option-int unsupported option: " + name);
    }

    void set_option_string(const std::string& name, const std::string& value)
    {
        ensure_open("set-option");
        if (name == "subscribe") {
            socket.set(zmq::sockopt::subscribe, value);
            return;
        }
        if (name == "unsubscribe") {
            socket.set(zmq::sockopt::unsubscribe, value);
            return;
        }
        if (name == "routing-id" || name == "identity") {
            socket.set(zmq::sockopt::routing_id, value);
            return;
        }
        throw sol::error("zmq.set-option-string unsupported option: " + name);
    }

    sol::object send(sol::this_state ts, sol::object data, sol::optional<int> flags)
    {
        ensure_open("send");
        zmq::send_flags send_flags = flags ? static_cast<zmq::send_flags>(*flags) : zmq::send_flags::none;
        sol::state_view lua(ts);
        if (data.is<std::string>()) {
            std::string payload = data.as<std::string>();
            zmq::send_result_t result = socket.send(zmq::buffer(payload), send_flags);
            if (!result) {
                return sol::make_object(lua, sol::lua_nil);
            }
            return sol::make_object(lua, static_cast<uint64_t>(*result));
        }
        if (data.is<zmq::message_t>()) {
            zmq::message_t& msg = data.as<zmq::message_t&>();
            zmq::send_result_t result = socket.send(msg, send_flags);
            if (!result) {
                return sol::make_object(lua, sol::lua_nil);
            }
            return sol::make_object(lua, static_cast<uint64_t>(*result));
        }
        if (data.is<sol::table>()) {
            sol::table parts = data.as<sol::table>();
            std::size_t len = parts.size();
            if (len == 0) {
                throw sol::error("zmq.send multipart requires at least one part");
            }
            uint64_t total = 0;
            for (std::size_t i = 1; i <= len; ++i) {
                sol::object part = parts.get<sol::object>(i);
                zmq::send_flags part_flags = send_flags;
                if (i < len) {
                    part_flags = part_flags | zmq::send_flags::sndmore;
                }
                if (part.is<std::string>()) {
                    std::string payload = part.as<std::string>();
                    zmq::send_result_t result = socket.send(zmq::buffer(payload), part_flags);
                    if (!result) {
                        return sol::make_object(lua, sol::lua_nil);
                    }
                    total += static_cast<uint64_t>(*result);
                } else if (part.is<zmq::message_t>()) {
                    zmq::message_t& msg = part.as<zmq::message_t&>();
                    zmq::send_result_t result = socket.send(msg, part_flags);
                    if (!result) {
                        return sol::make_object(lua, sol::lua_nil);
                    }
                    total += static_cast<uint64_t>(*result);
                } else {
                    throw sol::error("zmq.send multipart expects string or ZmqMessage parts");
                }
            }
            return sol::make_object(lua, total);
        }
        throw sol::error("zmq.send expects string, ZmqMessage, or table");
    }

    sol::object recv(sol::this_state ts, sol::optional<int> flags)
    {
        ensure_open("recv");
        zmq::recv_flags recv_flags = flags ? static_cast<zmq::recv_flags>(*flags) : zmq::recv_flags::none;
        zmq::message_t msg;
        zmq::recv_result_t result = socket.recv(msg, recv_flags);
        sol::state_view lua(ts);
        if (!result) {
            return sol::make_object(lua, sol::lua_nil);
        }
        return sol::make_object(lua, std::move(msg));
    }

    sol::object recv_multipart(sol::this_state ts, sol::optional<int> flags)
    {
        ensure_open("recv-multipart");
        zmq::recv_flags recv_flags = flags ? static_cast<zmq::recv_flags>(*flags) : zmq::recv_flags::none;
        sol::state_view lua(ts);
        sol::table out = lua.create_table();
        zmq::message_t msg;
        zmq::recv_result_t result = socket.recv(msg, recv_flags);
        if (!result) {
            return sol::make_object(lua, sol::lua_nil);
        }
        std::size_t idx = 1;
        out[idx++] = std::move(msg);
        while (socket.get(zmq::sockopt::rcvmore)) {
            zmq::message_t part;
            zmq::recv_result_t more_result = socket.recv(part, zmq::recv_flags::none);
            if (!more_result) {
                break;
            }
            out[idx++] = std::move(part);
        }
        return sol::make_object(lua, out);
    }

    zmq::socket_t& raw()
    {
        ensure_open("socket");
        return socket;
    }

private:
    void ensure_open(const std::string& action) const
    {
        if (closed) {
            throw sol::error("zmq socket is closed: " + action);
        }
    }

    std::shared_ptr<zmq::context_t> ctx;
    zmq::socket_t socket;
    bool closed { false };
};

struct ZmqContext {
    explicit ZmqContext(int io_threads)
        : ctx(std::make_shared<zmq::context_t>(io_threads))
    {
    }

    ~ZmqContext()
    {
        close();
    }

    std::shared_ptr<ZmqSocket> socket(int type)
    {
        ensure_open("socket");
        return std::make_shared<ZmqSocket>(ctx, type);
    }

    void shutdown()
    {
        ensure_open("shutdown");
        ctx->shutdown();
    }

    void close()
    {
        if (!closed) {
            ctx->close();
            closed = true;
        }
    }

    bool is_closed() const { return closed; }

    int get_option_int(const std::string& name)
    {
        ensure_open("get-option");
        if (name == "io-threads") {
            return ctx->get(zmq::ctxopt::io_threads);
        }
        if (name == "max-sockets") {
            return ctx->get(zmq::ctxopt::max_sockets);
        }
        throw sol::error("zmq.ctx.get-option-int unsupported option: " + name);
    }

    void set_option_int(const std::string& name, int value)
    {
        ensure_open("set-option");
        if (name == "io-threads") {
            ctx->set(zmq::ctxopt::io_threads, value);
            return;
        }
        if (name == "max-sockets") {
            ctx->set(zmq::ctxopt::max_sockets, value);
            return;
        }
        throw sol::error("zmq.ctx.set-option-int unsupported option: " + name);
    }

private:
    void ensure_open(const std::string& action) const
    {
        if (closed) {
            throw sol::error("zmq context is closed: " + action);
        }
    }

    std::shared_ptr<zmq::context_t> ctx;
    bool closed { false };
};

sol::table create_zmq_table(sol::state_view lua)
{
    sol::table zmq_table = lua.create_table();

    zmq_table.new_usertype<ZmqContext>("ZmqContext",
        sol::no_constructor,
        "socket", &ZmqContext::socket,
        "shutdown", &ZmqContext::shutdown,
        "close", &ZmqContext::close,
        "is-closed", &ZmqContext::is_closed,
        "get-option-int", &ZmqContext::get_option_int,
        "set-option-int", &ZmqContext::set_option_int);

    zmq_table.new_usertype<ZmqSocket>("ZmqSocket",
        sol::no_constructor,
        "bind", &ZmqSocket::bind,
        "connect", &ZmqSocket::connect,
        "unbind", &ZmqSocket::unbind,
        "disconnect", &ZmqSocket::disconnect,
        "close", &ZmqSocket::close,
        "is-closed", &ZmqSocket::is_closed,
        "get-option-int", &ZmqSocket::get_option_int,
        "get-option-string", &ZmqSocket::get_option_string,
        "set-option-int", &ZmqSocket::set_option_int,
        "set-option-string", &ZmqSocket::set_option_string,
        "send", &ZmqSocket::send,
        "recv", &ZmqSocket::recv,
        "recv-multipart", &ZmqSocket::recv_multipart);

    zmq_table.new_usertype<zmq::message_t>("ZmqMessage",
        sol::no_constructor,
        "size", [](const zmq::message_t& msg) { return msg.size(); },
        "to-string", [](const zmq::message_t& msg) { return msg.to_string(); });

    zmq_table.set_function("Context", [](sol::optional<int> io_threads) {
        int threads = io_threads.value_or(1);
        return std::make_shared<ZmqContext>(threads);
    });

    zmq_table.set_function("Message", [](sol::optional<std::string> data) {
        if (data) {
            return zmq::message_t(data->data(), data->size());
        }
        return zmq::message_t();
    });

    zmq_table.set_function("version", [lua]() {
        sol::state_view lua_view(lua.lua_state());
        int major = 0;
        int minor = 0;
        int patch = 0;
        zmq::version(&major, &minor, &patch);
        sol::table out = lua_view.create_table();
        out["major"] = major;
        out["minor"] = minor;
        out["patch"] = patch;
        return out;
    });

    zmq_table.set_function("poll", [](sol::table items, sol::optional<long> timeout_ms) {
        sol::state_view lua_view(items.lua_state());
        std::vector<zmq::pollitem_t> poll_items;
        std::vector<std::shared_ptr<ZmqSocket>> sockets;
        std::size_t len = items.size();
        poll_items.reserve(len);
        sockets.reserve(len);
        for (std::size_t i = 1; i <= len; ++i) {
            sol::table item = items.get<sol::table>(i);
            auto sock = item.get<std::shared_ptr<ZmqSocket>>("socket");
            int events = item.get_or("events", 0);
            if (!sock) {
                throw sol::error("zmq.poll requires socket");
            }
            if (sock->is_closed()) {
                throw sol::error("zmq.poll socket is closed");
            }
            zmq::pollitem_t poll_item {
                sock->raw().handle(),
                0,
                static_cast<short>(events),
                0
            };
            poll_items.push_back(poll_item);
            sockets.push_back(sock);
        }
        auto timeout = std::chrono::milliseconds(timeout_ms.value_or(-1));
        zmq::poll(poll_items, timeout);
        sol::table out = lua_view.create_table();
        for (std::size_t i = 0; i < poll_items.size(); ++i) {
            sol::table entry = lua_view.create_table();
            entry["revents"] = poll_items[i].revents;
            out[i + 1] = entry;
        }
        return out;
    });

    sol::table socket_types = lua.create_table();
    socket_types["REQ"] = ZMQ_REQ;
    socket_types["REP"] = ZMQ_REP;
    socket_types["DEALER"] = ZMQ_DEALER;
    socket_types["ROUTER"] = ZMQ_ROUTER;
    socket_types["PUB"] = ZMQ_PUB;
    socket_types["SUB"] = ZMQ_SUB;
    socket_types["PUSH"] = ZMQ_PUSH;
    socket_types["PULL"] = ZMQ_PULL;
    socket_types["PAIR"] = ZMQ_PAIR;
    zmq_table["socket-types"] = socket_types;

    sol::table send_flags = lua.create_table();
    send_flags["NONE"] = 0;
    send_flags["DONTWAIT"] = ZMQ_DONTWAIT;
    send_flags["SNDMORE"] = ZMQ_SNDMORE;
    zmq_table["send-flags"] = send_flags;

    sol::table recv_flags = lua.create_table();
    recv_flags["NONE"] = 0;
    recv_flags["DONTWAIT"] = ZMQ_DONTWAIT;
    zmq_table["recv-flags"] = recv_flags;

    sol::table poll_events = lua.create_table();
    poll_events["IN"] = ZMQ_POLLIN;
    poll_events["OUT"] = ZMQ_POLLOUT;
    poll_events["ERR"] = ZMQ_POLLERR;
    zmq_table["poll-events"] = poll_events;

    return zmq_table;
}

} // namespace

void lua_bind_zmq(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("zmq", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_zmq_table(lua);
    });
}
