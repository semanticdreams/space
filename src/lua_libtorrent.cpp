#include <sol/sol.hpp>

#if defined(SPACE_ENABLE_LIBTORRENT)

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/entry.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_handle.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/session_status.hpp>
#include <libtorrent/operations.hpp>
#include <libtorrent/socks5_stream.hpp>
#include <libtorrent/upnp.hpp>
#include <libtorrent/i2p_stream.hpp>
#include <libtorrent/kademlia/ed25519.hpp>
#include <libtorrent/kademlia/item.hpp>
#include <libtorrent/kademlia/announce_flags.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <array>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fs = std::filesystem;
namespace lt = libtorrent;

namespace {

std::vector<std::string> default_trackers()
{
    return {
        "udp://tracker.openbittorrent.com:6969/announce",
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce"
    };
}

std::string default_dht_bootstrap_nodes()
{
    return "router.bittorrent.com:6881,dht.transmissionbt.com:6881,router.utorrent.com:6881";
}

int hex_value(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

std::array<char, 20> sha1_from_hex(const std::string& hex)
{
    if (hex.size() != 40) {
        throw sol::error("info-hash must be 40 hex characters");
    }
    std::array<char, 20> out {};
    for (std::size_t i = 0; i < out.size(); ++i) {
        int high = hex_value(hex[i * 2]);
        int low = hex_value(hex[i * 2 + 1]);
        if (high < 0 || low < 0) {
            throw sol::error("info-hash contains non-hex characters");
        }
        out[i] = static_cast<char>((high << 4) | low);
    }
    return out;
}

template <std::size_t N>
std::array<char, N> fixed_bytes_from_hex(const std::string& hex, const char* label)
{
    if (hex.size() != N * 2) {
        throw sol::error(std::string(label) + " must be " + std::to_string(N * 2) + " hex characters");
    }
    std::array<char, N> out {};
    for (std::size_t i = 0; i < N; ++i) {
        int high = hex_value(hex[i * 2]);
        int low = hex_value(hex[i * 2 + 1]);
        if (high < 0 || low < 0) {
            throw sol::error(std::string(label) + " contains non-hex characters");
        }
        out[i] = static_cast<char>((high << 4) | low);
    }
    return out;
}

std::string hex_from_bytes(const char* data, std::size_t size)
{
    static const char* digits = "0123456789abcdef";
    std::string out;
    out.resize(size * 2);
    for (std::size_t i = 0; i < size; ++i) {
        unsigned char byte = static_cast<unsigned char>(data[i]);
        out[i * 2] = digits[(byte >> 4) & 0x0F];
        out[i * 2 + 1] = digits[byte & 0x0F];
    }
    return out;
}

std::vector<std::string> read_trackers(sol::table opts)
{
    sol::optional<sol::table> trackers_opt = opts.get<sol::optional<sol::table>>("trackers");
    if (!trackers_opt) {
        return default_trackers();
    }

    sol::table trackers_table = trackers_opt.value();
    std::vector<std::string> trackers;
    for (std::size_t i = 1; i <= trackers_table.size(); ++i) {
        sol::object entry = trackers_table.get<sol::object>(i);
        if (!entry.is<std::string>()) {
            throw sol::error("trackers must be an array of strings");
        }
        trackers.push_back(entry.as<std::string>());
    }
    if (trackers.empty()) {
        trackers = default_trackers();
    }
    return trackers;
}

bool try_read_positive_integer_key(const sol::object& key, std::size_t& out)
{
    if (key.is<std::size_t>()) {
        out = key.as<std::size_t>();
        return out >= 1;
    }
    if (key.is<int>()) {
        int value = key.as<int>();
        if (value < 1) {
            return false;
        }
        out = static_cast<std::size_t>(value);
        return true;
    }
    if (key.is<double>()) {
        double value = key.as<double>();
        if (value < 1) {
            return false;
        }
        double integral = 0.0;
        if (std::modf(value, &integral) != 0.0) {
            return false;
        }
        out = static_cast<std::size_t>(integral);
        return true;
    }
    return false;
}

struct BencodeListValue
{
    explicit BencodeListValue(sol::table value)
        : values(value)
    {
    }

    sol::table values;
};

struct BencodeDictValue
{
    explicit BencodeDictValue(sol::table value)
        : values(value)
    {
    }

    sol::table values;
};

lt::entry lua_object_to_entry(sol::object value);

lt::entry lua_list_table_to_entry(sol::table table)
{
    lt::entry out(lt::entry::list_type {});
    lt::entry::list_type& items = out.list();
    std::size_t count = table.size();
    items.reserve(count);
    for (std::size_t i = 1; i <= count; ++i) {
        items.push_back(lua_object_to_entry(table.get<sol::object>(i)));
    }
    return out;
}

lt::entry lua_dict_table_to_entry(sol::table table)
{
    lt::entry out(lt::entry::dictionary_type {});
    lt::entry::dictionary_type& dict = out.dict();
    for (const auto& kv : table) {
        if (!kv.first.is<std::string>()) {
            throw sol::error("bencode dictionary keys must be strings");
        }
        dict[kv.first.as<std::string>()] = lua_object_to_entry(kv.second.as<sol::object>());
    }
    return out;
}

lt::entry lua_table_to_entry(sol::table table)
{
    std::size_t array_items = 0;
    std::size_t max_index = 0;
    bool has_non_array_key = false;
    for (const auto& kv : table) {
        std::size_t index = 0;
        if (try_read_positive_integer_key(kv.first, index)) {
            ++array_items;
            if (index > max_index) {
                max_index = index;
            }
        } else {
            has_non_array_key = true;
        }
    }

    bool is_array = !has_non_array_key && array_items > 0 && max_index == array_items;
    if (is_array) {
        return lua_list_table_to_entry(table);
    }

    return lua_dict_table_to_entry(table);
}

lt::entry lua_object_to_entry(sol::object value)
{
    if (value.is<std::shared_ptr<BencodeListValue>>()) {
        auto list = value.as<std::shared_ptr<BencodeListValue>>();
        return lua_list_table_to_entry(list->values);
    }
    if (value.is<std::shared_ptr<BencodeDictValue>>()) {
        auto dict = value.as<std::shared_ptr<BencodeDictValue>>();
        return lua_dict_table_to_entry(dict->values);
    }
    if (value.is<sol::table>()) {
        return lua_table_to_entry(value.as<sol::table>());
    }
    if (value.is<std::string>()) {
        return lt::entry(value.as<std::string>());
    }
    if (value.is<bool>()) {
        return lt::entry(value.as<bool>() ? 1 : 0);
    }
    if (value.is<std::int64_t>()) {
        return lt::entry(value.as<std::int64_t>());
    }
    if (value.is<int>()) {
        return lt::entry(static_cast<std::int64_t>(value.as<int>()));
    }
    if (value.is<double>()) {
        double numeric = value.as<double>();
        double integral = 0.0;
        if (std::modf(numeric, &integral) != 0.0) {
            throw sol::error("bencode only supports integers, strings, lists and dictionaries");
        }
        return lt::entry(static_cast<std::int64_t>(integral));
    }
    if (value == sol::lua_nil) {
        throw sol::error("bencode does not support nil values");
    }
    throw sol::error("unsupported value type for bencode");
}

sol::object entry_to_lua_object(sol::state_view lua, const lt::entry& value)
{
    switch (value.type()) {
    case lt::entry::int_t:
        return sol::make_object(lua, value.integer());
    case lt::entry::string_t:
        return sol::make_object(lua, value.string());
    case lt::entry::list_t: {
        const lt::entry::list_type& list = value.list();
        sol::table out = lua.create_table(static_cast<int>(list.size()), 0);
        for (std::size_t i = 0; i < list.size(); ++i) {
            out[i + 1] = entry_to_lua_object(lua, list[i]);
        }
        return sol::make_object(lua, out);
    }
    case lt::entry::dictionary_t: {
        const lt::entry::dictionary_type& dict = value.dict();
        sol::table out = lua.create_table(0, static_cast<int>(dict.size()));
        for (const auto& kv : dict) {
            out[kv.first] = entry_to_lua_object(lua, kv.second);
        }
        return sol::make_object(lua, out);
    }
    default:
        return sol::make_object(lua, sol::lua_nil);
    }
}

template <typename T>
T opt_or(sol::table opts, const char* key, T default_value)
{
    sol::optional<T> value = opts.get<sol::optional<T>>(key);
    if (value) {
        return value.value();
    }
    return default_value;
}

std::string torrent_state_name(lt::torrent_status::state_t state)
{
    switch (state) {
    case lt::torrent_status::checking_files:
        return "checking-files";
    case lt::torrent_status::downloading_metadata:
        return "downloading-metadata";
    case lt::torrent_status::downloading:
        return "downloading";
    case lt::torrent_status::finished:
        return "finished";
    case lt::torrent_status::seeding:
        return "seeding";
    case lt::torrent_status::checking_resume_data:
        return "checking-resume-data";
    default:
        return "unknown";
    }
}

lt::settings_pack make_settings(sol::table opts)
{
    lt::settings_pack pack;
    std::string listen_interfaces = "0.0.0.0:0,[::]:0";
    sol::optional<std::string> listen_opt = opts.get<sol::optional<std::string>>("listen-interfaces");
    if (listen_opt && !listen_opt.value().empty()) {
        listen_interfaces = listen_opt.value();
    }
    std::string dht_bootstrap_nodes = default_dht_bootstrap_nodes();
    sol::optional<std::string> dht_nodes_opt = opts.get<sol::optional<std::string>>("dht-bootstrap-nodes");
    if (dht_nodes_opt && !dht_nodes_opt.value().empty()) {
        dht_bootstrap_nodes = dht_nodes_opt.value();
    }
    pack.set_str(lt::settings_pack::listen_interfaces, listen_interfaces);
    pack.set_str(lt::settings_pack::dht_bootstrap_nodes, dht_bootstrap_nodes);
    pack.set_bool(lt::settings_pack::enable_dht, true);
    pack.set_bool(lt::settings_pack::announce_to_all_tiers, true);
    pack.set_bool(lt::settings_pack::announce_to_all_trackers, true);
    auto alert_mask = lt::alert_category::error | lt::alert_category::status | lt::alert_category::dht;
    pack.set_int(lt::settings_pack::alert_mask,
                 static_cast<int>(static_cast<lt::alert_category_t::underlying_type>(alert_mask)));
    return pack;
}

sol::table status_to_table(sol::state_view lua, const lt::torrent_status& status)
{
    sol::table result = lua.create_table();
    result["name"] = status.name;
    result["state"] = torrent_state_name(status.state);
    result["progress"] = status.progress;
    result["progress-ppm"] = status.progress_ppm;
    result["is-seeding"] = status.is_seeding;
    result["num-peers"] = status.num_peers;
    result["num-seeds"] = status.num_seeds;
    result["total-done"] = status.total_done;
    result["total"] = status.total;
    result["download-rate"] = status.download_rate;
    result["upload-rate"] = status.upload_rate;
    if (status.errc) {
        result["error"] = status.errc.message();
    } else {
        result["error"] = sol::lua_nil;
    }
    return result;
}

void set_opt_int(sol::table table, const char* key, lt::settings_pack& pack, int setting)
{
    sol::optional<int> value = table.get<sol::optional<int>>(key);
    if (value) {
        pack.set_int(setting, value.value());
    }
}

void set_opt_bool(sol::table table, const char* key, lt::settings_pack& pack, int setting)
{
    sol::optional<bool> value = table.get<sol::optional<bool>>(key);
    if (value) {
        pack.set_bool(setting, value.value());
    }
}

void set_opt_str(sol::table table, const char* key, lt::settings_pack& pack, int setting)
{
    sol::optional<std::string> value = table.get<sol::optional<std::string>>(key);
    if (value) {
        pack.set_str(setting, value.value());
    }
}

sol::table settings_pack_to_table(sol::state_view lua, const lt::settings_pack& pack)
{
    sol::table result = lua.create_table();
    result["listen-interfaces"] = pack.get_str(lt::settings_pack::listen_interfaces);
    result["dht-bootstrap-nodes"] = pack.get_str(lt::settings_pack::dht_bootstrap_nodes);
    result["user-agent"] = pack.get_str(lt::settings_pack::user_agent);
    result["enable-dht"] = pack.get_bool(lt::settings_pack::enable_dht);
    result["announce-to-all-tiers"] = pack.get_bool(lt::settings_pack::announce_to_all_tiers);
    result["announce-to-all-trackers"] = pack.get_bool(lt::settings_pack::announce_to_all_trackers);
    result["alert-mask"] = pack.get_int(lt::settings_pack::alert_mask);
    result["download-rate-limit"] = pack.get_int(lt::settings_pack::download_rate_limit);
    result["upload-rate-limit"] = pack.get_int(lt::settings_pack::upload_rate_limit);
    result["connections-limit"] = pack.get_int(lt::settings_pack::connections_limit);
    return result;
}

sol::table session_status_to_table(sol::state_view lua
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
                                   ,
                                   const lt::session_status& status
#endif
)
{
    sol::table result = lua.create_table();
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
    result["download-rate"] = status.download_rate;
    result["upload-rate"] = status.upload_rate;
    result["num-peers"] = status.num_peers;
    result["has-incoming-connections"] = status.has_incoming_connections;
    result["dht-nodes"] = status.dht_nodes;
    result["dht-torrents"] = status.dht_torrents;
    result["total-download"] = status.total_download;
    result["total-upload"] = status.total_upload;
#else
    result["download-rate"] = 0;
    result["upload-rate"] = 0;
    result["num-peers"] = 0;
    result["has-incoming-connections"] = false;
    result["dht-nodes"] = 0;
    result["dht-torrents"] = 0;
    result["total-download"] = 0;
    result["total-upload"] = 0;
#endif
    return result;
}

sol::table alert_to_table(sol::state_view lua, const lt::alert& alert)
{
    sol::table result = lua.create_table();
    result["type"] = std::string(alert.what());
    result["message"] = alert.message();
    result["category"] = static_cast<std::uint32_t>(alert.category());
    result["alert-type"] = alert.type();
    auto timestamp_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        alert.timestamp().time_since_epoch());
    result["timestamp-ms"] = static_cast<std::int64_t>(timestamp_ms.count());

    if (const auto* add_alert = lt::alert_cast<lt::add_torrent_alert>(&alert)) {
        if (add_alert->error) {
            result["error"] = add_alert->error.message();
        } else {
            result["error"] = sol::lua_nil;
        }
        result["torrent-name"] = add_alert->params.name;
        result["save-path"] = add_alert->params.save_path;
        if (add_alert->params.info_hashes.has_v1()) {
            result["info-hash-v1"] = hex_from_bytes(add_alert->params.info_hashes.v1.data(), 20);
        } else {
            result["info-hash-v1"] = sol::lua_nil;
        }
    }
    if (const auto* state_alert = lt::alert_cast<lt::state_changed_alert>(&alert)) {
        result["state"] = torrent_state_name(state_alert->state);
        result["prev-state"] = torrent_state_name(state_alert->prev_state);
        result["torrent-name"] = std::string(state_alert->torrent_name());
    }
    if (const auto* update_alert = lt::alert_cast<lt::state_update_alert>(&alert)) {
        result["status-count"] = static_cast<int>(update_alert->status.size());
    }
    if (const auto* stats_alert = lt::alert_cast<lt::session_stats_alert>(&alert)) {
        result["counters-count"] = static_cast<int>(stats_alert->counters().size());
    }
    if (const auto* dht_alert = lt::alert_cast<lt::dht_stats_alert>(&alert)) {
        result["active-requests-count"] = static_cast<int>(dht_alert->active_requests.size());
        result["routing-table-count"] = static_cast<int>(dht_alert->routing_table.size());
    }
    if (const auto* immutable_alert = lt::alert_cast<lt::dht_immutable_item_alert>(&alert)) {
        result["target"] = hex_from_bytes(immutable_alert->target.data(), 20);
        result["item"] = entry_to_lua_object(lua, immutable_alert->item);
    }
    if (const auto* mutable_alert = lt::alert_cast<lt::dht_mutable_item_alert>(&alert)) {
        result["key"] = hex_from_bytes(mutable_alert->key.data(), 32);
        result["signature"] = hex_from_bytes(mutable_alert->signature.data(), 64);
        result["seq"] = mutable_alert->seq;
        result["salt"] = mutable_alert->salt;
        result["authoritative"] = mutable_alert->authoritative;
        result["item"] = entry_to_lua_object(lua, mutable_alert->item);
    }
    if (const auto* put_alert = lt::alert_cast<lt::dht_put_alert>(&alert)) {
        result["target"] = hex_from_bytes(put_alert->target.data(), 20);
        result["public-key"] = hex_from_bytes(put_alert->public_key.data(), 32);
        result["signature"] = hex_from_bytes(put_alert->signature.data(), 64);
        result["salt"] = put_alert->salt;
        result["seq"] = put_alert->seq;
        result["num-success"] = put_alert->num_success;
    }
    if (const auto* get_peers_reply = lt::alert_cast<lt::dht_get_peers_reply_alert>(&alert)) {
        result["info-hash"] = hex_from_bytes(get_peers_reply->info_hash.data(), 20);
        std::vector<lt::tcp::endpoint> peers = get_peers_reply->peers();
        sol::table peers_table = lua.create_table(static_cast<int>(peers.size()), 0);
        for (std::size_t i = 0; i < peers.size(); ++i) {
            sol::table peer = lua.create_table();
            peer["host"] = peers[i].address().to_string();
            peer["port"] = peers[i].port();
            peers_table[i + 1] = peer;
        }
        result["peers"] = peers_table;
        result["num-peers"] = static_cast<int>(peers.size());
    }
    if (const auto* live_nodes = lt::alert_cast<lt::dht_live_nodes_alert>(&alert)) {
        result["node-id"] = hex_from_bytes(live_nodes->node_id.data(), 20);
        std::vector<std::pair<lt::sha1_hash, lt::udp::endpoint>> nodes = live_nodes->nodes();
        sol::table nodes_table = lua.create_table(static_cast<int>(nodes.size()), 0);
        for (std::size_t i = 0; i < nodes.size(); ++i) {
            sol::table node = lua.create_table();
            node["id"] = hex_from_bytes(nodes[i].first.data(), 20);
            node["host"] = nodes[i].second.address().to_string();
            node["port"] = nodes[i].second.port();
            nodes_table[i + 1] = node;
        }
        result["nodes"] = nodes_table;
        result["num-nodes"] = static_cast<int>(nodes.size());
    }
    if (const auto* sample_infohashes = lt::alert_cast<lt::dht_sample_infohashes_alert>(&alert)) {
        result["node-id"] = hex_from_bytes(sample_infohashes->node_id.data(), 20);
        result["endpoint-host"] = sample_infohashes->endpoint.address().to_string();
        result["endpoint-port"] = sample_infohashes->endpoint.port();
        result["num-infohashes"] = sample_infohashes->num_infohashes;
        auto interval_ms = std::chrono::duration_cast<std::chrono::milliseconds>(sample_infohashes->interval);
        result["interval-ms"] = static_cast<std::int64_t>(interval_ms.count());
        std::vector<lt::sha1_hash> samples = sample_infohashes->samples();
        sol::table samples_table = lua.create_table(static_cast<int>(samples.size()), 0);
        for (std::size_t i = 0; i < samples.size(); ++i) {
            samples_table[i + 1] = hex_from_bytes(samples[i].data(), 20);
        }
        result["samples"] = samples_table;
        result["num-samples"] = static_cast<int>(samples.size());
    }
    if (const auto* announce_alert = lt::alert_cast<lt::dht_announce_alert>(&alert)) {
        result["announce-host"] = announce_alert->ip.to_string();
        result["announce-port"] = announce_alert->port;
        result["announce-info-hash"] = hex_from_bytes(announce_alert->info_hash.data(), 20);
    }
    if (const auto* direct_response = lt::alert_cast<lt::dht_direct_response_alert>(&alert)) {
        result["endpoint-host"] = direct_response->endpoint.address().to_string();
        result["endpoint-port"] = direct_response->endpoint.port();
        lt::bdecode_node response = direct_response->response();
        if (response) {
            lt::entry decoded(response);
            result["response"] = entry_to_lua_object(lua, decoded);
        } else {
            result["response"] = sol::lua_nil;
        }
        auto userdata = direct_response->userdata.get<std::int64_t>();
        if (userdata != nullptr) {
            result["userdata"] = *userdata;
        } else {
            result["userdata"] = sol::lua_nil;
        }
    }
    return result;
}

std::uint64_t flags_to_u64(lt::torrent_flags_t flags)
{
    return static_cast<std::uint64_t>(flags);
}

lt::torrent_flags_t u64_to_flags(std::uint64_t flags)
{
    return lt::torrent_flags_t(flags);
}

sol::table torrent_flags_to_table(sol::state_view lua)
{
    sol::table result = lua.create_table();
    result["default-flags"] = flags_to_u64(lt::torrent_flags::default_flags);
    result["seed-mode"] = flags_to_u64(lt::torrent_flags::seed_mode);
    result["upload-mode"] = flags_to_u64(lt::torrent_flags::upload_mode);
    result["share-mode"] = flags_to_u64(lt::torrent_flags::share_mode);
    result["apply-ip-filter"] = flags_to_u64(lt::torrent_flags::apply_ip_filter);
    result["paused"] = flags_to_u64(lt::torrent_flags::paused);
    result["auto-managed"] = flags_to_u64(lt::torrent_flags::auto_managed);
    result["duplicate-is-error"] = flags_to_u64(lt::torrent_flags::duplicate_is_error);
    result["update-subscribe"] = flags_to_u64(lt::torrent_flags::update_subscribe);
    result["super-seeding"] = flags_to_u64(lt::torrent_flags::super_seeding);
    result["sequential-download"] = flags_to_u64(lt::torrent_flags::sequential_download);
    result["stop-when-ready"] = flags_to_u64(lt::torrent_flags::stop_when_ready);
    result["override-trackers"] = flags_to_u64(lt::torrent_flags::override_trackers);
    result["override-web-seeds"] = flags_to_u64(lt::torrent_flags::override_web_seeds);
    result["need-save-resume"] = flags_to_u64(lt::torrent_flags::need_save_resume);
    result["disable-dht"] = flags_to_u64(lt::torrent_flags::disable_dht);
    result["disable-lsd"] = flags_to_u64(lt::torrent_flags::disable_lsd);
    result["disable-pex"] = flags_to_u64(lt::torrent_flags::disable_pex);
    return result;
}

sol::table storage_modes_to_table(sol::state_view lua)
{
    sol::table result = lua.create_table();
    result["allocate"] = static_cast<int>(lt::storage_mode_allocate);
    result["sparse"] = static_cast<int>(lt::storage_mode_sparse);
    return result;
}

sol::table dht_announce_flags_to_table(sol::state_view lua)
{
    sol::table result = lua.create_table();
    result["seed"] = static_cast<int>(static_cast<std::uint8_t>(lt::dht::announce::seed));
    result["implied-port"] = static_cast<int>(static_cast<std::uint8_t>(lt::dht::announce::implied_port));
    result["ssl-torrent"] = static_cast<int>(static_cast<std::uint8_t>(lt::dht::announce::ssl_torrent));
    return result;
}

std::uint32_t save_state_flags_to_u32(lt::save_state_flags_t flags)
{
    return static_cast<std::uint32_t>(flags);
}

lt::save_state_flags_t u32_to_save_state_flags(std::uint32_t flags)
{
    return lt::save_state_flags_t(flags);
}

sol::table save_state_flags_to_table(sol::state_view lua)
{
    sol::table result = lua.create_table();
    result["save-settings"] = save_state_flags_to_u32(lt::session_handle::save_settings);
    result["save-dht-state"] = save_state_flags_to_u32(lt::session_handle::save_dht_state);
    result["save-extension-state"] = save_state_flags_to_u32(lt::session_handle::save_extension_state);
    result["save-ip-filter"] = save_state_flags_to_u32(lt::session_handle::save_ip_filter);
    result["all"] = save_state_flags_to_u32(lt::save_state_flags_t::all());
    return result;
}

sol::table session_stats_metrics_to_table(sol::state_view lua)
{
    std::vector<lt::stats_metric> metrics = lt::session_stats_metrics();
    sol::table out = lua.create_table(static_cast<int>(metrics.size()), 0);
    for (std::size_t i = 0; i < metrics.size(); ++i) {
        sol::table item = lua.create_table();
        item["name"] = metrics[i].name;
        item["value-index"] = metrics[i].value_index;
        out[i + 1] = item;
    }
    return out;
}

struct AddTorrentParamsHandle
{
    explicit AddTorrentParamsHandle(lt::add_torrent_params value)
        : atp(std::move(value))
    {
    }

