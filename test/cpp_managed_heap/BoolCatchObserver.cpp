#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <stdexcept>

// This provider closure retains one program storage object and the StackItem
// CFunction singleton. Every wrapper, stack array, catch cell, and closure must
// disappear after the complete authored assertions finish and collection runs.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 2)
    throw std::runtime_error("Boolean catch retained temporary roots or allocations");
}
