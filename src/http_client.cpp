#include "http_client.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <curl/curl.h>
#include <stdexcept>
#include <utility>

namespace {

std::size_t write_body(char* ptr, std::size_t size, std::size_t nmemb, void* userdata)
{
    std::string* body = static_cast<std::string*>(userdata);
    body->append(ptr, size * nmemb);
    return size * nmemb;
}

std::size_t write_header(char* buffer, std::size_t size, std::size_t nitems, void* userdata)
{
    std::vector<std::pair<std::string, std::string>>* headers =
        static_cast<std::vector<std::pair<std::string, std::string>>*>(userdata);

    const std::size_t total = size * nitems;
    std::string line(buffer, total);

    auto colon = line.find(':');
    if (colon != std::string::npos) {
        std::string key = line.substr(0, colon);
        std::string value = line.substr(colon + 1);
        // Trim leading spaces and trailing CRLF
        value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](unsigned char c) {
            return !std::isspace(static_cast<unsigned char>(c));
        }));
        while (!value.empty() && (value.back() == '\r' || value.back() == '\n')) {
            value.pop_back();
        }
        headers->emplace_back(std::move(key), std::move(value));
    }
    return total;
}

curl_slist* build_header_list(const std::vector<std::pair<std::string, std::string>>& headers)
{
    curl_slist* list = nullptr;
    for (const auto& kv : headers) {
        std::string line = kv.first + ": " + kv.second;
        list = curl_slist_append(list, line.c_str());
    }
    return list;
}

class CurlGlobalInit {
public:
    CurlGlobalInit()
    {
        curl_global_init(CURL_GLOBAL_DEFAULT);
    }

    ~CurlGlobalInit()
    {
        curl_global_cleanup();
    }
};

CurlGlobalInit curl_global_init_guard;

} // namespace

HttpClient::HttpClient(std::size_t thread_count)
{
    if (thread_count == 0) {
        thread_count = std::max<std::size_t>(1, std::thread::hardware_concurrency());
    }

    workers.reserve(thread_count);
    for (std::size_t i = 0; i < thread_count; ++i) {
        workers.emplace_back([this]() { worker_loop(); });
    }
}

HttpClient::~HttpClient()
{
    shutdown();
}

uint64_t HttpClient::submit(const HttpRequest& request)
{
    if (request.url.empty()) {
        throw std::runtime_error("http.request requires a url");
    }

    uint64_t id = next_id.fetch_add(1);
    auto cancel_flag = std::make_shared<std::atomic<bool>>(false);
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        pending.push(QueuedRequest { id, request, cancel_flag });
        cancel_flags[id] = cancel_flag;
    }
    queue_cv.notify_one();
    return id;
}

bool HttpClient::cancel(uint64_t id)
{
    std::lock_guard<std::mutex> lock(queue_mutex);
    auto it = cancel_flags.find(id);
    if (it == cancel_flags.end()) {
        return false;
    }
    it->second->store(true);
    return true;
}

std::vector<HttpResponse> HttpClient::poll(std::size_t max_results)
{
    std::vector<HttpResponse> out;
    std::lock_guard<std::mutex> lock(completed_mutex);
    if (max_results == 0 || max_results > completed.size()) {
        max_results = completed.size();
    }
    out.reserve(max_results);
    for (std::size_t i = 0; i < max_results; ++i) {
        out.push_back(std::move(completed[i]));
    }
    completed.erase(completed.begin(), completed.begin() + static_cast<long>(max_results));
    return out;
}

void HttpClient::shutdown()
{
    bool expected = false;
    if (!stop.compare_exchange_strong(expected, true)) {
        return;
    }

    queue_cv.notify_all();
    for (auto& worker : workers) {
        if (worker.joinable()) {
            worker.join();
        }
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        std::queue<QueuedRequest> empty;
        pending.swap(empty);
        cancel_flags.clear();
    }
}

bool HttpClient::pop_request(QueuedRequest& out)
{
    std::unique_lock<std::mutex> lock(queue_mutex);
    queue_cv.wait(lock, [this]() { return stop.load() || !pending.empty(); });
    if (stop.load()) {
        return false;
    }
    out = std::move(pending.front());
    pending.pop();
    return true;
}

void HttpClient::worker_loop()
{
    while (!stop.load()) {
        QueuedRequest req;
        if (!pop_request(req)) {
            break;
        }

        if (req.cancel_flag && req.cancel_flag->load()) {
            HttpResponse cancelled = make_cancelled_response(req);
            std::lock_guard<std::mutex> lock(completed_mutex);
            completed.push_back(std::move(cancelled));
            continue;
        }

        HttpResponse resp = perform(req);
        {
            std::lock_guard<std::mutex> lock(completed_mutex);
            completed.push_back(std::move(resp));
        }
        {
            std::lock_guard<std::mutex> lock(queue_mutex);
            cancel_flags.erase(req.id);
        }
    }
}

HttpResponse HttpClient::make_cancelled_response(const QueuedRequest& req)
{
    HttpResponse resp;
    resp.id = req.id;
    resp.cancelled = true;
    resp.ok = false;
    resp.status = 0;
    resp.error = "cancelled";
    return resp;
}

HttpResponse HttpClient::perform(const QueuedRequest& req)
{
    HttpResponse out;
    out.id = req.id;
    CURL* curl = curl_easy_init();
    if (!curl) {
        out.error = "curl_easy_init failed";
        return out;
    }

    std::string body;
    std::vector<std::pair<std::string, std::string>> headers_out;

    curl_easy_setopt(curl, CURLOPT_URL, req.request.url.c_str());
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, req.request.follow_redirects ? 1L : 0L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, req.request.user_agent.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_body);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, write_header);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &headers_out);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");

    if (!req.request.body.empty()) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, req.request.body.c_str());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, req.request.body.size());
    }

    if (!req.request.method.empty()) {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, req.request.method.c_str());
    }

    curl_slist* header_list = build_header_list(req.request.headers);
    if (header_list) {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
    }

    if (req.request.timeout_ms > 0) {
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, req.request.timeout_ms);
    }
    if (req.request.connect_timeout_ms > 0) {
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, req.request.connect_timeout_ms);
    }

    std::shared_ptr<std::atomic<bool>> cancel_flag = req.cancel_flag;
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION,
        +[](void* clientp, curl_off_t, curl_off_t, curl_off_t, curl_off_t) -> int {
            auto* flag = static_cast<std::atomic<bool>*>(clientp);
            return (flag && flag->load()) ? 1 : 0;
        });
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, cancel_flag.get());
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);

    if (req.request.delay_ms > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(req.request.delay_ms));
    }

    CURLcode code = curl_easy_perform(curl);
    if (cancel_flag && cancel_flag->load()) {
        out = make_cancelled_response(req);
    } else if (code != CURLE_OK) {
        out.ok = false;
        out.error = curl_easy_strerror(code);
    } else {
        long status = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        out.ok = (status >= 200 && status < 400);
        out.status = status;
        out.body = std::move(body);
        out.headers = std::move(headers_out);
    }

    if (header_list) {
        curl_slist_free_all(header_list);
    }
    curl_easy_cleanup(curl);
    return out;
}
