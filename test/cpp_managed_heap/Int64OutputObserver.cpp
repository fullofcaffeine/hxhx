#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <stdexcept>

// Real library providers retain their static object graph. Temporary roots must
// still leave scope, and collection must be safe at every allocation.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("Int64 execution retained temporary roots");
}