    sol::table to_table(sol::this_state ts) const
    {
        sol::state_view lua(ts);
        sol::table result = lua.create_table();
        result["name"] = atp.name;
        result["save-path"] = atp.save_path;
        result["upload-limit"] = atp.upload_limit;
        result["download-limit"] = atp.download_limit;
        result["max-connections"] = atp.max_connections;
        result["max-uploads"] = atp.max_uploads;
        result["flags"] = flags_to_u64(atp.flags);
        result["storage-mode"] = static_cast<int>(atp.storage_mode);
        result["has-torrent-info"] = static_cast<bool>(atp.ti);
        if (atp.info_hashes.has_v1()) {
            result["info-hash-v1"] = hex_from_bytes(atp.info_hashes.v1.data(), 20);
        } else {
            result["info-hash-v1"] = sol::lua_nil;
        }
        sol::table trackers = lua.create_table();
        for (std::size_t i = 0; i < atp.trackers.size(); ++i) {
            trackers[i + 1] = atp.trackers[i];
        }
        result["trackers"] = trackers;
        sol::table tracker_tiers = lua.create_table();
        for (std::size_t i = 0; i < atp.tracker_tiers.size(); ++i) {
            tracker_tiers[i + 1] = atp.tracker_tiers[i];
        }
        result["tracker-tiers"] = tracker_tiers;
        sol::table url_seeds = lua.create_table();
        for (std::size_t i = 0; i < atp.url_seeds.size(); ++i) {
            url_seeds[i + 1] = atp.url_seeds[i];
        }
        result["url-seeds"] = url_seeds;
        sol::table dht_nodes = lua.create_table();
        for (std::size_t i = 0; i < atp.dht_nodes.size(); ++i) {
            sol::table node = lua.create_table();
            node["host"] = atp.dht_nodes[i].first;
            node["port"] = atp.dht_nodes[i].second;
            dht_nodes[i + 1] = node;
        }
        result["dht-nodes"] = dht_nodes;
        sol::table file_priorities = lua.create_table();
        for (std::size_t i = 0; i < atp.file_priorities.size(); ++i) {
            file_priorities[i + 1] = static_cast<int>(static_cast<std::uint8_t>(atp.file_priorities[i]));
        }
        result["file-priorities"] = file_priorities;
        sol::table piece_priorities = lua.create_table();
        for (std::size_t i = 0; i < atp.piece_priorities.size(); ++i) {
            piece_priorities[i + 1] = static_cast<int>(static_cast<std::uint8_t>(atp.piece_priorities[i]));
        }
        result["piece-priorities"] = piece_priorities;
        return result;
    }

