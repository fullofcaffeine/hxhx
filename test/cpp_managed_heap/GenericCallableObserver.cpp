// Force collection before each allocation. Callback aliases must retain their
// captures during execution and release the entire local graph on return.
#define main generated_main
#include "Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("generic callbacks retained local allocations or roots");
}
