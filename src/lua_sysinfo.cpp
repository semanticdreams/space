#include "lua_sysinfo.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if defined(__linux__)
#include <csignal>
#include <dirent.h>
#include <sys/types.h>
#include <unistd.h>
#elif defined(_WIN32)
#ifndef WINVER
#define WINVER 0x0600
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#define NOMINMAX
#include <windows.h>
#include <process.h>
#include <psapi.h>
#include <tlhelp32.h>
#elif defined(__APPLE__)
#include <csignal>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>
#else
#error "sysinfo: unsupported platform"
#endif

namespace {

using Clock = std::chrono::steady_clock;

struct CpuTimes
{
    std::optional<double> user;
    std::optional<double> system;
    std::optional<double> idle;
    std::optional<double> nice;
    std::optional<double> iowait;
    std::optional<double> irq;
    std::optional<double> softirq;
    std::optional<double> steal;
};

struct CpuSample
{
    Clock::time_point wall;
    double total_units { 0.0 };
    double idle_units { 0.0 };
    CpuTimes times {};
    std::vector<std::pair<double, double>> per_core_units;
};

struct VirtualMemory
{
    uint64_t total { 0 };
    std::optional<uint64_t> used;
    std::optional<uint64_t> available;
    std::optional<uint64_t> free;
    std::optional<double> percent;
};

struct ProcessTimes
{
    std::optional<double> user;
    std::optional<double> system;
    std::optional<uint64_t> start_token;
};

struct ProcessMemory
{
    std::optional<uint64_t> rss;
    std::optional<uint64_t> vms;
    std::optional<double> percent;
};

struct ProcessCpuSample
{
    Clock::time_point wall;
    double process_total_units { 0.0 };
    double system_total_units { 0.0 };
    std::optional<uint64_t> start_token;
};

double clamp_percent(double value)
{
    if (value < 0.0) {
        return 0.0;
    }
    if (value > 100.0) {
        return 100.0;
    }
    return value;
}

bool is_numeric_string(const std::string& value)
{
    if (value.empty()) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
        return std::isdigit(ch) != 0;
    });
}

std::string lower_copy(const std::string& value)
{
    std::string lowered = value;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return lowered;
}

bool contains_case_insensitive(const std::string& haystack, const std::string& needle)
{
    if (needle.empty()) {
        return true;
    }
    std::string hay = lower_copy(haystack);
    std::string ned = lower_copy(needle);
    return hay.find(ned) != std::string::npos;
}

std::string basename_from_path(const std::string& path)
{
    std::size_t pos = path.find_last_of("/\\");
    if (pos == std::string::npos || pos + 1 >= path.size()) {
        return path;
    }
    return path.substr(pos + 1);
}

int64_t current_pid()
{
#if defined(_WIN32)
    return static_cast<int64_t>(_getpid());
#else
    return static_cast<int64_t>(getpid());
#endif
}

std::string platform_os()
{
#if defined(__linux__)
    return "linux";
#elif defined(_WIN32)
    return "windows";
#else
    return "macos";
#endif
}

std::string platform_arch()
{
#if defined(__x86_64__) || defined(_M_X64)
    return "x86_64";
#elif defined(__aarch64__) || defined(_M_ARM64)
    return "arm64";
#elif defined(__arm__) || defined(_M_ARM)
    return "arm";
#elif defined(__i386__) || defined(_M_IX86)
    return "x86";
#else
    return "unknown";
#endif
}

#if defined(__linux__)

double linux_clock_ticks_per_second()
{
    static const double ticks = [] {
        long value = sysconf(_SC_CLK_TCK);
        if (value <= 0) {
            return 100.0;
        }
        return static_cast<double>(value);
    }();
    return ticks;
}

double linux_page_size()
{
    static const double page_size = [] {
        long value = sysconf(_SC_PAGESIZE);
        if (value <= 0) {
            return 4096.0;
        }
        return static_cast<double>(value);
    }();
    return page_size;
}

bool parse_linux_cpu_line(const std::string& line, CpuTimes& times, double& total_units, double& idle_units)
{
    std::istringstream stream(line);
    std::string label;
    uint64_t user = 0;
    uint64_t nice = 0;
    uint64_t system = 0;
    uint64_t idle = 0;
    uint64_t iowait = 0;
    uint64_t irq = 0;
    uint64_t softirq = 0;
    uint64_t steal = 0;
    stream >> label >> user >> nice >> system >> idle >> iowait >> irq >> softirq >> steal;
    if (stream.fail()) {
        return false;
    }

    const double scale = 1.0 / linux_clock_ticks_per_second();
    times.user = static_cast<double>(user) * scale;
    times.nice = static_cast<double>(nice) * scale;
    times.system = static_cast<double>(system) * scale;
    times.idle = static_cast<double>(idle) * scale;
    times.iowait = static_cast<double>(iowait) * scale;
    times.irq = static_cast<double>(irq) * scale;
    times.softirq = static_cast<double>(softirq) * scale;
    times.steal = static_cast<double>(steal) * scale;

    total_units = static_cast<double>(user + nice + system + idle + iowait + irq + softirq + steal);
    idle_units = static_cast<double>(idle + iowait);
    return true;
}