    void set_save_path(const std::string& path)
    {
        atp.save_path = path;
    }

    void set_name(const std::string& name)
    {
        atp.name = name;
    }

    void set_trackers(sol::table trackers_table)
    {
        atp.trackers.clear();
        for (std::size_t i = 1; i <= trackers_table.size(); ++i) {
            sol::object entry = trackers_table.get<sol::object>(i);
            if (!entry.is<std::string>()) {
                throw sol::error("trackers must be an array of strings");
            }
            atp.trackers.push_back(entry.as<std::string>());
        }
    }

    std::uint64_t get_flags() const
    {
        return flags_to_u64(atp.flags);
    }

    void set_flags(std::uint64_t flags)
    {
        atp.flags = u64_to_flags(flags);
    }

    void or_flags(std::uint64_t flags)
    {
        atp.flags |= u64_to_flags(flags);
    }

    void clear_flags(std::uint64_t flags)
    {
        atp.flags &= ~u64_to_flags(flags);
    }

    void set_upload_limit(int value)
    {
        atp.upload_limit = value;
    }

    void set_download_limit(int value)
    {
        atp.download_limit = value;
    }

    void set_max_connections(int value)
    {
        atp.max_connections = value;
    }

    void set_max_uploads(int value)
    {
        atp.max_uploads = value;
    }

    void set_storage_mode(int value)
    {
        atp.storage_mode = static_cast<lt::storage_mode_t>(value);
    }

    void set_tracker_tiers(sol::table tiers_table)
    {
        atp.tracker_tiers.clear();
        for (std::size_t i = 1; i <= tiers_table.size(); ++i) {
            sol::object entry = tiers_table.get<sol::object>(i);
            if (!entry.is<int>()) {
                throw sol::error("tracker-tiers must be an array of numbers");
            }
            atp.tracker_tiers.push_back(entry.as<int>());
        }
    }

    void set_url_seeds(sol::table seeds_table)
    {
        atp.url_seeds.clear();
        for (std::size_t i = 1; i <= seeds_table.size(); ++i) {
            sol::object entry = seeds_table.get<sol::object>(i);
            if (!entry.is<std::string>()) {
                throw sol::error("url-seeds must be an array of strings");
            }
            atp.url_seeds.push_back(entry.as<std::string>());
        }
    }

    void set_dht_nodes(sol::table nodes_table)
    {
        atp.dht_nodes.clear();
        for (std::size_t i = 1; i <= nodes_table.size(); ++i) {
            sol::object entry = nodes_table.get<sol::object>(i);
            if (!entry.is<sol::table>()) {
                throw sol::error("dht-nodes must be an array of tables");
            }
            sol::table node = entry.as<sol::table>();
            sol::optional<std::string> host = node.get<sol::optional<std::string>>("host");
            sol::optional<int> port = node.get<sol::optional<int>>("port");
            if (!host || !port) {
                throw sol::error("dht node requires host and port");
            }
            atp.dht_nodes.push_back({ host.value(), port.value() });
        }
    }

    void set_file_priorities(sol::table priorities_table)
    {
        atp.file_priorities.clear();
        for (std::size_t i = 1; i <= priorities_table.size(); ++i) {
            sol::object entry = priorities_table.get<sol::object>(i);
            if (!entry.is<int>()) {
                throw sol::error("file-priorities must be an array of numbers");
            }
            int priority = entry.as<int>();
            if (priority < 0 || priority > 255) {
                throw sol::error("file-priority out of range");
            }
            atp.file_priorities.push_back(lt::download_priority_t(static_cast<std::uint8_t>(priority)));
        }
    }

    void set_piece_priorities(sol::table priorities_table)
    {
        atp.piece_priorities.clear();
        for (std::size_t i = 1; i <= priorities_table.size(); ++i) {
            sol::object entry = priorities_table.get<sol::object>(i);
            if (!entry.is<int>()) {
                throw sol::error("piece-priorities must be an array of numbers");
            }
            int priority = entry.as<int>();
            if (priority < 0 || priority > 255) {
                throw sol::error("piece-priority out of range");
            }
            atp.piece_priorities.push_back(lt::download_priority_t(static_cast<std::uint8_t>(priority)));
        }
    }

    std::string write_resume_data_buf() const
    {
        std::vector<char> data = lt::write_resume_data_buf(atp);
        return std::string(data.data(), data.size());
    }

    std::string write_torrent_file_buf() const
    {
        lt::entry torrent_entry = lt::write_torrent_file(atp);
        std::vector<char> data;
        lt::bencode(std::back_inserter(data), torrent_entry);
        return std::string(data.data(), data.size());
    }

    lt::add_torrent_params atp;
};

struct SessionParamsHandle
{
    explicit SessionParamsHandle(lt::session_params value)
        : params(std::move(value))
    {
    }

    sol::table to_table(sol::this_state ts) const
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();
        out["settings"] = settings_pack_to_table(lua, params.settings);
        sol::table ext_state = lua.create_table();
        for (const auto& kv : params.ext_state) {
            ext_state[kv.first] = kv.second;
        }
        out["ext-state"] = ext_state;
        return out;
    }

    void apply_settings(sol::table settings)
    {
        set_opt_str(settings, "listen-interfaces", params.settings, lt::settings_pack::listen_interfaces);
        set_opt_str(settings, "dht-bootstrap-nodes", params.settings, lt::settings_pack::dht_bootstrap_nodes);
        set_opt_str(settings, "user-agent", params.settings, lt::settings_pack::user_agent);
        set_opt_bool(settings, "enable-dht", params.settings, lt::settings_pack::enable_dht);
        set_opt_bool(settings, "announce-to-all-tiers", params.settings, lt::settings_pack::announce_to_all_tiers);
        set_opt_bool(settings, "announce-to-all-trackers", params.settings, lt::settings_pack::announce_to_all_trackers);
        set_opt_int(settings, "alert-mask", params.settings, lt::settings_pack::alert_mask);
        set_opt_int(settings, "download-rate-limit", params.settings, lt::settings_pack::download_rate_limit);
        set_opt_int(settings, "upload-rate-limit", params.settings, lt::settings_pack::upload_rate_limit);
        set_opt_int(settings, "connections-limit", params.settings, lt::settings_pack::connections_limit);
    }

    void set_ext_state(sol::table ext_state_table)
    {
        params.ext_state.clear();
        for (const auto& kv : ext_state_table) {
            if (!kv.first.is<std::string>()) {
                throw sol::error("ext-state keys must be strings");
            }
            if (!kv.second.is<std::string>()) {
                throw sol::error("ext-state values must be strings");
            }
            params.ext_state[kv.first.as<std::string>()] = kv.second.as<std::string>();
        }
    }

    lt::session_params params;
};

struct LibtorrentSession
{
    explicit LibtorrentSession(sol::table opts)
    {
        sol::object session_params_obj = opts.get<sol::object>("session-params");
        if (session_params_obj.is<std::shared_ptr<SessionParamsHandle>>()) {
            auto params_handle = session_params_obj.as<std::shared_ptr<SessionParamsHandle>>();
            session = std::make_unique<lt::session>(params_handle->params);
            return;
        }
        lt::settings_pack pack = make_settings(opts);
        lt::session_params params(pack);
        session = std::make_unique<lt::session>(std::move(params));
    }

    ~LibtorrentSession()
    {
        close();
    }

    void close()
    {
        if (!closed) {
            for (lt::alert* alert : pending_alerts) {
                if (alert != nullptr) {
                    release_direct_request_userdata(*alert);
                }
            }
            pending_alerts.clear();
            handles.clear();
            direct_request_userdata_ptr_to_id.clear();
            direct_request_userdata.clear();
            session.reset();
            closed = true;
        }
    }

    bool is_closed() const
    {
        return closed;
    }

    std::int64_t add_torrent_file(sol::table opts)
    {
        ensure_open("add-torrent-file");
        std::string torrent_path = opt_or<std::string>(opts, "torrent-path", "");
        std::string save_path = opt_or<std::string>(opts, "save-path", "");
        bool seed_mode = opt_or<bool>(opts, "seed-mode", false);

        if (torrent_path.empty()) {
            throw sol::error("libtorrent session add-torrent-file requires torrent-path");
        }
        if (save_path.empty()) {
            throw sol::error("libtorrent session add-torrent-file requires save-path");
        }

        lt::error_code ec;
        auto torrent_info = std::make_shared<lt::torrent_info>(torrent_path, ec);
        if (ec) {
            throw sol::error("failed to load torrent file: " + ec.message());
        }

        lt::add_torrent_params atp;
        atp.ti = std::move(torrent_info);
        atp.save_path = save_path;
        atp.trackers = read_trackers(opts);
        if (seed_mode) {
            atp.flags |= lt::torrent_flags::seed_mode;
        }

        lt::torrent_handle handle = session->add_torrent(atp, ec);
        if (ec) {
            throw sol::error("add-torrent-file failed: " + ec.message());
        }
        std::int64_t id = next_handle_id++;
        handles[id] = handle;
        return id;
    }

