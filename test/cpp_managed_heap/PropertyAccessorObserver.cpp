#define main generated_main
#include "src/Main.cpp"
#undef main
#include <stdexcept>

// Property receivers and getter values must survive collection during argument
// evaluation. The authored assertions run with collection before each allocation.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("property access retained temporary storage");
}