bool capture_system_cpu_sample(CpuSample& sample)
{
    std::ifstream file("/proc/stat");
    if (!file.is_open()) {
        return false;
    }

    sample = CpuSample {};
    sample.wall = Clock::now();
    std::string line;
    bool saw_total = false;
    while (std::getline(file, line)) {
        if (line.rfind("cpu", 0) != 0) {
            break;
        }
        CpuTimes times {};
        double total_units = 0.0;
        double idle_units = 0.0;
        if (!parse_linux_cpu_line(line, times, total_units, idle_units)) {
            continue;
        }
        if (line.rfind("cpu ", 0) == 0) {
            sample.times = times;
            sample.total_units = total_units;
            sample.idle_units = idle_units;
            saw_total = true;
            continue;
        }
        sample.per_core_units.emplace_back(total_units, idle_units);
    }

    return saw_total;
}

bool capture_virtual_memory(VirtualMemory& memory)
{
    std::ifstream file("/proc/meminfo");
    if (!file.is_open()) {
        return false;
    }

    std::optional<uint64_t> total_kb;
    std::optional<uint64_t> available_kb;
    std::optional<uint64_t> free_kb;
    std::string key;
    uint64_t value = 0;
    std::string unit;
    while (file >> key >> value >> unit) {
        if (key == "MemTotal:") {
            total_kb = value;
        } else if (key == "MemAvailable:") {
            available_kb = value;
        } else if (key == "MemFree:") {
            free_kb = value;
        }
    }

    if (!total_kb.has_value()) {
        return false;
    }

    memory = VirtualMemory {};
    memory.total = total_kb.value() * 1024ULL;
    if (available_kb.has_value()) {
        memory.available = available_kb.value() * 1024ULL;
    }
    if (free_kb.has_value()) {
        memory.free = free_kb.value() * 1024ULL;
    }

    if (memory.available.has_value()) {
        memory.used = memory.total > memory.available.value() ? memory.total - memory.available.value() : 0ULL;
    } else if (memory.free.has_value()) {
        memory.used = memory.total > memory.free.value() ? memory.total - memory.free.value() : 0ULL;
    }

    if (memory.used.has_value() && memory.total > 0) {
        memory.percent = clamp_percent((static_cast<double>(memory.used.value()) * 100.0)
                                       / static_cast<double>(memory.total));
    }

    return true;
}

bool read_process_stat_line(int64_t pid, std::string& name, uint64_t& utime_ticks, uint64_t& stime_ticks, uint64_t& start_time_ticks)
{
    const std::string path = "/proc/" + std::to_string(pid) + "/stat";
    std::ifstream file(path);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    std::getline(file, line);
    if (line.empty()) {
        return false;
    }

    std::size_t open = line.find('(');
    std::size_t close = line.rfind(')');
    if (open == std::string::npos || close == std::string::npos || close <= open) {
        return false;
    }
    name = line.substr(open + 1, close - open - 1);

    if (close + 2 >= line.size()) {
        return false;
    }

    std::string remainder = line.substr(close + 2);
    std::istringstream stream(remainder);
    std::vector<std::string> fields;
    std::string token;
    while (stream >> token) {
        fields.push_back(token);
    }

    if (fields.size() <= 19) {
        return false;
    }

    try {
        utime_ticks = std::stoull(fields[11]);
        stime_ticks = std::stoull(fields[12]);
        start_time_ticks = std::stoull(fields[19]);
    } catch (...) {
        return false;
    }
    return true;
}

bool capture_process_times(int64_t pid, ProcessTimes& times, std::optional<std::string>* out_name = nullptr)
{
    std::string name;
    uint64_t utime_ticks = 0;
    uint64_t stime_ticks = 0;
    uint64_t start_ticks = 0;
    if (!read_process_stat_line(pid, name, utime_ticks, stime_ticks, start_ticks)) {
        return false;
    }

    const double scale = 1.0 / linux_clock_ticks_per_second();
    times = ProcessTimes {};
    times.user = static_cast<double>(utime_ticks) * scale;
    times.system = static_cast<double>(stime_ticks) * scale;
    times.start_token = start_ticks;
    if (out_name != nullptr) {
        *out_name = name;
    }
    return true;
}