    std::int64_t add_info_hash(sol::table opts)
    {
        ensure_open("add-info-hash");
        std::string info_hash_hex = opt_or<std::string>(opts, "info-hash", "");
        std::string save_path = opt_or<std::string>(opts, "save-path", "");
        std::string name = opt_or<std::string>(opts, "name", "space-libtorrent");

        if (info_hash_hex.empty()) {
            throw sol::error("libtorrent session add-info-hash requires info-hash");
        }
        if (save_path.empty()) {
            throw sol::error("libtorrent session add-info-hash requires save-path");
        }

        std::array<char, 20> info_hash_data = sha1_from_hex(info_hash_hex);
        lt::add_torrent_params atp;
        atp.save_path = save_path;
        atp.name = name;
        atp.info_hashes = lt::info_hash_t(lt::sha1_hash(info_hash_data.data()));
        atp.trackers = read_trackers(opts);

        lt::error_code ec;
        lt::torrent_handle handle = session->add_torrent(atp, ec);
        if (ec) {
            throw sol::error("add-info-hash failed: " + ec.message());
        }
        std::int64_t id = next_handle_id++;
        handles[id] = handle;
        return id;
    }

    std::int64_t add_magnet_uri(const std::string& uri, sol::optional<sol::table> opts_opt)
    {
        ensure_open("add-magnet-uri");
        lt::error_code ec;
        lt::add_torrent_params atp = lt::parse_magnet_uri(uri, ec);
        if (ec) {
            throw sol::error("parse_magnet_uri failed: " + ec.message());
        }

        if (opts_opt) {
            sol::table opts = opts_opt.value();
            atp.save_path = opt_or<std::string>(opts, "save-path", atp.save_path);
            atp.name = opt_or<std::string>(opts, "name", atp.name);
            atp.trackers = read_trackers(opts);
        }

        if (atp.save_path.empty()) {
            throw sol::error("add-magnet-uri requires save-path");
        }

        lt::torrent_handle handle = session->add_torrent(atp, ec);
        if (ec) {
            throw sol::error("add-magnet-uri failed: " + ec.message());
        }
        std::int64_t id = next_handle_id++;
        handles[id] = handle;
        return id;
    }

    std::int64_t add_torrent_params(sol::table opts)
    {
        ensure_open("add-torrent-params");
        sol::object params_obj = opts.get<sol::object>("params");
        if (!params_obj.is<std::shared_ptr<AddTorrentParamsHandle>>()) {
            throw sol::error("add-torrent-params requires params handle");
        }
        auto params_handle = params_obj.as<std::shared_ptr<AddTorrentParamsHandle>>();
        lt::add_torrent_params atp = params_handle->atp;

        sol::optional<std::string> save_path = opts.get<sol::optional<std::string>>("save-path");
        if (save_path && !save_path.value().empty()) {
            atp.save_path = save_path.value();
        }

        lt::error_code ec;
        lt::torrent_handle handle = session->add_torrent(atp, ec);
        if (ec) {
            throw sol::error("add-torrent-params failed: " + ec.message());
        }
        std::int64_t id = next_handle_id++;
        handles[id] = handle;
        return id;
    }

    sol::table get_torrents(sol::this_state ts)
    {
        ensure_open("get-torrents");
        sol::state_view lua(ts);
        std::vector<lt::torrent_handle> torrents = session->get_torrents();
        sol::table out = lua.create_table(static_cast<int>(torrents.size()), 0);

        for (std::size_t i = 0; i < torrents.size(); ++i) {
            const lt::torrent_handle& handle = torrents[i];
            sol::table item = lua.create_table();
            item["is-valid"] = handle.is_valid();

            if (handle.is_valid()) {
                lt::torrent_status status = handle.status();
                item["name"] = status.name;
                item["progress"] = status.progress;
                item["is-seeding"] = status.is_seeding;
                item["state"] = torrent_state_name(status.state);

                lt::info_hash_t hashes = handle.info_hashes();
                if (hashes.has_v1()) {
                    item["info-hash-v1"] = hex_from_bytes(hashes.v1.data(), 20);
                } else {
                    item["info-hash-v1"] = sol::lua_nil;
                }

                std::int64_t id = 0;
                for (const auto& entry : handles) {
                    if (entry.second == handle) {
                        id = entry.first;
                        break;
                    }
                }
                if (id == 0) {
                    id = next_handle_id++;
                    handles[id] = handle;
                }
                item["handle-id"] = id;
            } else {
                item["name"] = sol::lua_nil;
                item["progress"] = sol::lua_nil;
                item["is-seeding"] = sol::lua_nil;
                item["state"] = sol::lua_nil;
                item["info-hash-v1"] = sol::lua_nil;
                item["handle-id"] = sol::lua_nil;
            }

            out[i + 1] = item;
        }

        return out;
    }

    sol::object find_torrent(sol::this_state ts, const std::string& info_hash_hex)
    {
        ensure_open("find-torrent");
        sol::state_view lua(ts);
        std::array<char, 20> info_hash_data = sha1_from_hex(info_hash_hex);
        lt::sha1_hash sha1(info_hash_data.data());
        lt::torrent_handle handle = session->find_torrent(sha1);
        if (!handle.is_valid()) {
            return sol::make_object(lua, sol::lua_nil);
        }

        for (const auto& entry : handles) {
            if (entry.second == handle) {
                return sol::make_object(lua, entry.first);
            }
        }

        std::int64_t id = next_handle_id++;
        handles[id] = handle;
        return sol::make_object(lua, id);
    }

    void force_reannounce(std::int64_t id)
    {
        get_handle(id, "force-reannounce").force_reannounce();
    }

    void pause_torrent(std::int64_t id)
    {
        get_handle(id, "pause-torrent").pause();
    }

    void resume_torrent(std::int64_t id)
    {
        get_handle(id, "resume-torrent").resume();
    }

    void set_torrent_download_limit(std::int64_t id, int limit)
    {
        get_handle(id, "set-torrent-download-limit").set_download_limit(limit);
    }

    int torrent_download_limit(std::int64_t id)
    {
        return get_handle(id, "torrent-download-limit").download_limit();
    }

    void set_torrent_upload_limit(std::int64_t id, int limit)
    {
        get_handle(id, "set-torrent-upload-limit").set_upload_limit(limit);
    }

    int torrent_upload_limit(std::int64_t id)
    {
        return get_handle(id, "torrent-upload-limit").upload_limit();
    }

    void set_torrent_max_connections(std::int64_t id, int value)
    {
        get_handle(id, "set-torrent-max-connections").set_max_connections(value);
    }

    int torrent_max_connections(std::int64_t id)
    {
        return get_handle(id, "torrent-max-connections").max_connections();
    }

    void set_torrent_max_uploads(std::int64_t id, int value)
    {
        get_handle(id, "set-torrent-max-uploads").set_max_uploads(value);
    }

    int torrent_max_uploads(std::int64_t id)
    {
        return get_handle(id, "torrent-max-uploads").max_uploads();
    }

    void set_torrent_piece_priorities(std::int64_t id, sol::table priorities)
    {
        lt::torrent_handle handle = get_handle(id, "set-torrent-piece-priorities");
        std::vector<lt::download_priority_t> values;
        values.reserve(priorities.size());
        for (std::size_t i = 1; i <= priorities.size(); ++i) {
            sol::object entry = priorities.get<sol::object>(i);
            if (!entry.is<int>()) {
                throw sol::error("piece-priorities must be an array of numbers");
            }
            int priority = entry.as<int>();
            if (priority < 0 || priority > 255) {
                throw sol::error("piece-priority out of range");
            }
            values.push_back(lt::download_priority_t(static_cast<std::uint8_t>(priority)));
        }
        handle.prioritize_pieces(values);
    }

    sol::table torrent_piece_priorities(sol::this_state ts, std::int64_t id)
    {
        sol::state_view lua(ts);
        lt::torrent_handle handle = get_handle(id, "torrent-piece-priorities");
        std::vector<lt::download_priority_t> values = handle.get_piece_priorities();
        sol::table out = lua.create_table(static_cast<int>(values.size()), 0);
        for (std::size_t i = 0; i < values.size(); ++i) {
            out[i + 1] = static_cast<int>(static_cast<std::uint8_t>(values[i]));
        }
        return out;
    }

    void set_torrent_file_priorities(std::int64_t id, sol::table priorities)
    {
        lt::torrent_handle handle = get_handle(id, "set-torrent-file-priorities");
        std::vector<lt::download_priority_t> values;
        values.reserve(priorities.size());
        for (std::size_t i = 1; i <= priorities.size(); ++i) {
            sol::object entry = priorities.get<sol::object>(i);
            if (!entry.is<int>()) {
                throw sol::error("file-priorities must be an array of numbers");
            }
            int priority = entry.as<int>();
            if (priority < 0 || priority > 255) {
                throw sol::error("file-priority out of range");
            }
            values.push_back(lt::download_priority_t(static_cast<std::uint8_t>(priority)));
        }
        handle.prioritize_files(values);
    }

    sol::table torrent_file_priorities(sol::this_state ts, std::int64_t id)
    {
        sol::state_view lua(ts);
        lt::torrent_handle handle = get_handle(id, "torrent-file-priorities");
        std::vector<lt::download_priority_t> values = handle.get_file_priorities();
        sol::table out = lua.create_table(static_cast<int>(values.size()), 0);
        for (std::size_t i = 0; i < values.size(); ++i) {
            out[i + 1] = static_cast<int>(static_cast<std::uint8_t>(values[i]));
        }
        return out;
    }

    void force_dht_announce(std::int64_t id)
    {
        get_handle(id, "force-dht-announce").force_dht_announce();
    }

    void remove_torrent(std::int64_t id, sol::optional<sol::table> opts_opt)
    {
        ensure_open("remove-torrent");
        lt::torrent_handle handle = get_handle(id, "remove-torrent");

        lt::remove_flags_t flags = {};
        if (opts_opt) {
            sol::table opts = opts_opt.value();
            bool delete_files = opt_or<bool>(opts, "delete-files", false);
            bool delete_partfile = opt_or<bool>(opts, "delete-partfile", false);
            if (delete_files) {
                flags |= lt::session::delete_files;
            }
            if (delete_partfile) {
                flags |= lt::session::delete_partfile;
            }
        }

        session->remove_torrent(handle, flags);
        handles.erase(id);
    }

    void pause()
    {
        ensure_open("pause");
        session->pause();
    }

    void resume()
    {
        ensure_open("resume");
        session->resume();
    }

    bool is_paused() const
    {
        ensure_open("is-paused");
        return session->is_paused();
    }

    void start_dht()
    {
        ensure_open("start-dht");
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
        session->start_dht();
#else
        lt::settings_pack pack = session->get_settings();
        pack.set_bool(lt::settings_pack::enable_dht, true);
        session->apply_settings(std::move(pack));
#endif
    }

    void stop_dht()
    {
        ensure_open("stop-dht");
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
        session->stop_dht();
#else
        lt::settings_pack pack = session->get_settings();
        pack.set_bool(lt::settings_pack::enable_dht, false);
        session->apply_settings(std::move(pack));
#endif
    }

    bool is_dht_running() const
    {
        ensure_open("is-dht-running");
        return session->is_dht_running();
    }

    void add_dht_node(sol::table node)
    {
        ensure_open("add-dht-node");
        sol::optional<std::string> host = node.get<sol::optional<std::string>>("host");
        sol::optional<int> port = node.get<sol::optional<int>>("port");
        if (!host || !port) {
            throw sol::error("add-dht-node requires host and port");
        }
        session->add_dht_node({ host.value(), port.value() });
    }

    void add_dht_router(sol::table node)
    {
        ensure_open("add-dht-router");
        sol::optional<std::string> host = node.get<sol::optional<std::string>>("host");
        sol::optional<int> port = node.get<sol::optional<int>>("port");
        if (!host || !port) {
            throw sol::error("add-dht-router requires host and port");
        }
#if TORRENT_ABI_VERSION == 1
        session->add_dht_router({ host.value(), port.value() });
#else
        throw sol::error("add-dht-router unavailable in this libtorrent ABI");
#endif
    }

    void dht_get_peers(const std::string& info_hash_hex)
    {
        ensure_open("dht-get-peers");
        std::array<char, 20> info_hash_data = sha1_from_hex(info_hash_hex);
        session->dht_get_peers(lt::sha1_hash(info_hash_data.data()));
    }

    void dht_announce(sol::table opts)
    {
        ensure_open("dht-announce");
        std::string info_hash_hex = opt_or<std::string>(opts, "info-hash", "");
        int port = opt_or<int>(opts, "port", 0);
        int flags = opt_or<int>(opts, "flags", 0);
        if (info_hash_hex.empty()) {
            throw sol::error("dht-announce requires info-hash");
        }
        std::array<char, 20> info_hash_data = sha1_from_hex(info_hash_hex);
        session->dht_announce(lt::sha1_hash(info_hash_data.data()),
            port,
            lt::dht::announce_flags_t(static_cast<std::uint8_t>(flags)));
    }

