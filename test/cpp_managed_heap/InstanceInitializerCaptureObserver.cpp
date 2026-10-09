// Run the generated program with collection at every allocation, then check
// that its callbacks, environments, cells, and instances are no longer retained.
#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("initializer closures retained temporary storage");
}