bool capture_process_memory(int64_t pid, ProcessMemory& memory, uint64_t system_total_bytes)
{
    const std::string path = "/proc/" + std::to_string(pid) + "/statm";
    std::ifstream file(path);
    if (!file.is_open()) {
        return false;
    }

    uint64_t size_pages = 0;
    uint64_t resident_pages = 0;
    file >> size_pages >> resident_pages;
    if (file.fail()) {
        return false;
    }

    const double page_size = linux_page_size();
    memory = ProcessMemory {};
    memory.vms = static_cast<uint64_t>(static_cast<double>(size_pages) * page_size);
    memory.rss = static_cast<uint64_t>(static_cast<double>(resident_pages) * page_size);
    if (memory.rss.has_value() && system_total_bytes > 0) {
        memory.percent = clamp_percent((static_cast<double>(memory.rss.value()) * 100.0)
                                       / static_cast<double>(system_total_bytes));
    }
    return true;
}

bool process_exists(int64_t pid)
{
    if (pid <= 0) {
        return false;
    }
    if (kill(static_cast<pid_t>(pid), 0) == 0) {
        return true;
    }
    return errno == EPERM;
}

bool list_process_ids(std::vector<int64_t>& pids)
{
    DIR* dir = opendir("/proc");
    if (dir == nullptr) {
        return false;
    }

    pids.clear();
    while (dirent* entry = readdir(dir)) {
        if (entry->d_type != DT_DIR && entry->d_type != DT_UNKNOWN) {
            continue;
        }
        std::string name(entry->d_name);
        if (!is_numeric_string(name)) {
            continue;
        }
        try {
            pids.push_back(std::stoll(name));
        } catch (...) {
        }
    }
    closedir(dir);
    return true;
}

bool supports_process_name_filtering()
{
    return true;
}

#elif defined(_WIN32)

uint64_t filetime_to_uint64(const FILETIME& value)
{
    ULARGE_INTEGER raw {};
    raw.LowPart = value.dwLowDateTime;
    raw.HighPart = value.dwHighDateTime;
    return raw.QuadPart;
}

double filetime_to_seconds(const FILETIME& value)
{
    return static_cast<double>(filetime_to_uint64(value)) / 10000000.0;
}

bool capture_system_cpu_sample(CpuSample& sample)
{
    FILETIME idle {};
    FILETIME kernel {};
    FILETIME user {};
    if (GetSystemTimes(&idle, &kernel, &user) == 0) {
        return false;
    }

    const uint64_t idle_units = filetime_to_uint64(idle);
    const uint64_t kernel_units = filetime_to_uint64(kernel);
    const uint64_t user_units = filetime_to_uint64(user);

    sample = CpuSample {};
    sample.wall = Clock::now();
    sample.total_units = static_cast<double>(kernel_units + user_units);
    sample.idle_units = static_cast<double>(idle_units);

    sample.times.user = filetime_to_seconds(user);
    sample.times.system = filetime_to_seconds(kernel);
    sample.times.idle = filetime_to_seconds(idle);
    return true;
}

bool capture_virtual_memory(VirtualMemory& memory)
{
    MEMORYSTATUSEX status {};
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status) == 0) {
        return false;
    }

    memory = VirtualMemory {};
    memory.total = status.ullTotalPhys;
    memory.available = status.ullAvailPhys;
    memory.free = status.ullAvailPhys;
    memory.used = memory.total > status.ullAvailPhys ? memory.total - status.ullAvailPhys : 0ULL;
    if (memory.total > 0) {
        memory.percent = clamp_percent((static_cast<double>(memory.used.value()) * 100.0)
                                       / static_cast<double>(memory.total));
    }
    return true;
}

bool open_process_handle(int64_t pid, HANDLE& out_handle)
{
    out_handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, static_cast<DWORD>(pid));
    return out_handle != nullptr;
}

bool query_process_name(int64_t pid, std::optional<std::string>& out_name)
{
    HANDLE handle = nullptr;
    if (!open_process_handle(pid, handle)) {
        return false;
    }

    char buffer[MAX_PATH] = { 0 };
    bool ok = false;
    DWORD size = GetProcessImageFileNameA(handle, buffer, MAX_PATH);
    if (size > 0) {
        out_name = basename_from_path(std::string(buffer, size));
        ok = true;
    }

    CloseHandle(handle);
    return ok;
}