    void dht_live_nodes(const std::string& node_id_hex)
    {
        ensure_open("dht-live-nodes");
        std::array<char, 20> node_id_data = sha1_from_hex(node_id_hex);
        session->dht_live_nodes(lt::sha1_hash(node_id_data.data()));
    }

    void dht_sample_infohashes(sol::table opts)
    {
        ensure_open("dht-sample-infohashes");
        std::string host = opt_or<std::string>(opts, "host", "");
        int port = opt_or<int>(opts, "port", 0);
        std::string target_hex = opt_or<std::string>(opts, "target", "");
        if (host.empty()) {
            throw sol::error("dht-sample-infohashes requires host");
        }
        if (port <= 0) {
            throw sol::error("dht-sample-infohashes requires positive port");
        }
        if (target_hex.empty()) {
            throw sol::error("dht-sample-infohashes requires target");
        }
        std::array<char, 20> target_data = sha1_from_hex(target_hex);
        lt::error_code ec;
        lt::address addr = lt::make_address(host, ec);
        if (ec) {
            throw sol::error("dht-sample-infohashes invalid host: " + ec.message());
        }
        session->dht_sample_infohashes(lt::udp::endpoint(addr, static_cast<std::uint16_t>(port)),
            lt::sha1_hash(target_data.data()));
    }

    void dht_get_item(const std::string& target_hex)
    {
        ensure_open("dht-get-item");
        std::array<char, 20> target_data = sha1_from_hex(target_hex);
        session->dht_get_item(lt::sha1_hash(target_data.data()));
    }

    void dht_get_mutable_item(sol::table opts)
    {
        ensure_open("dht-get-mutable-item");
        std::string key_hex = opt_or<std::string>(opts, "public-key", "");
        std::string salt = opt_or<std::string>(opts, "salt", "");
        if (key_hex.empty()) {
            throw sol::error("dht-get-mutable-item requires public-key");
        }
        std::array<char, 32> key_data = fixed_bytes_from_hex<32>(key_hex, "public-key");
        session->dht_get_item(key_data, salt);
    }

    std::string dht_put_item(sol::object item)
    {
        ensure_open("dht-put-item");
        lt::entry data = lua_object_to_entry(item);
        lt::sha1_hash target = session->dht_put_item(std::move(data));
        return hex_from_bytes(target.data(), 20);
    }

    void dht_put_mutable_item(sol::table opts)
    {
        ensure_open("dht-put-mutable-item");
        std::string public_key_hex = opt_or<std::string>(opts, "public-key", "");
        std::string secret_key_hex = opt_or<std::string>(opts, "secret-key", "");
        std::string salt = opt_or<std::string>(opts, "salt", "");
        std::int64_t seq = static_cast<std::int64_t>(opt_or<int>(opts, "seq", 0));
        sol::object item_obj = opts.get<sol::object>("item");

        if (public_key_hex.empty() || secret_key_hex.empty()) {
            throw sol::error("dht-put-mutable-item requires public-key and secret-key");
        }
        if (item_obj == sol::lua_nil) {
            throw sol::error("dht-put-mutable-item requires item");
        }

        std::array<char, 32> public_key_data = fixed_bytes_from_hex<32>(public_key_hex, "public-key");
        std::array<char, 64> secret_key_data = fixed_bytes_from_hex<64>(secret_key_hex, "secret-key");
        lt::dht::public_key pk(public_key_data.data());
        lt::dht::secret_key sk(secret_key_data.data());
        lt::entry item_entry = lua_object_to_entry(item_obj);

        session->dht_put_item(public_key_data,
            [item_entry, salt, seq, pk, sk](lt::entry& value, std::array<char, 64>& sig_out, std::int64_t& seq_out,
                std::string const&) mutable {
                value = item_entry;
                seq_out = seq;
                std::vector<char> item_buf;
                lt::bencode(std::back_inserter(item_buf), item_entry);
                lt::dht::signature signature = lt::dht::sign_mutable_item(
                    lt::span<char const>(item_buf.data(), item_buf.size()),
                    lt::span<char const>(salt.data(), salt.size()),
                    lt::dht::sequence_number(seq),
                    pk,
                    sk);
                std::copy(signature.bytes.begin(), signature.bytes.end(), sig_out.begin());
            },
            salt);
    }

    void dht_direct_request(sol::table opts)
    {
        ensure_open("dht-direct-request");
        std::string host = opt_or<std::string>(opts, "host", "");
        int port = opt_or<int>(opts, "port", 0);
        sol::object request_obj = opts.get<sol::object>("request");
        sol::object userdata_obj = opts.get<sol::object>("userdata");
        if (host.empty()) {
            throw sol::error("dht-direct-request requires host");
        }
        if (port <= 0) {
            throw sol::error("dht-direct-request requires positive port");
        }
        if (request_obj == sol::lua_nil) {
            throw sol::error("dht-direct-request requires request");
        }
        lt::error_code ec;
        lt::address addr = lt::make_address(host, ec);
        if (ec) {
            throw sol::error("dht-direct-request invalid host: " + ec.message());
        }
        lt::entry request = lua_object_to_entry(request_obj);

        lt::client_data_t userdata {};
        if (userdata_obj != sol::lua_nil) {
            if (!userdata_obj.is<std::int64_t>() && !userdata_obj.is<int>()) {
                throw sol::error("dht-direct-request requires numeric userdata when provided");
            }
            std::int64_t userdata_id = userdata_obj.is<std::int64_t>()
                                           ? userdata_obj.as<std::int64_t>()
                                           : static_cast<std::int64_t>(userdata_obj.as<int>());

            auto existing = direct_request_userdata.find(userdata_id);
            if (existing != direct_request_userdata.end()) {
                direct_request_userdata_ptr_to_id.erase(existing->second.get());
                direct_request_userdata.erase(existing);
            }

            auto holder = std::make_unique<std::int64_t>(userdata_id);
            std::int64_t* userdata_ptr = holder.get();
            direct_request_userdata_ptr_to_id[userdata_ptr] = userdata_id;
            direct_request_userdata[userdata_id] = std::move(holder);
            userdata = lt::client_data_t(userdata_ptr);
        }

        session->dht_direct_request(lt::udp::endpoint(addr, static_cast<std::uint16_t>(port)), request, userdata);
    }

    void apply_settings(sol::table settings)
    {
        ensure_open("apply-settings");
        lt::settings_pack pack = session->get_settings();
        set_opt_str(settings, "listen-interfaces", pack, lt::settings_pack::listen_interfaces);
        set_opt_str(settings, "dht-bootstrap-nodes", pack, lt::settings_pack::dht_bootstrap_nodes);
        set_opt_str(settings, "user-agent", pack, lt::settings_pack::user_agent);
        set_opt_bool(settings, "enable-dht", pack, lt::settings_pack::enable_dht);
        set_opt_bool(settings, "announce-to-all-tiers", pack, lt::settings_pack::announce_to_all_tiers);
        set_opt_bool(settings, "announce-to-all-trackers", pack, lt::settings_pack::announce_to_all_trackers);
        set_opt_int(settings, "alert-mask", pack, lt::settings_pack::alert_mask);
        set_opt_int(settings, "download-rate-limit", pack, lt::settings_pack::download_rate_limit);
        set_opt_int(settings, "upload-rate-limit", pack, lt::settings_pack::upload_rate_limit);
        set_opt_int(settings, "connections-limit", pack, lt::settings_pack::connections_limit);
        session->apply_settings(std::move(pack));
    }

    void set_alert_mask(std::uint32_t mask)
    {
        ensure_open("set-alert-mask");
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
        session->set_alert_mask(lt::alert_category_t(mask));
#else
        lt::settings_pack pack = session->get_settings();
        pack.set_int(lt::settings_pack::alert_mask, static_cast<int>(mask));
        session->apply_settings(std::move(pack));
#endif
    }

    int set_alert_queue_size_limit(int limit)
    {
        ensure_open("set-alert-queue-size-limit");
        if (limit < 1) {
            limit = 1;
        }
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
        return session->set_alert_queue_size_limit(limit);
#else
        lt::settings_pack pack = session->get_settings();
        pack.set_int(lt::settings_pack::alert_queue_size, limit);
        session->apply_settings(std::move(pack));
        return limit;
#endif
    }

    sol::table get_settings(sol::this_state ts) const
    {
        ensure_open("get-settings");
        sol::state_view lua(ts);
        lt::settings_pack pack = session->get_settings();
        return settings_pack_to_table(lua, pack);
    }

    sol::table session_status(sol::this_state ts) const
    {
        ensure_open("session-status");
        sol::state_view lua(ts);
#if TORRENT_ABI_VERSION == 1 && !defined(TORRENT_NO_DEPRECATE)
        lt::session_status status = session->status();
        return session_status_to_table(lua, status);
#else
        return session_status_to_table(lua);
#endif
    }

    std::shared_ptr<SessionParamsHandle> session_state(sol::optional<std::uint32_t> flags_opt) const
    {
        ensure_open("session-state");
        lt::save_state_flags_t flags = flags_opt
                                           ? u32_to_save_state_flags(flags_opt.value())
                                           : lt::save_state_flags_t::all();
        lt::session_params state = session->session_state(flags);
        return std::make_shared<SessionParamsHandle>(std::move(state));
    }

    sol::table status(sol::this_state ts, std::int64_t id)
    {
        sol::state_view lua(ts);
        lt::torrent_status st = get_handle(id, "status").status();
        return status_to_table(lua, st);
    }

    sol::table torrent_info(sol::this_state ts, std::int64_t id)
    {
        sol::state_view lua(ts);
        lt::torrent_handle handle = get_handle(id, "torrent-info");
        sol::table result = lua.create_table();
        result["handle-id"] = id;
        result["is-valid"] = handle.is_valid();
        if (!handle.is_valid()) {
            result["name"] = sol::lua_nil;
            result["info-hash-v1"] = sol::lua_nil;
            return result;
        }

        lt::torrent_status st = handle.status();
        result["name"] = st.name;
        result["progress"] = st.progress;
        result["is-seeding"] = st.is_seeding;
        result["state"] = torrent_state_name(st.state);

        lt::info_hash_t hashes = handle.info_hashes();
        if (hashes.has_v1()) {
            result["info-hash-v1"] = hex_from_bytes(hashes.v1.data(), 20);
        } else {
            result["info-hash-v1"] = sol::lua_nil;
        }
        result["download-limit"] = handle.download_limit();
        result["upload-limit"] = handle.upload_limit();
        result["max-connections"] = handle.max_connections();
        result["max-uploads"] = handle.max_uploads();
        return result;
    }

    std::string make_magnet_uri(std::int64_t id)
    {
        lt::torrent_handle handle = get_handle(id, "make-magnet-uri");
        return lt::make_magnet_uri(handle);
    }

    sol::table wait_for_complete(sol::this_state ts, std::int64_t id, sol::optional<sol::table> opts_opt)
    {
        sol::state_view lua(ts);
        lt::torrent_handle handle = get_handle(id, "wait-for-complete");

        int timeout_secs = 180;
        int poll_ms = 500;
        if (opts_opt) {
            sol::table opts = opts_opt.value();
            timeout_secs = opt_or<int>(opts, "timeout-secs", timeout_secs);
            poll_ms = opt_or<int>(opts, "poll-ms", poll_ms);
        }
        if (timeout_secs <= 0) {
            timeout_secs = 1;
        }
        if (poll_ms <= 0) {
            poll_ms = 50;
        }

        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(timeout_secs);
        while (std::chrono::steady_clock::now() < deadline) {
            lt::torrent_status st = handle.status();
            if (st.errc) {
                sol::table result = lua.create_table();
                result["ok"] = false;
                result["timeout"] = false;
                result["error"] = st.errc.message();
                result["status"] = status_to_table(lua, st);
                return result;
            }
            if (st.is_seeding || st.progress_ppm >= 1000000) {
                sol::table result = lua.create_table();
                result["ok"] = true;
                result["timeout"] = false;
                result["error"] = sol::lua_nil;
                result["status"] = status_to_table(lua, st);
                return result;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(poll_ms));
        }

        lt::torrent_status st = handle.status();
        sol::table result = lua.create_table();
        result["ok"] = false;
        result["timeout"] = true;
        result["error"] = "timeout waiting for complete download";
        result["status"] = status_to_table(lua, st);
        return result;
    }

