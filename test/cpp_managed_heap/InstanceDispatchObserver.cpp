#define main generated_main
#include "src/Main.cpp"
#undef main
#include <stdexcept>

// Every allocation can collect. The authored program checks a temporary
// receiver across an allocating argument and an object returned by an override.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // Only the program's static Int field storage remains after calls unwind.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("instance dispatch retained temporary storage");
}