bool capture_process_times(int64_t pid, ProcessTimes& times, std::optional<std::string>* out_name = nullptr)
{
    HANDLE handle = nullptr;
    if (!open_process_handle(pid, handle)) {
        return false;
    }

    FILETIME create_time {};
    FILETIME exit_time {};
    FILETIME kernel_time {};
    FILETIME user_time {};
    if (GetProcessTimes(handle, &create_time, &exit_time, &kernel_time, &user_time) == 0) {
        CloseHandle(handle);
        return false;
    }

    times = ProcessTimes {};
    times.user = filetime_to_seconds(user_time);
    times.system = filetime_to_seconds(kernel_time);
    times.start_token = filetime_to_uint64(create_time);

    if (out_name != nullptr) {
        std::optional<std::string> name;
        char buffer[MAX_PATH] = { 0 };
        DWORD size = GetProcessImageFileNameA(handle, buffer, MAX_PATH);
        if (size > 0) {
            name = basename_from_path(std::string(buffer, size));
        }
        *out_name = name;
    }

    CloseHandle(handle);
    return true;
}

bool capture_process_memory(int64_t pid, ProcessMemory& memory, uint64_t system_total_bytes)
{
    HANDLE handle = nullptr;
    if (!open_process_handle(pid, handle)) {
        return false;
    }

    PROCESS_MEMORY_COUNTERS_EX counters {};
    if (GetProcessMemoryInfo(handle,
            reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
            sizeof(counters)) == 0) {
        CloseHandle(handle);
        return false;
    }

    memory = ProcessMemory {};
    memory.rss = static_cast<uint64_t>(counters.WorkingSetSize);
    memory.vms = static_cast<uint64_t>(counters.PrivateUsage);
    if (memory.rss.has_value() && system_total_bytes > 0) {
        memory.percent = clamp_percent((static_cast<double>(memory.rss.value()) * 100.0)
                                       / static_cast<double>(system_total_bytes));
    }

    CloseHandle(handle);
    return true;
}

bool process_exists(int64_t pid)
{
    HANDLE handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(pid));
    if (handle == nullptr) {
        return false;
    }
    DWORD code = 0;
    bool ok = GetExitCodeProcess(handle, &code) != 0 && code == STILL_ACTIVE;
    CloseHandle(handle);
    return ok;
}

bool list_process_ids(std::vector<int64_t>& pids)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return false;
    }

    pids.clear();
    PROCESSENTRY32 entry {};
    entry.dwSize = sizeof(entry);
    if (Process32First(snapshot, &entry)) {
        do {
            pids.push_back(static_cast<int64_t>(entry.th32ProcessID));
        } while (Process32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return true;
}

bool supports_process_name_filtering()
{
    return true;
}

#else

bool capture_system_cpu_sample(CpuSample& sample)
{
    host_cpu_load_info_data_t cpu_info {};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
            reinterpret_cast<host_info_t>(&cpu_info), &count) != KERN_SUCCESS) {
        return false;
    }

    const uint64_t user = cpu_info.cpu_ticks[CPU_STATE_USER];
    const uint64_t system = cpu_info.cpu_ticks[CPU_STATE_SYSTEM];
    const uint64_t idle = cpu_info.cpu_ticks[CPU_STATE_IDLE];
    const uint64_t nice = cpu_info.cpu_ticks[CPU_STATE_NICE];

    sample = CpuSample {};
    sample.wall = Clock::now();
    sample.total_units = static_cast<double>(user + system + idle + nice);
    sample.idle_units = static_cast<double>(idle);

    sample.times.user = static_cast<double>(user);
    sample.times.system = static_cast<double>(system);
    sample.times.idle = static_cast<double>(idle);
    sample.times.nice = static_cast<double>(nice);

    processor_info_array_t cpu_load = nullptr;
    mach_msg_type_number_t cpu_load_count = 0;
    natural_t cpu_count = 0;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
            &cpu_count, &cpu_load, &cpu_load_count) == KERN_SUCCESS) {
        for (natural_t i = 0; i < cpu_count; ++i) {
            const auto base = static_cast<std::size_t>(i) * CPU_STATE_MAX;
            const uint64_t c_user = cpu_load[base + CPU_STATE_USER];
            const uint64_t c_system = cpu_load[base + CPU_STATE_SYSTEM];
            const uint64_t c_idle = cpu_load[base + CPU_STATE_IDLE];
            const uint64_t c_nice = cpu_load[base + CPU_STATE_NICE];
            const double total = static_cast<double>(c_user + c_system + c_idle + c_nice);
            sample.per_core_units.emplace_back(total, static_cast<double>(c_idle));
        }
        vm_deallocate(mach_task_self(), reinterpret_cast<vm_address_t>(cpu_load),
            cpu_load_count * sizeof(integer_t));
    }

    return true;
}

