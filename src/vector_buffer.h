#pragma once

#include <vector>
#include <unordered_map>
#include <list>
#include <stdexcept>
#include <cstring> // for std::memset

class VectorHandle {
public:
    size_t index;
    size_t size;

    VectorHandle(size_t i, size_t s)
        : index(i), size(s) {}
};

class VectorBuffer {
public:
    VectorBuffer(size_t initialSize = 1024) {
        buffer.resize(initialSize, 0.0f);
        freeFrom = 0;
    }

    const float* view(const VectorHandle& handle) const {
        return &buffer[handle.index];
    }

    float* view(VectorHandle& handle) {
        return &buffer[handle.index];
    }

    float* raw_data() {
        return buffer.data();
    }

    size_t used_size() const {
        return freeFrom * sizeof(float);
    }

    VectorHandle allocate(size_t size) {
        // Try reuse
        auto& freedList = freed[size];
        if (!freedList.empty()) {
            VectorHandle handle = freedList.front();
            freedList.pop_front();
            return handle;
        }

        // Expand if needed
        if (freeFrom + size > buffer.size()) {
            resizeBuffer(2 * buffer.size() + size);
        }

        VectorHandle handle(freeFrom, size);
        freeFrom += size;
        return handle;
    }

    void reallocate(VectorHandle& handle, size_t newSize) {
        if (newSize == handle.size) return;

        if (newSize < handle.size) {
            // Shrinking in-place: zero extra bytes
            zeroRegion(handle.index + newSize, handle.size - newSize);
            handle.size = newSize;
        } else {
            // Allocate new region
            deleteHandle(handle);
            handle = allocate(newSize);
        }
    }

    void deleteHandle(const VectorHandle& handle) {
        zeroRegion(handle.index, handle.size);
        freed[handle.size].push_back(handle);
    }

private:
    std::vector<float> buffer;
    size_t freeFrom;

    std::unordered_map<size_t, std::list<VectorHandle>> freed;

    void zeroRegion(size_t start, size_t size) {
        std::fill(buffer.begin() + start, buffer.begin() + start + size, 0.0f);
    }

    void resizeBuffer(size_t newSize) {
        if (newSize <= buffer.size()) {
            throw std::runtime_error("Cannot downsize buffer manually.");
        }
        buffer.resize(newSize, 0.0f);
    }
};
