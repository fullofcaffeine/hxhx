// Execute the generated source with collection before every allocation.
#define main generated_main
#include "src/Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // Provider startup retains its array and six singleton values. The fixture
  // adds three Key singletons; static storage is the eleventh surviving object.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 11)
    throw std::runtime_error("enum map retained a temporary object or root");
}