bool capture_virtual_memory(VirtualMemory& memory)
{
    uint64_t total = 0;
    std::size_t total_size = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &total_size, nullptr, 0) != 0 || total == 0) {
        return false;
    }

    vm_statistics64_data_t vm_info {};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
            reinterpret_cast<host_info64_t>(&vm_info), &count) != KERN_SUCCESS) {
        return false;
    }

    const uint64_t page_size = static_cast<uint64_t>(vm_kernel_page_size);
    const uint64_t free_bytes = static_cast<uint64_t>(vm_info.free_count) * page_size;

    memory = VirtualMemory {};
    memory.total = total;
    memory.free = free_bytes;
    memory.used = total > free_bytes ? total - free_bytes : 0ULL;
    memory.percent = clamp_percent((static_cast<double>(memory.used.value()) * 100.0)
                                   / static_cast<double>(total));
    return true;
}

bool capture_process_times(int64_t pid, ProcessTimes& times, std::optional<std::string>* out_name = nullptr)
{
    rusage_info_v2 usage {};
    if (proc_pid_rusage(static_cast<int>(pid), RUSAGE_INFO_V2,
            reinterpret_cast<rusage_info_t*>(&usage)) != 0) {
        return false;
    }

    struct proc_bsdinfo bsd {};
    if (proc_pidinfo(static_cast<int>(pid), PROC_PIDTBSDINFO, 0,
            &bsd, sizeof(bsd)) <= 0) {
        return false;
    }

    times = ProcessTimes {};
    times.user = static_cast<double>(usage.ri_user_time) / 1e9;
    times.system = static_cast<double>(usage.ri_system_time) / 1e9;
    times.start_token = (static_cast<uint64_t>(bsd.pbi_start_tvsec) * 1000000ULL)
                        + static_cast<uint64_t>(bsd.pbi_start_tvusec);

    if (out_name != nullptr) {
        std::string raw_name(bsd.pbi_name);
        if (!raw_name.empty()) {
            *out_name = raw_name;
        } else {
            *out_name = std::nullopt;
        }
    }

    return true;
}

bool capture_process_memory(int64_t pid, ProcessMemory& memory, uint64_t system_total_bytes)
{
    struct proc_taskinfo task_info {};
    if (proc_pidinfo(static_cast<int>(pid), PROC_PIDTASKINFO, 0,
            &task_info, sizeof(task_info)) <= 0) {
        return false;
    }

    memory = ProcessMemory {};
    memory.rss = task_info.pti_resident_size;
    memory.vms = task_info.pti_virtual_size;
    if (memory.rss.has_value() && system_total_bytes > 0) {
        memory.percent = clamp_percent((static_cast<double>(memory.rss.value()) * 100.0)
                                       / static_cast<double>(system_total_bytes));
    }

    return true;
}

bool process_exists(int64_t pid)
{
    if (pid <= 0) {
        return false;
    }
    if (kill(static_cast<pid_t>(pid), 0) == 0) {
        return true;
    }
    return errno == EPERM;
}

bool list_process_ids(std::vector<int64_t>& pids)
{
    int max_bytes = proc_listpids(PROC_ALL_PIDS, 0, nullptr, 0);
    if (max_bytes <= 0) {
        return false;
    }

    std::vector<pid_t> raw(static_cast<std::size_t>(max_bytes / static_cast<int>(sizeof(pid_t))));
    int used_bytes = proc_listpids(PROC_ALL_PIDS, 0, raw.data(),
        static_cast<int>(raw.size() * sizeof(pid_t)));
    if (used_bytes <= 0) {
        return false;
    }

    pids.clear();
    const std::size_t count = static_cast<std::size_t>(used_bytes) / sizeof(pid_t);
    for (std::size_t i = 0; i < count; ++i) {
        if (raw[i] > 0) {
            pids.push_back(static_cast<int64_t>(raw[i]));
        }
    }
    return true;
}

bool supports_process_name_filtering()
{
    return true;
}

#endif

class ProcessHandle
{
public:
    explicit ProcessHandle(int64_t pid_value)
        : pid_(pid_value)
    {
    }

    int64_t pid_value() const
    {
        return pid_;
    }

