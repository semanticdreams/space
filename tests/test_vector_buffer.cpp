#include "vector_buffer.h"

#include <cassert>
#include <stdexcept>

namespace {

template <typename Fn>
void assert_throws(Fn fn)
{
    bool threw = false;
    try {
        fn();
    } catch (const std::runtime_error&) {
        threw = true;
    }
    assert(threw);
}

void tail_delete_shrinks_without_dirty_free_work()
{
    VectorBuffer buffer(0);
    VectorHandle handle = buffer.allocate(100);
    buffer.clearDirty();

    buffer.deleteHandle(handle);

    assert(buffer.length() == 0);
    assert(buffer.free_count() == 0);
    assert(buffer.free_size() == 0);
    assert(!buffer.has_dirty());
}

void middle_delete_keeps_logical_length_and_marks_dirty()
{
    VectorBuffer buffer(0);
    VectorHandle left = buffer.allocate(10);
    VectorHandle middle = buffer.allocate(10);
    VectorHandle right = buffer.allocate(10);
    (void)left;
    (void)right;
    buffer.clearDirty();

    buffer.deleteHandle(middle);

    assert(buffer.length() == 30);
    assert(buffer.free_count() == 1);
    assert(buffer.free_size() == 10);
    assert(buffer.has_dirty());
    auto [from, to] = buffer.dirty_range();
    assert(from == 10);
    assert(to == 20);

    VectorHandle reused = buffer.allocate(10);
    assert(reused.index == 10);
    assert(reused.size == 10);
    assert(buffer.length() == 30);
    assert(buffer.free_count() == 0);
}

void tail_delete_coalesces_previous_middle_free()
{
    VectorBuffer buffer(0);
    VectorHandle left = buffer.allocate(10);
    VectorHandle middle = buffer.allocate(10);
    VectorHandle right = buffer.allocate(10);
    (void)left;

    buffer.deleteHandle(middle);
    buffer.clearDirty();
    buffer.deleteHandle(right);

    assert(buffer.length() == 10);
    assert(buffer.free_count() == 0);
    assert(buffer.free_size() == 0);
    assert(!buffer.has_dirty());
}

void shrinking_tail_handle_moves_logical_end()
{
    VectorBuffer buffer(0);
    VectorHandle handle = buffer.allocate(100);
    buffer.clearDirty();

    buffer.reallocate(handle, 20);

    assert(handle.index == 0);
    assert(handle.size == 20);
    assert(buffer.length() == 20);
    assert(buffer.free_count() == 0);
    assert(!buffer.has_dirty());
}

void shrinking_middle_handle_reuses_released_range()
{
    VectorBuffer buffer(0);
    VectorHandle left = buffer.allocate(10);
    VectorHandle right = buffer.allocate(10);
    (void)right;
    buffer.clearDirty();

    buffer.reallocate(left, 4);

    assert(left.index == 0);
    assert(left.size == 4);
    assert(buffer.length() == 20);
    assert(buffer.free_count() == 1);
    assert(buffer.free_size() == 6);
    assert(buffer.has_dirty());

    VectorHandle reused = buffer.allocate(6);
    assert(reused.index == 4);
    assert(reused.size == 6);
    assert(buffer.free_count() == 0);
}

void stale_handles_fail_loudly()
{
    VectorBuffer buffer(0);
    VectorHandle handle = buffer.allocate(8);
    buffer.deleteHandle(handle);
    assert_throws([&]() {
        buffer.deleteHandle(handle);
    });
}

void reused_slot_invalidates_stale_view_handle()
{
    VectorBuffer buffer(0);
    VectorHandle original = buffer.allocate(8);
    buffer.deleteHandle(original);

    VectorHandle replacement = buffer.allocate(8);
    assert(replacement.index == original.index);
    assert(replacement.size == original.size);

    assert_throws([&]() {
        (void)buffer.view(original);
    });
}

void growing_reallocate_invalidates_previous_handle_shape()
{
    VectorBuffer buffer(0);
    VectorHandle handle = buffer.allocate(8);
    VectorHandle stale = handle;

    buffer.reallocate(handle, 16);

    assert(handle.index == 0);
    assert(handle.size == 16);
    assert(buffer.is_active(handle));
    assert_throws([&]() {
        (void)buffer.view(stale);
    });
    assert_throws([&]() {
        buffer.deleteHandle(stale);
    });
}

} // namespace

int main()
{
    tail_delete_shrinks_without_dirty_free_work();
    middle_delete_keeps_logical_length_and_marks_dirty();
    tail_delete_coalesces_previous_middle_free();
    shrinking_tail_handle_moves_logical_end();
    shrinking_middle_handle_reuses_released_range();
    stale_handles_fail_loudly();
    reused_slot_invalidates_stale_view_handle();
    growing_reallocate_invalidates_previous_handle_shape();
    return 0;
}
