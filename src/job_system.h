#pragma once

#include <atomic>
#include <cstddef>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

class JobSystem {
public:
    enum class JobOwner {
        Engine,
        Lua
    };

    struct JobRequest {
        uint64_t id;
        std::string kind;
        std::string payload;
        JobOwner owner { JobOwner::Engine };
    };

    struct NativePayload {
        void* data { nullptr };
        std::size_t size_bytes { 0 };
        std::size_t alignment { 1 };
        std::size_t element_size { 1 };
        std::unique_ptr<void, void(*)(void*)> owner { nullptr, nullptr };

        static NativePayload from_owned(void* ptr,
                                        std::size_t size_bytes,
                                        std::size_t alignment,
                                        std::size_t element_size,
                                        void (*deleter)(void*)) {
            NativePayload payload;
            payload.data = ptr;
            payload.size_bytes = size_bytes;
            payload.alignment = alignment;
            payload.element_size = element_size;
            payload.owner = std::unique_ptr<void, void(*)(void*)>(ptr, deleter);
            return payload;
        }

        template <typename T>
        static NativePayload from_array(std::unique_ptr<T[]>&& data, std::size_t count) {
            T* ptr = data.release();
            return from_owned(ptr,
                              count * sizeof(T),
                              alignof(T),
                              sizeof(T),
                              [](void* raw) { delete[] static_cast<T*>(raw); });
        }
    };

    struct JobResult {
        uint64_t id;
        bool ok;
        std::string kind;
        std::string result;
        std::string error;
        NativePayload payload;
        int aux_a { 0 };
        int aux_b { 0 };
        int aux_c { 0 };
        int aux_d { 0 };
        JobOwner owner { JobOwner::Engine };
    };

    using JobHandler = std::function<JobResult(const JobRequest&)>;

    explicit JobSystem(std::size_t threadCount = 0);
    ~JobSystem();

    JobSystem(const JobSystem&) = delete;
    JobSystem& operator=(const JobSystem&) = delete;

    uint64_t submit(const std::string& kind, const std::string& payload, JobOwner owner = JobOwner::Engine);
    void register_handler(const std::string& kind, JobHandler handler);
    std::vector<JobResult> poll(std::size_t maxResults = 0);
    std::vector<JobResult> poll_kind(const std::string& kind, std::size_t maxResults = 0);
    std::vector<JobResult> poll_owner(JobOwner owner, std::size_t maxResults = 0);
    std::vector<JobResult> poll_kind_owner(const std::string& kind, JobOwner owner, std::size_t maxResults = 0);
    void shutdown();

private:
    void worker_loop();
    bool pop_job(JobRequest& out);

    std::atomic<bool> stop { false };
    std::atomic<uint64_t> nextId { 1 };

    std::mutex handlerMutex;
    std::unordered_map<std::string, JobHandler> handlers;

    std::mutex queueMutex;
    std::condition_variable queueCv;
    std::queue<JobRequest> jobQueue;

    std::mutex completedMutex;
    std::vector<JobResult> completed;

    std::vector<std::thread> workers;
};

void register_default_job_handlers(JobSystem& jobs);