    bool exists()
    {
        if (!process_exists(pid_)) {
            return false;
        }

        if (!start_token_.has_value()) {
            return true;
        }

        ProcessTimes times {};
        if (!capture_process_times(pid_, times, nullptr)) {
            return false;
        }

        if (times.start_token.has_value() && times.start_token.value() != start_token_.value()) {
            return false;
        }
        return true;
    }

    std::optional<std::string> name()
    {
        std::optional<std::string> value;
        ProcessTimes times {};
        if (!capture_process_times(pid_, times, &value)) {
            return std::nullopt;
        }

        if (times.start_token.has_value()) {
            if (!start_token_.has_value()) {
                start_token_ = times.start_token;
            } else if (times.start_token.value() != start_token_.value()) {
                return std::nullopt;
            }
        }

        return value;
    }

    bool refresh()
    {
        ProcessTimes process_times {};
        if (!capture_process_times(pid_, process_times, nullptr)) {
            return false;
        }

        if (process_times.start_token.has_value()) {
            if (!start_token_.has_value()) {
                start_token_ = process_times.start_token;
            } else if (process_times.start_token.value() != start_token_.value()) {
                return false;
            }
        }

        CpuSample system_sample {};
        if (!capture_system_cpu_sample(system_sample)) {
            return false;
        }

        ProcessCpuSample sample {};
        sample.wall = system_sample.wall;
        sample.process_total_units = process_times.user.value_or(0.0) + process_times.system.value_or(0.0);
        sample.system_total_units = system_sample.total_units;
        sample.start_token = process_times.start_token;

        baseline_ = sample;
        last_process_times_ = process_times;
        return true;
    }

    sol::table cpu(sol::this_state ts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();
        out["warmup"] = true;

        ProcessTimes process_times {};
        if (!capture_process_times(pid_, process_times, nullptr)) {
            return out;
        }

        if (process_times.start_token.has_value()) {
            if (!start_token_.has_value()) {
                start_token_ = process_times.start_token;
            } else if (process_times.start_token.value() != start_token_.value()) {
                return out;
            }
        }

        CpuSample system_sample {};
        if (!capture_system_cpu_sample(system_sample)) {
            return out;
        }

        ProcessCpuSample sample {};
        sample.wall = system_sample.wall;
        sample.process_total_units = process_times.user.value_or(0.0) + process_times.system.value_or(0.0);
        sample.system_total_units = system_sample.total_units;
        sample.start_token = process_times.start_token;

        last_process_times_ = process_times;

        if (!baseline_.has_value()) {
            baseline_ = sample;
            return out;
        }

        const ProcessCpuSample base = baseline_.value();
        baseline_ = sample;

        const double delta_proc = sample.process_total_units - base.process_total_units;
        const double delta_sys = sample.system_total_units - base.system_total_units;
        const double interval = std::chrono::duration<double>(sample.wall - base.wall).count();
        if (delta_proc < 0.0 || delta_sys <= 0.0 || interval <= 0.0) {
            return out;
        }

        out["percent"] = clamp_percent((delta_proc * 100.0) / delta_sys);
        out["warmup"] = false;
        out["interval"] = interval;
        return out;
    }

    sol::table cpu_times(sol::this_state ts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();

        ProcessTimes times = last_process_times_.value_or(ProcessTimes {});
        if (!times.user.has_value() || !times.system.has_value()) {
            ProcessTimes fresh {};
            if (capture_process_times(pid_, fresh, nullptr)) {
                times = fresh;
                last_process_times_ = fresh;
            }
        }

        if (times.user.has_value()) {
            out["user"] = times.user.value();
        }
        if (times.system.has_value()) {
            out["system"] = times.system.value();
        }
        return out;
    }

    sol::table mem(sol::this_state ts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();

        VirtualMemory vm {};
        capture_virtual_memory(vm);

        ProcessMemory process_memory {};
        if (!capture_process_memory(pid_, process_memory, vm.total)) {
            return out;
        }

        if (process_memory.rss.has_value()) {
            out["rss"] = process_memory.rss.value();
        }
        if (process_memory.vms.has_value()) {
            out["vms"] = process_memory.vms.value();
        }
        if (process_memory.percent.has_value()) {
            out["percent"] = process_memory.percent.value();
        }
        return out;
    }

private:
    int64_t pid_ { -1 };
    std::optional<uint64_t> start_token_ {};
    std::optional<ProcessCpuSample> baseline_ {};
    std::optional<ProcessTimes> last_process_times_ {};
};

class SystemHandle
{
public:
    bool refresh()
    {
        CpuSample sample {};
        if (!capture_system_cpu_sample(sample)) {
            return false;
        }
        baseline_ = sample;
        last_cpu_sample_ = sample;
        return true;
    }

