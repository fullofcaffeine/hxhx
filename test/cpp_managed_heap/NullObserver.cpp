#define main generated_main
#include "src/Main.cpp"
#undef main
#include "Completion.hpp"
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  if (!sourceCompleted(heap)) throw std::runtime_error("null assertion body did not complete");
  heap.collect();
  // Array resolves through its real declaration, but this fixture has no
  // provider startup graph. Only Main's primitive/null static storage survives.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("null execution retained a temporary allocation or root");
}
