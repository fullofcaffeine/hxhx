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
    try { HXHX_INTERFACE_EDGE(heap, mode); }
    catch (const ThrownValue& failure) {
      heap.collect();
      require(failure.value().asString() == (mode == 1 ? "receiver" : "argument"),
              "interface call replaced an operand failure");
      // Main.effects is the fixture's only static field. A receiver failure
      // skips the argument; an argument failure follows one receiver evaluation.
      require(storage->field_0.read().asInteger() == (mode == 1 ? 1 : 12),
              "interface failure changed operand order or invocation count");
      require(heap.rootCount() == 1 && heap.liveCount() == 1,
              "interface unwind retained a temporary receiver or argument");
      caught = true;
    }
    require(caught, "interface call swallowed an operand failure");
  }
  bool nullRejected = false;
  try { HXHX_INTERFACE_EDGE(heap, 3); }
  catch (...) { nullRejected = true; }
  // Upstream native debug mode evaluates the argument before the null error.
  // This checks order and cleanup, not the unfinished Haxe catch/wrapper policy.
  require(nullRejected && storage->field_0.read().asInteger() == 12,
          "null interface receiver returned a value or lost argument effects");
  heap.collect();
  require(heap.rootCount() == 0 && heap.liveCount() == 1,
          "null interface call retained an argument or receiver root");
  require(HXHX_INTERFACE_EDGE(heap, 0) == 18,
          "temporary interface receiver did not survive argument allocation");
  require(storage->field_0.read().asInteger() == 12,
          "successful interface call changed operand order");
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 1 && heap.liveCount() == 1,
          "interface calls retained temporary roots or allocations");
}
