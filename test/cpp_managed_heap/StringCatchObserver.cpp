#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <stdexcept>

// Collect at allocation boundaries, including while escaped catch cells survive.
// Only program storage and the provider's StackItem CFunction singleton remain
// after the complete authored contract returns and collection runs again.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 2)
    throw std::runtime_error("String catch retained temporary roots or allocations");
}
