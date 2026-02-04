#include "job_system.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <stdexcept>
#include <utility>

namespace {

std::size_t resolve_thread_count(std::size_t requested) {
    if (requested > 0) {
        return requested;
    }

    unsigned int hardware = std::thread::hardware_concurrency();
    if (hardware == 0) {
        return 1;
    }
    return std::max<std::size_t>(1, hardware - 1);
}

} // namespace

JobSystem::JobSystem(std::size_t threadCount) {
    std::size_t workersCount = resolve_thread_count(threadCount);
    workers.reserve(workersCount);
    for (std::size_t i = 0; i < workersCount; ++i) {
        workers.emplace_back([this]() { worker_loop(); });
    }
}

JobSystem::~JobSystem() {
    shutdown();
}

void JobSystem::shutdown() {
    bool expected = false;
    if (!stop.compare_exchange_strong(expected, true)) {
        return;
    }

    queueCv.notify_all();
    for (auto& worker : workers) {
        if (worker.joinable()) {
            worker.join();
        }
    }
}

void JobSystem::register_handler(const std::string& kind, JobHandler handler) {
    if (!handler) {
        throw std::invalid_argument("Job handler must not be empty");
    }
    std::lock_guard<std::mutex> lock(handlerMutex);
    handlers[kind] = handler;
}

uint64_t JobSystem::submit(const std::string& kind, const std::string& payload, JobOwner owner) {
    uint64_t id = nextId.fetch_add(1);

    {
        std::lock_guard<std::mutex> handlerLock(handlerMutex);
        if (handlers.find(kind) == handlers.end()) {
            JobResult immediate { id, false, kind, std::string(), "Unknown job kind: " + kind,
                                   {}, 0, 0, 0, 0, owner };
            std::lock_guard<std::mutex> completedLock(completedMutex);
            completed.push_back(std::move(immediate));
            return id;
        }
    }

    {
        std::lock_guard<std::mutex> lock(queueMutex);
        jobQueue.push(JobRequest { id, kind, payload, owner });
    }
    queueCv.notify_one();
    return id;
}

std::vector<JobSystem::JobResult> JobSystem::poll(std::size_t maxResults) {
    std::vector<JobResult> results;
    std::lock_guard<std::mutex> lock(completedMutex);

    if (completed.empty()) {
        return results;
    }

    if (maxResults == 0 || maxResults >= completed.size()) {
        results.swap(completed);
        return results;
    }

    results.reserve(maxResults);
    auto begin = completed.begin();
    auto split = begin + static_cast<std::ptrdiff_t>(maxResults);
    results.insert(results.end(),
                   std::make_move_iterator(begin),
                   std::make_move_iterator(split));
    completed.erase(begin, split);
    return results;
}

std::vector<JobSystem::JobResult> JobSystem::poll_kind(const std::string& kind, std::size_t maxResults) {
    std::vector<JobResult> results;
    std::lock_guard<std::mutex> lock(completedMutex);
    if (completed.empty()) {
        return results;
    }

    auto matches_kind = [&kind](const JobResult& res) { return res.kind == kind; };

    if (maxResults == 0) {
        maxResults = completed.size();
    }

    auto it = completed.begin();
    while (it != completed.end() && results.size() < maxResults) {
        if (matches_kind(*it)) {
            results.push_back(std::move(*it));
            it = completed.erase(it);
        } else {
            ++it;
        }
    }

    return results;
}

std::vector<JobSystem::JobResult> JobSystem::poll_owner(JobOwner owner, std::size_t maxResults) {
    std::vector<JobResult> results;
    std::lock_guard<std::mutex> lock(completedMutex);
    if (completed.empty()) {
        return results;
    }

    auto matches_owner = [owner](const JobResult& res) { return res.owner == owner; };

    if (maxResults == 0) {
        maxResults = completed.size();
    }

    auto it = completed.begin();
    while (it != completed.end() && results.size() < maxResults) {
        if (matches_owner(*it)) {
            results.push_back(std::move(*it));
            it = completed.erase(it);
        } else {
            ++it;
        }
    }

    return results;
}

std::vector<JobSystem::JobResult> JobSystem::poll_kind_owner(const std::string& kind,
                                                             JobOwner owner,
                                                             std::size_t maxResults) {
    std::vector<JobResult> results;
    std::lock_guard<std::mutex> lock(completedMutex);
    if (completed.empty()) {
        return results;
    }

    auto matches = [&kind, owner](const JobResult& res) { return res.kind == kind && res.owner == owner; };

    if (maxResults == 0) {
        maxResults = completed.size();
    }

    auto it = completed.begin();
    while (it != completed.end() && results.size() < maxResults) {
        if (matches(*it)) {
            results.push_back(std::move(*it));
            it = completed.erase(it);
        } else {
            ++it;
        }
    }

    return results;
}

bool JobSystem::pop_job(JobRequest& out) {
    std::unique_lock<std::mutex> lock(queueMutex);
    queueCv.wait(lock, [this]() { return stop.load() || !jobQueue.empty(); });

    if (stop.load() && jobQueue.empty()) {
        return false;
    }

    out = std::move(jobQueue.front());
    jobQueue.pop();
    return true;
}

void JobSystem::worker_loop() {
    while (!stop.load()) {
        JobRequest request;
        if (!pop_job(request)) {
            break;
        }

        JobResult result {};
        result.id = request.id;
        result.kind = request.kind;
        result.ok = false;

        JobHandler handler;
        {
            std::lock_guard<std::mutex> lock(handlerMutex);
            auto it = handlers.find(request.kind);
            if (it != handlers.end()) {
                handler = it->second;
            }
        }

        if (!handler) {
            result.error = "Unknown job kind: " + request.kind;
        } else {
            try {
                result = handler(request);
                result.id = request.id;
            } catch (const std::exception& ex) {
                result.ok = false;
                result.error = ex.what();
            } catch (...) {
                result.ok = false;
                result.error = "Unhandled exception in job handler";
            }
        }
        result.owner = request.owner;

        {
            std::lock_guard<std::mutex> lock(completedMutex);
            completed.push_back(std::move(result));
        }
    }
}

void register_default_job_handlers(JobSystem& jobs) {
    jobs.register_handler("echo",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              return JobSystem::JobResult { req.id, true, req.kind, req.payload, std::string(),
                                                            {}, 0, 0, 0, 0 };
                          });

    jobs.register_handler("sleep_ms",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              try {
                                  unsigned long duration = std::stoul(req.payload);
                                  std::this_thread::sleep_for(std::chrono::milliseconds(duration));
                                  return JobSystem::JobResult { req.id, true, req.kind, req.payload, std::string(),
                                                                {}, 0, 0, 0, 0 };
                              } catch (const std::exception& ex) {
                                  return JobSystem::JobResult { req.id, false, req.kind, std::string(),
                                                                std::string("sleep_ms: ") + ex.what(),
                                                                {}, 0, 0, 0, 0 };
                              }
                          });

    jobs.register_handler("uppercase",
                          [](const JobSystem::JobRequest& req) -> JobSystem::JobResult {
                              std::string out = req.payload;
                              std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) {
                                  return static_cast<char>(std::toupper(c));
                              });
                              return JobSystem::JobResult { req.id, true, req.kind, out, std::string(),
                                                            {}, 0, 0, 0, 0 };
                          });
}
