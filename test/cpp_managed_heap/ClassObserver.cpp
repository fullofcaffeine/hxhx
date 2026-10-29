#define main generated_main
#include "src/Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("class execution leaked entry or temporary roots");
  heap.collect();
}
