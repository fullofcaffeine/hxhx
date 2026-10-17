#include "ManagedEquality.hpp"
#include <stdexcept>

// Unsupported numeric comparisons must not hide the existing universal null
// boundary. No object descriptor or numeric conversion is needed for this test.
int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  {
    Root<Value> value(heap, boxInt64(heap, 1, 7));
    const Value empty;
    if (dynamicEquality(heap, value.get(), empty, false, nullptr) ||
        dynamicEquality(heap, empty, value.get(), false, nullptr) ||
        !dynamicEquality(heap, value.get(), empty, true, nullptr) ||
        !dynamicEquality(heap, empty, value.get(), true, nullptr) ||
        enumPayloadEquality(heap, empty, value.get(), nullptr))
      throw std::runtime_error("Int64 storage changed null membership in equality");
    bool rejected = false;
    try { (void)dynamicEquality(heap, value.get(), value.get(), false, nullptr); }
    catch (const std::invalid_argument&) { rejected = true; }
    if (!rejected) throw std::runtime_error("unsupported Int64 equality became object identity");
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.liveCount() != 0)
    throw std::runtime_error("Int64 null observer retained storage");
}
