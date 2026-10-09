// Force collection before every allocation in the unchanged generated program.
#define main generated_main
#include "Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // Real provider startup retains its escape-character array and six nullary
  // enum singletons, plus static storage. No Inspector, closure, Map, or Payload
  // from Main belongs to that persistent graph.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 8)
    throw std::runtime_error("runtime tests retained temporary generic operands");
}