    sol::table cpu_usage(sol::this_state ts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();
        out["warmup"] = true;

        CpuSample sample {};
        if (!capture_system_cpu_sample(sample)) {
            return out;
        }

        last_cpu_sample_ = sample;

        if (!baseline_.has_value()) {
            baseline_ = sample;
            if (!sample.per_core_units.empty()) {
                sol::table per_core = lua.create_table();
                for (std::size_t i = 0; i < sample.per_core_units.size(); ++i) {
                    per_core[static_cast<int>(i + 1)] = lua.create_table();
                }
                out["per-core"] = per_core;
            }
            return out;
        }

        const CpuSample base = baseline_.value();
        baseline_ = sample;

        const double delta_total = sample.total_units - base.total_units;
        const double delta_idle = sample.idle_units - base.idle_units;
        const double interval = std::chrono::duration<double>(sample.wall - base.wall).count();
        if (delta_total <= 0.0 || interval <= 0.0) {
            return out;
        }

        const double busy = std::max(0.0, delta_total - delta_idle);
        out["percent"] = clamp_percent((busy * 100.0) / delta_total);
        out["warmup"] = false;
        out["interval"] = interval;

        if (!sample.per_core_units.empty() && base.per_core_units.size() == sample.per_core_units.size()) {
            sol::table per_core = lua.create_table();
            for (std::size_t i = 0; i < sample.per_core_units.size(); ++i) {
                const auto& now = sample.per_core_units[i];
                const auto& prev = base.per_core_units[i];
                const double core_total = now.first - prev.first;
                const double core_idle = now.second - prev.second;
                sol::table item = lua.create_table();
                if (core_total > 0.0) {
                    const double core_busy = std::max(0.0, core_total - core_idle);
                    item["percent"] = clamp_percent((core_busy * 100.0) / core_total);
                }
                per_core[static_cast<int>(i + 1)] = item;
            }
            out["per-core"] = per_core;
        }

        return out;
    }

    sol::table cpu_times(sol::this_state ts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();

        CpuSample sample = last_cpu_sample_.value_or(CpuSample {});
        if (!sample.times.user.has_value() && !capture_system_cpu_sample(sample)) {
            return out;
        }

        if (sample.times.user.has_value()) {
            out["user"] = sample.times.user.value();
        }
        if (sample.times.system.has_value()) {
            out["system"] = sample.times.system.value();
        }
        if (sample.times.idle.has_value()) {
            out["idle"] = sample.times.idle.value();
        }
        if (sample.times.nice.has_value()) {
            out["nice"] = sample.times.nice.value();
        }
        if (sample.times.iowait.has_value()) {
            out["iowait"] = sample.times.iowait.value();
        }
        if (sample.times.irq.has_value()) {
            out["irq"] = sample.times.irq.value();
        }
        if (sample.times.softirq.has_value()) {
            out["softirq"] = sample.times.softirq.value();
        }
        if (sample.times.steal.has_value()) {
            out["steal"] = sample.times.steal.value();
        }
        return out;
    }

    sol::table mem_virtual(sol::this_state ts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();

        VirtualMemory memory {};
        if (!capture_virtual_memory(memory) || memory.total == 0) {
            return out;
        }

        out["total"] = memory.total;
        if (memory.used.has_value()) {
            out["used"] = memory.used.value();
        }
        if (memory.available.has_value()) {
            out["available"] = memory.available.value();
        }
        if (memory.free.has_value()) {
            out["free"] = memory.free.value();
        }
        if (memory.percent.has_value()) {
            out["percent"] = memory.percent.value();
        }
        return out;
    }

    ProcessHandle process_current()
    {
        return ProcessHandle(current_pid());
    }

    sol::object process(sol::this_state ts, int64_t pid)
    {
        sol::state_view lua(ts);
        if (pid <= 0) {
            return sol::make_object(lua, sol::lua_nil);
        }

        if (pid == current_pid()) {
            ProcessHandle handle(pid);
            handle.refresh();
            return sol::make_object(lua, handle);
        }

        ProcessTimes times {};
        if (!capture_process_times(pid, times, nullptr)) {
            return sol::make_object(lua, sol::lua_nil);
        }

        ProcessHandle handle(pid);
        handle.refresh();
        return sol::make_object(lua, handle);
    }

