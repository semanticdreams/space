#pragma once

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

struct HttpRequest {
    std::string url;
    std::string method { "GET" };
    std::vector<std::pair<std::string, std::string>> headers;
    std::string body;
    long timeout_ms { 0 };
    long connect_timeout_ms { 0 };
    long delay_ms { 0 };
    bool follow_redirects { true };
    std::string user_agent { "space-http/1.0" };
};

struct HttpResponse {
    uint64_t id { 0 };
    bool ok { false };
    bool cancelled { false };
    long status { 0 };
    std::string body;
    std::string error;
    std::vector<std::pair<std::string, std::string>> headers;
};

class HttpClient {
public:
    explicit HttpClient(std::size_t thread_count = 0);
    ~HttpClient();

    HttpClient(const HttpClient&) = delete;
    HttpClient& operator=(const HttpClient&) = delete;

    uint64_t submit(const HttpRequest& request);
    bool cancel(uint64_t id);
    std::vector<HttpResponse> poll(std::size_t max_results = 0);
    void shutdown();

private:
    struct QueuedRequest {
        uint64_t id { 0 };
        HttpRequest request;
        std::shared_ptr<std::atomic<bool>> cancel_flag;
    };

    void worker_loop();
    HttpResponse perform(const QueuedRequest& req);
    HttpResponse make_cancelled_response(const QueuedRequest& req);
    bool pop_request(QueuedRequest& out);

    std::atomic<bool> stop { false };
    std::atomic<uint64_t> next_id { 1 };

    std::mutex queue_mutex;
    std::condition_variable queue_cv;
    std::queue<QueuedRequest> pending;
    std::unordered_map<uint64_t, std::shared_ptr<std::atomic<bool>>> cancel_flags;

    std::mutex completed_mutex;
    std::vector<HttpResponse> completed;

    std::vector<std::thread> workers;
};
