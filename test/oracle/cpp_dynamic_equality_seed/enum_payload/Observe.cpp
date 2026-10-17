#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <stdexcept>

int main() {
  using namespace hxhx::managed;
  for (int run = 0; run < 2; ++run) {
    Heap heap(0);
    hxhx_program_run(heap);
    heap.collect();
    // The real Sys dependency closure retains Type.ValueType (7), StackItem (1),
    // Encoding (2), Error (3), and the shared SysTools.winMetaCharacters array.
    // Program storage adds one allocation; the source fixture adds its Empty.
    if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 15 + ENUM_SINGLETONS)
      throw std::runtime_error("enum comparison retained unexpected roots or values: "
        + std::to_string(heap.rootCount()) + ":" + std::to_string(heap.staticRootCount())
        + ":" + std::to_string(heap.liveCount()));
  }
}
