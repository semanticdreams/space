#pragma once

#include <vector>
#include <unordered_map>
#include <list>
#include <stdexcept>
#include <utility>
#include <cstring>  // for std::memset
#include <iostream> // for std::cout
#include <iomanip>  // for std::setprecision

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
        clearDirty();
    }

    const float* view(const VectorHandle& handle) const {
        if (handle.index + handle.size > buffer.size()) {
            throw std::runtime_error("VectorBuffer.view out of bounds: invalid handle");
        }
        return &buffer[handle.index];
    }

    float* view(VectorHandle& handle) {
        if (handle.index + handle.size > buffer.size()) {
            throw std::runtime_error("VectorBuffer.view out of bounds: invalid handle");
        }
        return &buffer[handle.index];
    }

    float* raw_data() {
        return buffer.data();
    }

    size_t used_size() const {
        return freeFrom * sizeof(float);
    }

    size_t length() const {
        return freeFrom;
    }

    bool has_dirty() const {
        return dirtyFrom != static_cast<size_t>(-1) && dirtyTo > dirtyFrom;
    }

    std::pair<size_t, size_t> dirty_range() const {
        if (!has_dirty()) {
            return { 0, 0 };
        }
        return { dirtyFrom, dirtyTo };
    }

    void clearDirty() {
        dirtyFrom = static_cast<size_t>(-1);
        dirtyTo = 0;
    }

    void markDirty(size_t start, size_t size) {
        if (size == 0) {
            return;
        }
        if (start >= freeFrom) {
            return;
        }
        size_t end = start + size;
        if (end > freeFrom) {
            end = freeFrom;
        }
        if (!has_dirty()) {
            dirtyFrom = start;
            dirtyTo = end;
            return;
        }
        if (start < dirtyFrom) {
            dirtyFrom = start;
        }
        if (end > dirtyTo) {
            dirtyTo = end;
        }
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

    void print(const VectorHandle* handle = nullptr) const {
        std::cout << std::fixed << std::setprecision(4);

        if (handle) {
            if (handle->index + handle->size > buffer.size()) {
                std::cerr << "[VectorBuffer] Invalid handle: out of bounds\n";
                return;
            }

            std::cout << "Handle @ index " << handle->index
                      << ", size " << handle->size << ":\n";

            const float* ptr = view(*handle);
            for (size_t i = 0; i < handle->size; ++i) {
                std::cout << "  [" << i << "] = " << ptr[i] << '\n';
            }
        } else {
            std::cout << "Full buffer (" << freeFrom << " / " 
                      << buffer.size() << " used):\n";

            for (size_t i = 0; i < freeFrom; ++i) {
                std::cout << "  [" << i << "] = " << buffer[i] << '\n';
            }
        }
    }

private:
    std::vector<float> buffer;
    size_t freeFrom;
    size_t dirtyFrom;
    size_t dirtyTo;
    std::unordered_map<size_t, std::list<VectorHandle>> freed;

    void zeroRegion(size_t start, size_t size) {
        markDirty(start, size);
        std::fill(buffer.begin() + start, buffer.begin() + start + size, 0.0f);
    }

    void resizeBuffer(size_t newSize) {
        if (newSize <= buffer.size()) {
            throw std::runtime_error("Cannot downsize buffer manually.");
        }
        buffer.resize(newSize, 0.0f);
    }
};
