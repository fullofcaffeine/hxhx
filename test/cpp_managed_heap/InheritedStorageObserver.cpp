#define main generated_main
#include HXHX_INHERITED_PROGRAM
#undef main
#include <stdexcept>

// The authored assertions run while every allocation can collect. Only the
// program's empty static root may remain after all ordinary roots leave scope.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("inherited construction retained temporary storage");
}
