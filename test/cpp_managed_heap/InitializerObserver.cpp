#include "Generated.hpp"
#include <iostream>
#include <stdexcept>
#include <cstdlib>
#include <new>

// Observe a failed allocation inside generated initialization, without a runtime test switch.
static bool failNextAllocation = false;
void* operator new(std::size_t size) {
  if (failNextAllocation) { failNextAllocation = false; throw std::bad_alloc(); }
  if (void* value = std::malloc(size == 0 ? 1 : size)) return value;
  throw std::bad_alloc();
}
void operator delete(void* value) noexcept { std::free(value); }
void operator delete(void* value, std::size_t) noexcept { std::free(value); }

using namespace hxhx::managed;
static void require(bool condition) { if (!condition) throw std::runtime_error("initializer observer failed"); }

int main() {
  Heap heap(0);
  publishStorage(heap);
  bool rejected = false;
  // An out-of-order execution must fail instead of replacing a missing dependency with null.
  try { hxhx_initializer_second(heap); } catch (const std::logic_error&) { rejected = true; }
  require(rejected && heap.liveCount() == 1);
  hxhx_initializer_first(heap);
  hxhx_initializer_second(heap);
  hxhx_initializer_record(heap);
  heap.collect();
  require(heap.liveCount() == 2 && heap.staticRootCount() == 1);
  std::cout << generated_firstValue(heap) << '\n';
  std::cout << generated_read(heap) << '\n';
  Root<Value> label(heap);
  generated_label(heap, label);
  std::cout << label.get().asString() << '\n';
  label.set({});
  heap.collect();
  require(heap.liveCount() == 2); // The initialized record survives through its static field.
  Root<Value> observed(heap);
  generated_current(heap, observed);
  const auto retained = observed.get().asManaged().allocationId();
  observed.set({});
  failNextAllocation = true;
  rejected = false;
  try { hxhx_initializer_record(heap); } catch (const std::bad_alloc&) { rejected = true; }
  require(rejected && !failNextAllocation);
  heap.collect();
  generated_current(heap, observed);
  require(observed.get().asManaged().allocationId() == retained && generated_read(heap) == 8);
  require(heap.liveCount() == 2); // A failed initializer did not commit or leak a partial replacement.
}
