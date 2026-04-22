#pragma once

#include <vector>
#include <unordered_map>
#include <list>
#include <stdexcept>
#include <utility>
#include <cstring>  // for std::memset
#include <iostream> // for std::cout
#include <iomanip>  // for std::setprecision
#include <string>

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
        validateHandle(handle, "VectorBuffer.view");
        if (handle.size == 0) {
            return buffer.data();
        }
        return &buffer[handle.index];
    }

    float* view(VectorHandle& handle) {
        validateHandle(handle, "VectorBuffer.view");
        if (handle.size == 0) {
            return buffer.data();
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

    size_t capacity() const {
        return buffer.size();
    }

    size_t free_count() const {
        size_t count = 0;
        for (const auto& entry : freed) {
            count += entry.second.size();
        }
        return count;
    }

    size_t free_size() const {
        size_t total = 0;
        for (const auto& entry : freed) {
            total += entry.first * entry.second.size();
        }
        return total;
    }

    bool is_active(const VectorHandle& handle) const {
        auto it = active.find(handle.index);
        return it != active.end() && it->second == handle.size;
    }

    void validateHandle(const VectorHandle& handle, const char* label) const {
        if (handle.size == 0) {
            return;
        }
        if (handle.index > buffer.size() || handle.size > buffer.size() - handle.index) {
            throw std::runtime_error(std::string(label) + " out of bounds: invalid handle");
        }
        auto it = active.find(handle.index);
        if (it == active.end() || it->second != handle.size) {
            throw std::runtime_error(std::string(label) + " invalid handle: handle is not active");
        }
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
        if (size == 0) {
            return VectorHandle(freeFrom, 0);
        }

        auto it = freed.find(size);
        if (it != freed.end() && !it->second.empty()) {
            VectorHandle handle = it->second.front();
            it->second.pop_front();
            if (it->second.empty()) {
                freed.erase(it);
            }
            active[handle.index] = handle.size;
            return handle;
        }

        if (freeFrom + size > buffer.size()) {
            resizeBuffer(2 * buffer.size() + size);
        }

        VectorHandle handle(freeFrom, size);
        freeFrom += size;
        active[handle.index] = handle.size;
        return handle;
    }

    void reallocate(VectorHandle& handle, size_t newSize) {
        if (newSize == handle.size) return;
        validateHandle(handle, "VectorBuffer.reallocate");

        if (newSize < handle.size) {
            const VectorHandle released(handle.index + newSize, handle.size - newSize);
            if (newSize == 0) {
                active.erase(handle.index);
            } else {
                active[handle.index] = newSize;
            }
            handle.size = newSize;
            releaseRegion(released);
        } else {
            deleteHandle(handle);
            handle = allocate(newSize);
        }
    }

    void deleteHandle(const VectorHandle& handle) {
        if (handle.size == 0) {
            return;
        }
        validateHandle(handle, "VectorBuffer.delete");
        active.erase(handle.index);
        releaseRegion(handle);
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
    std::unordered_map<size_t, size_t> active;

    void zeroRegion(size_t start, size_t size) {
        if (size == 0) {
            return;
        }
        if (start > buffer.size() || size > buffer.size() - start) {
            throw std::runtime_error("VectorBuffer.zeroRegion out of bounds");
        }
        markDirty(start, size);
        std::fill(buffer.begin() + start, buffer.begin() + start + size, 0.0f);
    }

    void resizeBuffer(size_t newSize) {
        if (newSize <= buffer.size()) {
            throw std::runtime_error("Cannot downsize buffer manually.");
        }
        buffer.resize(newSize, 0.0f);
    }

    void releaseRegion(const VectorHandle& handle) {
        if (handle.size == 0) {
            return;
        }
        if (handle.index + handle.size == freeFrom) {
            freeFrom = handle.index;
            releaseTailFreeBlocks();
            clampDirtyToLength();
            return;
        }
        zeroRegion(handle.index, handle.size);
        freed[handle.size].push_back(handle);
    }

    void releaseTailFreeBlocks() {
        bool released = true;
        while (released) {
            released = false;
            for (auto mapIt = freed.begin(); mapIt != freed.end(); ) {
                auto& handles = mapIt->second;
                for (auto listIt = handles.begin(); listIt != handles.end(); ++listIt) {
                    if (listIt->index + listIt->size == freeFrom) {
                        freeFrom = listIt->index;
                        handles.erase(listIt);
                        released = true;
                        break;
                    }
                }
                if (handles.empty()) {
                    mapIt = freed.erase(mapIt);
                } else {
                    ++mapIt;
                }
                if (released) {
                    break;
                }
            }
        }
    }

    void clampDirtyToLength() {
        if (!has_dirty()) {
            return;
        }
        if (dirtyFrom >= freeFrom) {
            clearDirty();
            return;
        }
        if (dirtyTo > freeFrom) {
            dirtyTo = freeFrom;
        }
    }
};