    sol::object wait_for_alert(sol::this_state ts, sol::optional<int> timeout_ms_opt)
    {
        ensure_open("wait-for-alert");
        sol::state_view lua(ts);

        if (!pending_alerts.empty()) {
            lt::alert* alert = pending_alerts.front();
            pending_alerts.pop_front();
            sol::table table = alert_to_table(lua, *alert);
            release_direct_request_userdata(*alert);
            return sol::make_object(lua, table);
        }

        int timeout_ms = timeout_ms_opt.value_or(0);
        if (timeout_ms < 0) {
            timeout_ms = 0;
        }
        lt::alert* alerted = session->wait_for_alert(std::chrono::milliseconds(timeout_ms));
        if (alerted == nullptr) {
            return sol::make_object(lua, sol::lua_nil);
        }

        std::vector<lt::alert*> alerts;
        session->pop_alerts(&alerts);
        if (alerts.empty()) {
            return sol::make_object(lua, sol::lua_nil);
        }

        for (lt::alert* item : alerts) {
            pending_alerts.push_back(item);
        }

        lt::alert* next = pending_alerts.front();
        pending_alerts.pop_front();
        sol::table table = alert_to_table(lua, *next);
        release_direct_request_userdata(*next);
        return sol::make_object(lua, table);
    }

    sol::table pop_alerts(sol::this_state ts)
    {
        ensure_open("pop-alerts");
        sol::state_view lua(ts);
        std::vector<lt::alert*> alerts;
        session->pop_alerts(&alerts);
        std::size_t total = pending_alerts.size() + alerts.size();
        sol::table out = lua.create_table(static_cast<int>(total), 0);
        std::size_t out_index = 1;
        while (!pending_alerts.empty()) {
            lt::alert* item = pending_alerts.front();
            pending_alerts.pop_front();
            out[out_index++] = alert_to_table(lua, *item);
            release_direct_request_userdata(*item);
        }
        for (std::size_t i = 0; i < alerts.size(); ++i) {
            out[out_index++] = alert_to_table(lua, *alerts[i]);
            release_direct_request_userdata(*alerts[i]);
        }
        return out;
    }

    void post_session_stats()
    {
        ensure_open("post-session-stats");
        session->post_session_stats();
    }

    void post_dht_stats()
    {
        ensure_open("post-dht-stats");
        session->post_dht_stats();
    }

    void post_torrent_updates()
    {
        ensure_open("post-torrent-updates");
        session->post_torrent_updates();
    }

private:
    void release_direct_request_userdata(const lt::alert& alert)
    {
        auto* direct_response = lt::alert_cast<lt::dht_direct_response_alert>(&alert);
        if (direct_response == nullptr) {
            return;
        }
        const std::int64_t* userdata = direct_response->userdata.get<std::int64_t>();
        if (userdata == nullptr) {
            return;
        }
        auto id_it = direct_request_userdata_ptr_to_id.find(userdata);
        if (id_it == direct_request_userdata_ptr_to_id.end()) {
            return;
        }
        std::int64_t id = id_it->second;
        direct_request_userdata_ptr_to_id.erase(id_it);
        direct_request_userdata.erase(id);
    }

    void ensure_open(const std::string& action) const
    {
        if (closed || session == nullptr) {
            throw sol::error("libtorrent session is closed: " + action);
        }
    }

    lt::torrent_handle get_handle(std::int64_t id, const std::string& action)
    {
        ensure_open(action);
        auto it = handles.find(id);
        if (it == handles.end()) {
            throw sol::error("unknown libtorrent handle id");
        }
        return it->second;
    }

    std::unique_ptr<lt::session> session;
    std::unordered_map<std::int64_t, lt::torrent_handle> handles;
    std::unordered_map<std::int64_t, std::unique_ptr<std::int64_t>> direct_request_userdata;
    std::unordered_map<const std::int64_t*, std::int64_t> direct_request_userdata_ptr_to_id;
    std::deque<lt::alert*> pending_alerts;
    std::int64_t next_handle_id { 1 };
    bool closed { false };
};

sol::table create_torrent(sol::state_view lua, sol::table opts)
{
    std::string source_path = opt_or<std::string>(opts, "source-path", "");
    std::string output_path = opt_or<std::string>(opts, "output-path", "");
    int piece_size = opt_or<int>(opts, "piece-size", 0);
    std::string creator = opt_or<std::string>(opts, "creator", "space/libtorrent");

    if (source_path.empty()) {
        throw sol::error("libtorrent.create-torrent requires source-path");
    }
    if (!fs::exists(source_path)) {
        throw sol::error("source-path does not exist: " + source_path);
    }

    lt::file_storage file_storage;
    lt::add_files(file_storage, source_path);
    if (file_storage.num_files() <= 0) {
        throw sol::error("source-path did not add any files to torrent");
    }

    if (output_path.empty()) {
        output_path = source_path + ".torrent";
    }

    lt::create_torrent torrent(file_storage, piece_size, lt::create_torrent::v1_only);
    torrent.set_creator(creator.c_str());

    std::vector<std::string> trackers = read_trackers(opts);
    for (const std::string& tracker : trackers) {
        torrent.add_tracker(tracker);
    }

    fs::path source_fs = fs::absolute(source_path);
    // set_piece_hashes expects the root containing the file-storage paths.
    // For both single-file and directory sources, add_files() stores paths
    // relative to the source parent.
    fs::path hash_root = source_fs.parent_path();
    if (hash_root.empty()) {
        hash_root = fs::current_path();
    }
    lt::error_code ec;
    lt::set_piece_hashes(torrent, hash_root.string(), ec);
    if (ec) {
        throw sol::error("set_piece_hashes failed: " + ec.message());
    }

    lt::entry torrent_entry = torrent.generate();
    std::vector<char> buffer;
    lt::bencode(std::back_inserter(buffer), torrent_entry);

    std::ofstream out(output_path, std::ios::binary);
    if (!out.is_open()) {
        throw sol::error("failed to open output-path for writing: " + output_path);
    }
    out.write(buffer.data(), static_cast<std::streamsize>(buffer.size()));
    out.close();

    lt::torrent_info info(buffer.data(), static_cast<int>(buffer.size()), ec);
    if (ec) {
        throw sol::error("failed to parse generated torrent: " + ec.message());
    }

    lt::info_hash_t hashes = info.info_hashes();
    std::string info_hash_v1 = hashes.has_v1()
                                   ? hex_from_bytes(hashes.v1.data(), 20)
                                   : std::string();

    sol::table result = lua.create_table();
    result["name"] = info.name();
    result["torrent-path"] = output_path;
    result["magnet-uri"] = lt::make_magnet_uri(info);
    result["info-hash-v1"] = info_hash_v1;
    result["total-size"] = static_cast<std::int64_t>(info.total_size());
    sol::table trackers_table = lua.create_table();
    for (std::size_t i = 0; i < trackers.size(); ++i) {
        trackers_table[i + 1] = trackers[i];
    }
    result["trackers"] = trackers_table;
    return result;
}

sol::table parse_magnet_uri(sol::state_view lua, const std::string& uri)
{
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(uri, ec);
    if (ec) {
        throw sol::error("parse_magnet_uri failed: " + ec.message());
    }

    sol::table out = lua.create_table();
    if (atp.info_hashes.has_v1()) {
        out["info-hash"] = hex_from_bytes(atp.info_hashes.v1.data(), 20);
    } else {
        out["info-hash"] = sol::lua_nil;
    }
    out["name"] = atp.name;
    out["save-path"] = atp.save_path;
    sol::table trackers = lua.create_table();
    for (std::size_t i = 0; i < atp.trackers.size(); ++i) {
        trackers[i + 1] = atp.trackers[i];
    }
    out["trackers"] = trackers;
    return out;
}

sol::table torrent_info_to_table(sol::state_view lua, const lt::torrent_info& info)
{
    sol::table result = lua.create_table();
    result["name"] = info.name();
    result["total-size"] = static_cast<std::int64_t>(info.total_size());
    result["num-files"] = info.num_files();
    result["num-pieces"] = info.num_pieces();
    result["piece-length"] = info.piece_length();
    result["is-private"] = info.priv();

    lt::info_hash_t hashes = info.info_hashes();
    if (hashes.has_v1()) {
        result["info-hash-v1"] = hex_from_bytes(hashes.v1.data(), 20);
    } else {
        result["info-hash-v1"] = sol::lua_nil;
    }
    result["magnet-uri"] = lt::make_magnet_uri(info);

    sol::table trackers = lua.create_table();
    std::vector<lt::announce_entry> entries = info.trackers();
    for (std::size_t i = 0; i < entries.size(); ++i) {
        trackers[i + 1] = entries[i].url;
    }
    result["trackers"] = trackers;
    return result;
}

sol::table load_torrent_file(sol::state_view lua, const std::string& torrent_path)
{
    lt::error_code ec;
    lt::torrent_info info(torrent_path, ec);
    if (ec) {
        throw sol::error("failed to load torrent file: " + ec.message());
    }
    return torrent_info_to_table(lua, info);
}

sol::table load_torrent_buffer(sol::state_view lua, const std::string& buffer)
{
    lt::error_code ec;
    lt::torrent_info info(buffer.data(), static_cast<int>(buffer.size()), ec);
    if (ec) {
        throw sol::error("failed to load torrent buffer: " + ec.message());
    }
    return torrent_info_to_table(lua, info);
}

std::shared_ptr<AddTorrentParamsHandle> load_torrent_file_params(const std::string& path)
{
    lt::error_code ec;
    auto info = std::make_shared<lt::torrent_info>(path, ec);
    if (ec) {
        throw sol::error("failed to load torrent file: " + ec.message());
    }
    lt::add_torrent_params atp;
    atp.ti = std::move(info);
    atp.name = atp.ti->name();
    atp.info_hashes = atp.ti->info_hashes();
    return std::make_shared<AddTorrentParamsHandle>(std::move(atp));
}

std::shared_ptr<AddTorrentParamsHandle> load_torrent_buffer_params(const std::string& buffer)
{
    lt::error_code ec;
    auto info = std::make_shared<lt::torrent_info>(buffer.data(), static_cast<int>(buffer.size()), ec);
    if (ec) {
        throw sol::error("failed to load torrent buffer: " + ec.message());
    }
    lt::add_torrent_params atp;
    atp.ti = std::move(info);
    atp.name = atp.ti->name();
    atp.info_hashes = atp.ti->info_hashes();
    return std::make_shared<AddTorrentParamsHandle>(std::move(atp));
}

std::shared_ptr<AddTorrentParamsHandle> load_torrent_parsed_params(sol::object parsed)
{
    lt::entry parsed_entry = lua_object_to_entry(parsed);
    std::vector<char> data;
    lt::bencode(std::back_inserter(data), parsed_entry);
    return load_torrent_buffer_params(std::string(data.data(), data.size()));
}

std::shared_ptr<AddTorrentParamsHandle> parse_magnet_uri_params(const std::string& uri)
{
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(uri, ec);
    if (ec) {
        throw sol::error("parse_magnet_uri failed: " + ec.message());
    }
    return std::make_shared<AddTorrentParamsHandle>(std::move(atp));
}

std::shared_ptr<AddTorrentParamsHandle> read_resume_data_params(const std::string& buffer)
{
    lt::error_code ec;
    lt::add_torrent_params atp = lt::read_resume_data(lt::span<char const>(buffer.data(), buffer.size()), ec);
    if (ec) {
        throw sol::error("read_resume_data failed: " + ec.message());
    }
    return std::make_shared<AddTorrentParamsHandle>(std::move(atp));
}

std::string make_magnet_uri_from_torrent(const std::string& torrent_path)
{
    lt::error_code ec;
    lt::torrent_info ti(torrent_path, ec);
    if (ec) {
        throw sol::error("failed to load torrent file: " + ec.message());
    }
    return lt::make_magnet_uri(ti);
}