    sol::table process_list(sol::this_state ts, sol::optional<sol::table> opts)
    {
        sol::state_view lua(ts);
        sol::table out = lua.create_table();

        std::string name_filter;
        std::optional<int64_t> pid_min;
        std::optional<int64_t> pid_max;
        std::optional<int64_t> limit;

        if (opts.has_value()) {
            sol::table options = opts.value();
            sol::optional<std::string> name_value = options["name"];
            if (name_value.has_value()) {
                name_filter = name_value.value();
            }
            sol::optional<int64_t> pid_min_value = options["pid-min"];
            if (pid_min_value.has_value()) {
                pid_min = pid_min_value.value();
            }
            sol::optional<int64_t> pid_max_value = options["pid-max"];
            if (pid_max_value.has_value()) {
                pid_max = pid_max_value.value();
            }
            sol::optional<int64_t> limit_value = options["limit"];
            if (limit_value.has_value() && limit_value.value() > 0) {
                limit = limit_value.value();
            }
        }

        std::vector<int64_t> pids;
        if (!list_process_ids(pids)) {
            return out;
        }
        std::sort(pids.begin(), pids.end());

        const bool apply_name_filter = !name_filter.empty() && supports_process_name_filtering();

        int64_t count = 0;
        for (int64_t pid : pids) {
            if (pid <= 0) {
                continue;
            }
            if (pid_min.has_value() && pid < pid_min.value()) {
                continue;
            }
            if (pid_max.has_value() && pid > pid_max.value()) {
                continue;
            }

            if (apply_name_filter) {
                std::optional<std::string> process_name;
                ProcessTimes times {};
                if (capture_process_times(pid, times, &process_name)) {
                    if (!process_name.has_value()
                        || !contains_case_insensitive(process_name.value(), name_filter)) {
                        continue;
                    }
                }
            }

            ProcessHandle handle(pid);
            if (!handle.refresh()) {
                continue;
            }
            out[static_cast<int>(count + 1)] = handle;
            count += 1;
            if (limit.has_value() && count >= limit.value()) {
                break;
            }
        }

        return out;
    }

private:
    std::optional<CpuSample> baseline_ {};
    std::optional<CpuSample> last_cpu_sample_ {};
};

sol::table platform_table(sol::this_state ts)
{
    sol::state_view lua(ts);
    sol::table out = lua.create_table();
    out["os"] = platform_os();
    out["arch"] = platform_arch();
#ifdef LUA_VERSION
    out["lua"] = std::string(LUA_VERSION);
#endif

    sol::table features = lua.create_table();
#if defined(__linux__) || defined(__APPLE__)
    features["process-list"] = true;
    features["per-core-cpu"] = true;
    features["system-cpu-times"] = true;
    features["system-memory"] = true;
    features["process-cpu"] = true;
    features["process-cpu-times"] = true;
    features["process-memory"] = true;
    features["process-name"] = true;
#elif defined(_WIN32)
    features["process-list"] = true;
    features["per-core-cpu"] = false;
    features["system-cpu-times"] = true;
    features["system-memory"] = true;
    features["process-cpu"] = true;
    features["process-cpu-times"] = true;
    features["process-memory"] = true;
    features["process-name"] = true;
#endif
    out["features"] = features;
    return out;
}

void sleep_seconds(double seconds)
{
    if (seconds <= 0.0) {
        return;
    }
    std::this_thread::sleep_for(std::chrono::duration<double>(seconds));
}

double now_ms()
{
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return std::chrono::duration<double, std::milli>(now).count();
}

} // namespace

void lua_bind_sysinfo(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("sysinfo", [](sol::this_state ts) {
        sol::state_view lua(ts);
        sol::table module = lua.create_table();

        module.new_usertype<ProcessHandle>("SysinfoProcess",
            sol::no_constructor,
            "pid", sol::property(&ProcessHandle::pid_value),
            "exists", &ProcessHandle::exists,
            "name", &ProcessHandle::name,
            "refresh", &ProcessHandle::refresh,
            "cpu", &ProcessHandle::cpu,
            "cpu-times", &ProcessHandle::cpu_times,
            "mem", &ProcessHandle::mem
        );

        module.new_usertype<SystemHandle>("SysinfoSystem",
            sol::no_constructor,
            "refresh", &SystemHandle::refresh,
            "cpu-usage", &SystemHandle::cpu_usage,
            "cpu-times", &SystemHandle::cpu_times,
            "mem-virtual", &SystemHandle::mem_virtual,
            "process-current", &SystemHandle::process_current,
            "process", &SystemHandle::process,
            "process-list", &SystemHandle::process_list
        );

        module.set_function("platform", &platform_table);
        module.set_function("system", []() { return SystemHandle(); });
        module.set_function("sleep", &sleep_seconds);
        module.set_function("now-ms", &now_ms);
        return module;
    });
}
