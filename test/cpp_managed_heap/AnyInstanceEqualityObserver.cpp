#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include "Bindings.hpp"
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

int main() {
  Heap heap(0);
  hxhx_program_run(heap);
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  for (const int mode : {1, 2}) {
    bool caught = false;
    try { HXHX_COMPARE_FAILURE(heap, mode == 1, mode == 2); }
    catch (const ThrownValue& failure) {
      heap.collect();
      require(failure.value().asString() == (mode == 1 ? "left" : "right"), "comparison replaced a thrown operand");
      // The fixture has one static Int field, Main.effects. The throwing left
      // operand skips the right; a throwing right follows exactly one left.
      require(storage->field_0.read().asInteger() == (mode == 1 ? 1 : 12), "comparison reordered operand effects");
      require(heap.rootCount() == 1 && heap.liveCount() == 1, "unwind retained an operand root or allocation");
      caught = true;
    }
    require(caught, "comparison did not propagate its operand failure");
  }
  require(!HXHX_COMPARE_FAILURE(heap, false, false), "distinct allocating operands compared equal");
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 1 && heap.liveCount() == 1,
          "opaque comparison retained temporary roots or instances");
}