std::string make_magnet_uri_from_params(const std::shared_ptr<AddTorrentParamsHandle>& params)
{
    if (params == nullptr) {
        throw sol::error("make-magnet-uri-from-params requires params handle");
    }
    if (params->atp.ti) {
        return lt::make_magnet_uri(*params->atp.ti);
    }
    if (!params->atp.info_hashes.has_v1()) {
        throw sol::error("make-magnet-uri-from-params requires torrent-info or v1 info-hash");
    }
    return "magnet:?xt=urn:btih:" + hex_from_bytes(params->atp.info_hashes.v1.data(), 20);
}

std::string bencode_lua_object(sol::object value)
{
    lt::entry parsed_entry = lua_object_to_entry(value);
    std::vector<char> data;
    lt::bencode(std::back_inserter(data), parsed_entry);
    return std::string(data.data(), data.size());
}

sol::object bdecode_buffer(sol::this_state ts, const std::string& buffer)
{
    sol::state_view lua(ts);
    lt::error_code ec;
    lt::bdecode_node root = lt::bdecode(lt::span<char const>(buffer.data(), buffer.size()), ec);
    if (ec) {
        throw sol::error("bdecode failed: " + ec.message());
    }
    lt::entry decoded(root);
    return entry_to_lua_object(lua, decoded);
}

std::string write_torrent_file_buf_from_params(const std::shared_ptr<AddTorrentParamsHandle>& params)
{
    if (params == nullptr) {
        throw sol::error("write-torrent-file-buf requires params handle");
    }
    return params->write_torrent_file_buf();
}

sol::object write_torrent_file_from_params(sol::this_state ts, const std::shared_ptr<AddTorrentParamsHandle>& params)
{
    return bdecode_buffer(ts, write_torrent_file_buf_from_params(params));
}

std::shared_ptr<SessionParamsHandle> create_session_params(sol::optional<sol::table> opts_opt)
{
    lt::session_params params;
    if (opts_opt) {
        sol::table opts = opts_opt.value();
        sol::optional<sol::table> settings_opt = opts.get<sol::optional<sol::table>>("settings");
        if (settings_opt) {
            SessionParamsHandle handle(std::move(params));
            handle.apply_settings(settings_opt.value());
            params = std::move(handle.params);
        }
        sol::optional<sol::table> ext_state_opt = opts.get<sol::optional<sol::table>>("ext-state");
        if (ext_state_opt) {
            SessionParamsHandle handle(std::move(params));
            handle.set_ext_state(ext_state_opt.value());
            params = std::move(handle.params);
        }
    }
    return std::make_shared<SessionParamsHandle>(std::move(params));
}

std::shared_ptr<SessionParamsHandle> read_session_params_from_buffer(const std::string& buffer,
    sol::optional<std::uint32_t> flags_opt)
{
    lt::save_state_flags_t flags = flags_opt
                                       ? u32_to_save_state_flags(flags_opt.value())
                                       : lt::save_state_flags_t::all();
    lt::session_params params = lt::read_session_params(lt::span<char const>(buffer.data(), buffer.size()), flags);
    return std::make_shared<SessionParamsHandle>(std::move(params));
}

std::string write_session_params_buf_from_handle(const std::shared_ptr<SessionParamsHandle>& handle,
    sol::optional<std::uint32_t> flags_opt)
{
    if (handle == nullptr) {
        throw sol::error("write-session-params-buf requires session-params handle");
    }
    lt::save_state_flags_t flags = flags_opt
                                       ? u32_to_save_state_flags(flags_opt.value())
                                       : lt::save_state_flags_t::all();
    std::vector<char> out = lt::write_session_params_buf(handle->params, flags);
    return std::string(out.data(), out.size());
}

sol::object write_session_params_from_handle(sol::this_state ts, const std::shared_ptr<SessionParamsHandle>& handle,
    sol::optional<std::uint32_t> flags_opt)
{
    return bdecode_buffer(ts, write_session_params_buf_from_handle(handle, flags_opt));
}

std::shared_ptr<AddTorrentParamsHandle> read_resume_data(const std::string& buffer)
{
    lt::error_code ec;
    lt::add_torrent_params atp = lt::read_resume_data(lt::span<char const>(buffer.data(), buffer.size()), ec);
    if (ec) {
        throw sol::error("read_resume_data failed: " + ec.message());
    }
    return std::make_shared<AddTorrentParamsHandle>(std::move(atp));
}

std::string write_resume_data_buf_from_params(const std::shared_ptr<AddTorrentParamsHandle>& params)
{
    if (params == nullptr) {
        throw sol::error("write-resume-data-buf requires params handle");
    }
    return params->write_resume_data_buf();
}

sol::object write_resume_data_from_params(sol::this_state ts, const std::shared_ptr<AddTorrentParamsHandle>& params)
{
    return bdecode_buffer(ts, write_resume_data_buf_from_params(params));
}

std::string ed25519_create_seed_hex()
{
    std::array<char, 32> seed = lt::dht::ed25519_create_seed();
    return hex_from_bytes(seed.data(), seed.size());
}

sol::table ed25519_create_keypair_hex(sol::this_state ts, const std::string& seed_hex)
{
    sol::state_view lua(ts);
    std::array<char, 32> seed = fixed_bytes_from_hex<32>(seed_hex, "seed");
    auto [pk, sk] = lt::dht::ed25519_create_keypair(seed);
    sol::table out = lua.create_table();
    out["public-key"] = hex_from_bytes(pk.bytes.data(), pk.bytes.size());
    out["secret-key"] = hex_from_bytes(sk.bytes.data(), sk.bytes.size());
    return out;
}

std::string sign_mutable_item_hex(sol::table opts)
{
    sol::object item_obj = opts.get<sol::object>("item");
    if (item_obj == sol::lua_nil) {
        throw sol::error("sign-mutable-item requires item");
    }
    std::string public_key_hex = opt_or<std::string>(opts, "public-key", "");
    std::string secret_key_hex = opt_or<std::string>(opts, "secret-key", "");
    std::string salt = opt_or<std::string>(opts, "salt", "");
    std::int64_t seq = static_cast<std::int64_t>(opt_or<int>(opts, "seq", 0));
    if (public_key_hex.empty() || secret_key_hex.empty()) {
        throw sol::error("sign-mutable-item requires public-key and secret-key");
    }

    lt::entry item_entry = lua_object_to_entry(item_obj);
    std::vector<char> item_buf;
    lt::bencode(std::back_inserter(item_buf), item_entry);

    std::array<char, 32> public_key_data = fixed_bytes_from_hex<32>(public_key_hex, "public-key");
    std::array<char, 64> secret_key_data = fixed_bytes_from_hex<64>(secret_key_hex, "secret-key");
    lt::dht::public_key pk(public_key_data.data());
    lt::dht::secret_key sk(secret_key_data.data());
    lt::dht::signature sig = lt::dht::sign_mutable_item(
        lt::span<char const>(item_buf.data(), item_buf.size()),
        lt::span<char const>(salt.data(), salt.size()),
        lt::dht::sequence_number(seq),
        pk,
        sk);
    return hex_from_bytes(sig.bytes.data(), sig.bytes.size());
}

bool verify_mutable_item_signature(sol::table opts)
{
    (void)opts;
    throw sol::error("verify-mutable-item unavailable in this libtorrent build");
}

std::string operation_name_from_code(int op)
{
    return std::string(lt::operation_name(static_cast<lt::operation_t>(op)));
}

std::string libtorrent_category_name()
{
    return lt::libtorrent_category().name();
}

std::string http_category_name()
{
    return lt::http_category().name();
}

std::string socks_category_name()
{
    return lt::socks_category().name();
}

std::string upnp_category_name()
{
    return lt::upnp_category().name();
}

std::string i2p_category_name()
{
    return lt::i2p_category().name();
}

std::string system_category_name()
{
    return boost::system::system_category().name();
}

std::string generic_category_name()
{
    return boost::system::generic_category().name();
}

std::string bdecode_category_name()
{
    return lt::bdecode_category().name();
}

sol::table create_libtorrent_table(sol::state_view lua)
{
    sol::table module = lua.create_table();

    module["available"] = true;
    module["missing-reason"] = sol::lua_nil;

    module.new_usertype<LibtorrentSession>("SessionHandle",
        sol::no_constructor,
        "add-torrent-file", &LibtorrentSession::add_torrent_file,
        "add-info-hash", &LibtorrentSession::add_info_hash,
        "add-magnet-uri", &LibtorrentSession::add_magnet_uri,
        "add-torrent-params", &LibtorrentSession::add_torrent_params,
        "get-torrents", &LibtorrentSession::get_torrents,
        "find-torrent", &LibtorrentSession::find_torrent,
        "apply-settings", &LibtorrentSession::apply_settings,
        "pause-torrent", &LibtorrentSession::pause_torrent,
        "resume-torrent", &LibtorrentSession::resume_torrent,
        "set-torrent-download-limit", &LibtorrentSession::set_torrent_download_limit,
        "torrent-download-limit", &LibtorrentSession::torrent_download_limit,
        "set-torrent-upload-limit", &LibtorrentSession::set_torrent_upload_limit,
        "torrent-upload-limit", &LibtorrentSession::torrent_upload_limit,
        "set-torrent-max-connections", &LibtorrentSession::set_torrent_max_connections,
        "torrent-max-connections", &LibtorrentSession::torrent_max_connections,
        "set-torrent-max-uploads", &LibtorrentSession::set_torrent_max_uploads,
        "torrent-max-uploads", &LibtorrentSession::torrent_max_uploads,
        "set-torrent-piece-priorities", &LibtorrentSession::set_torrent_piece_priorities,
        "torrent-piece-priorities", &LibtorrentSession::torrent_piece_priorities,
        "set-torrent-file-priorities", &LibtorrentSession::set_torrent_file_priorities,
        "torrent-file-priorities", &LibtorrentSession::torrent_file_priorities,
        "set-alert-mask", &LibtorrentSession::set_alert_mask,
        "set-alert-queue-size-limit", &LibtorrentSession::set_alert_queue_size_limit,
        "get-settings", &LibtorrentSession::get_settings,
        "pause", &LibtorrentSession::pause,
        "resume", &LibtorrentSession::resume,
        "is-paused", &LibtorrentSession::is_paused,
        "start-dht", &LibtorrentSession::start_dht,
        "stop-dht", &LibtorrentSession::stop_dht,
        "is-dht-running", &LibtorrentSession::is_dht_running,
        "add-dht-node", &LibtorrentSession::add_dht_node,
        "add-dht-router", &LibtorrentSession::add_dht_router,
        "dht-get-peers", &LibtorrentSession::dht_get_peers,
        "dht-announce", &LibtorrentSession::dht_announce,
        "dht-live-nodes", &LibtorrentSession::dht_live_nodes,
        "dht-sample-infohashes", &LibtorrentSession::dht_sample_infohashes,
        "dht-get-item", &LibtorrentSession::dht_get_item,
        "dht-get-mutable-item", &LibtorrentSession::dht_get_mutable_item,
        "dht-put-item", &LibtorrentSession::dht_put_item,
        "dht-put-mutable-item", &LibtorrentSession::dht_put_mutable_item,
        "dht-direct-request", &LibtorrentSession::dht_direct_request,
        "session-status", &LibtorrentSession::session_status,
        "session-state", &LibtorrentSession::session_state,
        "wait-for-alert", &LibtorrentSession::wait_for_alert,
        "pop-alerts", &LibtorrentSession::pop_alerts,
        "post-session-stats", &LibtorrentSession::post_session_stats,
        "post-dht-stats", &LibtorrentSession::post_dht_stats,
        "post-torrent-updates", &LibtorrentSession::post_torrent_updates,
        "force-reannounce", &LibtorrentSession::force_reannounce,
        "force-dht-announce", &LibtorrentSession::force_dht_announce,
        "remove-torrent", &LibtorrentSession::remove_torrent,
        "status", &LibtorrentSession::status,
        "torrent-info", &LibtorrentSession::torrent_info,
        "make-magnet-uri", &LibtorrentSession::make_magnet_uri,
        "wait-for-complete", &LibtorrentSession::wait_for_complete,
        "drop", &LibtorrentSession::close,
        "is-closed", &LibtorrentSession::is_closed);

    module.new_usertype<AddTorrentParamsHandle>("AddTorrentParamsHandle",
        sol::no_constructor,
        "to-table", &AddTorrentParamsHandle::to_table,
        "set-save-path", &AddTorrentParamsHandle::set_save_path,
        "set-name", &AddTorrentParamsHandle::set_name,
        "set-trackers", &AddTorrentParamsHandle::set_trackers,
        "get-flags", &AddTorrentParamsHandle::get_flags,
        "set-flags", &AddTorrentParamsHandle::set_flags,
        "or-flags", &AddTorrentParamsHandle::or_flags,
        "clear-flags", &AddTorrentParamsHandle::clear_flags,
        "set-upload-limit", &AddTorrentParamsHandle::set_upload_limit,
        "set-download-limit", &AddTorrentParamsHandle::set_download_limit,
        "set-max-connections", &AddTorrentParamsHandle::set_max_connections,
        "set-max-uploads", &AddTorrentParamsHandle::set_max_uploads,
        "set-storage-mode", &AddTorrentParamsHandle::set_storage_mode,
        "set-tracker-tiers", &AddTorrentParamsHandle::set_tracker_tiers,
        "set-url-seeds", &AddTorrentParamsHandle::set_url_seeds,
        "set-dht-nodes", &AddTorrentParamsHandle::set_dht_nodes,
        "set-file-priorities", &AddTorrentParamsHandle::set_file_priorities,
        "set-piece-priorities", &AddTorrentParamsHandle::set_piece_priorities,
        "write-resume-data-buf", &AddTorrentParamsHandle::write_resume_data_buf,
        "write-torrent-file-buf", &AddTorrentParamsHandle::write_torrent_file_buf);

    module.new_usertype<SessionParamsHandle>("SessionParamsHandle",
        sol::no_constructor,
        "to-table", &SessionParamsHandle::to_table,
        "apply-settings", &SessionParamsHandle::apply_settings,
        "set-ext-state", &SessionParamsHandle::set_ext_state);
    module.new_usertype<BencodeListValue>("BencodeListValue",
        sol::no_constructor);
    module.new_usertype<BencodeDictValue>("BencodeDictValue",
        sol::no_constructor);

    module.set_function("Session", [](sol::table opts) {
        return std::make_shared<LibtorrentSession>(opts);
    });
    module.set_function("session", [](sol::this_state ts, sol::optional<sol::table> opts) {
        if (opts) {
            return std::make_shared<LibtorrentSession>(opts.value());
        }
        sol::state_view lua(ts);
        return std::make_shared<LibtorrentSession>(lua.create_table());
    });
    module.set_function("session-params", &create_session_params);
    module.set_function("list", [](sol::table values) {
        return std::make_shared<BencodeListValue>(values);
    });
    module.set_function("dict", [](sol::table values) {
        return std::make_shared<BencodeDictValue>(values);
    });
    module.set_function("ed25519-create-seed", &ed25519_create_seed_hex);
    module.set_function("ed25519-create-keypair", &ed25519_create_keypair_hex);
    module.set_function("sign-mutable-item", &sign_mutable_item_hex);
    module.set_function("verify-mutable-item", &verify_mutable_item_signature);
    module.set_function("operation-name", &operation_name_from_code);
    module.set_function("libtorrent-category-name", &libtorrent_category_name);
    module.set_function("http-category-name", &http_category_name);
    module.set_function("socks-category-name", &socks_category_name);
    module.set_function("upnp-category-name", &upnp_category_name);
    module.set_function("i2p-category-name", &i2p_category_name);
    module.set_function("system-category-name", &system_category_name);
    module.set_function("generic-category-name", &generic_category_name);
    module.set_function("bdecode-category-name", &bdecode_category_name);

    module.set_function("create-torrent", [lua](sol::table opts) {
        return create_torrent(lua, opts);
    });
    module.set_function("bencode", &bencode_lua_object);
    module.set_function("bdecode", &bdecode_buffer);
    module.set_function("parse-magnet-uri", [lua](const std::string& uri) {
        return parse_magnet_uri(lua, uri);
    });
    module.set_function("parse-magnet-uri-dict", [lua](const std::string& uri) {
        return parse_magnet_uri(lua, uri);
    });
    module.set_function("make-magnet-uri", &make_magnet_uri_from_torrent);
    module.set_function("make-magnet-uri-from-params", &make_magnet_uri_from_params);
    module.set_function("load-torrent-file", [lua](const std::string& torrent_path) {
        return load_torrent_file(lua, torrent_path);
    });
    module.set_function("load-torrent-buffer", [lua](const std::string& buffer) {
        return load_torrent_buffer(lua, buffer);
    });
    module.set_function("add-magnet-uri", [](LibtorrentSession& ses, const std::string& uri, sol::optional<sol::table> opts) {
        return ses.add_magnet_uri(uri, opts);
    });
    module.set_function("parse-magnet-uri-params", &parse_magnet_uri_params);
    module.set_function("load-torrent-file-params", &load_torrent_file_params);
    module.set_function("load-torrent-buffer-params", &load_torrent_buffer_params);
    module.set_function("load-torrent-parsed", &load_torrent_parsed_params);
    module.set_function("read-resume-data", &read_resume_data);
    module.set_function("read-resume-data-params", &read_resume_data_params);
    module.set_function("write-resume-data", &write_resume_data_from_params);
    module.set_function("write-resume-data-buf", &write_resume_data_buf_from_params);
    module.set_function("write-torrent-file", &write_torrent_file_from_params);
    module.set_function("write-torrent-file-buf", &write_torrent_file_buf_from_params);
    module.set_function("read-session-params", &read_session_params_from_buffer);
    module.set_function("write-session-params", &write_session_params_from_handle);
    module.set_function("write-session-params-buf", &write_session_params_buf_from_handle);

    module.set_function("version", []() {
        return std::string(lt::version());
    });
    module.set_function("default-settings", [lua]() {
        return settings_pack_to_table(lua, lt::default_settings());
    });
    module.set_function("high-performance-seed", [lua]() {
        return settings_pack_to_table(lua, lt::high_performance_seed());
    });
    module.set_function("min-memory-usage", [lua]() {
        return settings_pack_to_table(lua, lt::min_memory_usage());
    });
    module.set_function("session-stats-metrics", [lua]() {
        return session_stats_metrics_to_table(lua);
    });
    module.set_function("find-metric-idx", [](const std::string& name) {
        return lt::find_metric_idx(name);
    });
    module["torrent-flags"] = torrent_flags_to_table(lua);
    module["storage-modes"] = storage_modes_to_table(lua);
    module["save-state-flags"] = save_state_flags_to_table(lua);
    module["dht-announce-flags"] = dht_announce_flags_to_table(lua);

    return module;
}

} // namespace

void lua_bind_libtorrent(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("libtorrent", [](sol::this_state state) {
        sol::state_view lua_view(state);
        return create_libtorrent_table(lua_view);
    });
}

#else

void lua_bind_libtorrent(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("libtorrent", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table module = lua_view.create_table();
        module["available"] = false;
        module["missing-reason"] = "libtorrent unavailable (install libtorrent-rasterbar-dev and rebuild)";
        module["torrent-flags"] = lua_view.create_table();
        module["storage-modes"] = lua_view.create_table();
        module["save-state-flags"] = lua_view.create_table();
        module["dht-announce-flags"] = lua_view.create_table();
        auto unavailable = []() {
            throw sol::error("libtorrent unavailable (install libtorrent-rasterbar-dev and rebuild)");
        };
        module.set_function("Session", unavailable);
        module.set_function("create-torrent", unavailable);
        module.set_function("bencode", unavailable);
        module.set_function("bdecode", unavailable);
        module.set_function("session", unavailable);
        module.set_function("session-params", unavailable);
        module.set_function("list", unavailable);
        module.set_function("dict", unavailable);
        module.set_function("parse-magnet-uri", unavailable);
        module.set_function("parse-magnet-uri-dict", unavailable);
        module.set_function("make-magnet-uri", unavailable);
        module.set_function("make-magnet-uri-from-params", unavailable);
        module.set_function("load-torrent-file", unavailable);
        module.set_function("load-torrent-buffer", unavailable);
        module.set_function("load-torrent-file-params", unavailable);
        module.set_function("load-torrent-buffer-params", unavailable);
        module.set_function("parse-magnet-uri-params", unavailable);
        module.set_function("read-resume-data", unavailable);
        module.set_function("read-resume-data-params", unavailable);
        module.set_function("write-resume-data", unavailable);
        module.set_function("write-resume-data-buf", unavailable);
        module.set_function("read-session-params", unavailable);
        module.set_function("write-session-params", unavailable);
        module.set_function("write-session-params-buf", unavailable);
        module.set_function("load-torrent-parsed", unavailable);
        module.set_function("write-torrent-file", unavailable);
        module.set_function("write-torrent-file-buf", unavailable);
        module.set_function("add-magnet-uri", unavailable);
        module.set_function("add-torrent-file", unavailable);
        module.set_function("add-info-hash", unavailable);
        module.set_function("add-torrent-params", unavailable);
        module.set_function("get-torrents", unavailable);
        module.set_function("find-torrent", unavailable);
        module.set_function("pause-torrent", unavailable);
        module.set_function("resume-torrent", unavailable);
        module.set_function("set-torrent-download-limit", unavailable);
        module.set_function("torrent-download-limit", unavailable);
        module.set_function("set-torrent-upload-limit", unavailable);
        module.set_function("torrent-upload-limit", unavailable);
        module.set_function("set-torrent-max-connections", unavailable);
        module.set_function("torrent-max-connections", unavailable);
        module.set_function("set-torrent-max-uploads", unavailable);
        module.set_function("torrent-max-uploads", unavailable);
        module.set_function("set-torrent-piece-priorities", unavailable);
        module.set_function("torrent-piece-priorities", unavailable);
        module.set_function("set-torrent-file-priorities", unavailable);
        module.set_function("torrent-file-priorities", unavailable);
        module.set_function("wait-for-complete", unavailable);
        module.set_function("force-dht-announce", unavailable);
        module.set_function("force-reannounce", unavailable);
        module.set_function("remove-torrent", unavailable);
        module.set_function("drop", unavailable);
        module.set_function("is-closed", unavailable);
        module.set_function("status", unavailable);
        module.set_function("torrent-info", unavailable);
        module.set_function("apply-settings", unavailable);
        module.set_function("set-alert-mask", unavailable);
        module.set_function("set-alert-queue-size-limit", unavailable);
        module.set_function("get-settings", unavailable);
        module.set_function("pause", unavailable);
        module.set_function("resume", unavailable);
        module.set_function("is-paused", unavailable);
        module.set_function("start-dht", unavailable);
        module.set_function("stop-dht", unavailable);
        module.set_function("is-dht-running", unavailable);
        module.set_function("add-dht-node", unavailable);
        module.set_function("add-dht-router", unavailable);
        module.set_function("dht-get-peers", unavailable);
        module.set_function("dht-announce", unavailable);
        module.set_function("dht-live-nodes", unavailable);
        module.set_function("dht-sample-infohashes", unavailable);
        module.set_function("dht-get-item", unavailable);
        module.set_function("dht-get-mutable-item", unavailable);
        module.set_function("dht-put-item", unavailable);
        module.set_function("dht-put-mutable-item", unavailable);
        module.set_function("dht-direct-request", unavailable);
        module.set_function("ed25519-create-seed", unavailable);
        module.set_function("ed25519-create-keypair", unavailable);
        module.set_function("sign-mutable-item", unavailable);
        module.set_function("verify-mutable-item", unavailable);
        module.set_function("operation-name", unavailable);
        module.set_function("libtorrent-category-name", unavailable);
        module.set_function("http-category-name", unavailable);
        module.set_function("socks-category-name", unavailable);
        module.set_function("upnp-category-name", unavailable);
        module.set_function("i2p-category-name", unavailable);
        module.set_function("system-category-name", unavailable);
        module.set_function("generic-category-name", unavailable);
        module.set_function("bdecode-category-name", unavailable);
        module.set_function("session-status", unavailable);
        module.set_function("wait-for-alert", unavailable);
        module.set_function("pop-alerts", unavailable);
        module.set_function("post-session-stats", unavailable);
        module.set_function("post-dht-stats", unavailable);
        module.set_function("post-torrent-updates", unavailable);
        module.set_function("session-stats-metrics", unavailable);
        module.set_function("find-metric-idx", unavailable);
        module.set_function("default-settings", unavailable);
        module.set_function("high-performance-seed", unavailable);
        module.set_function("min-memory-usage", unavailable);
        module.set_function("version", []() {
            return std::string("unavailable");
        });
        return module;
    });
}

#endif
