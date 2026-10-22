#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string>

// This body comes from the Haxe-owned Std.int binding. The full program below
// separately proves that source calls select it through the production target.
static std::int32_t observedConversion(hxhx::managed::Heap& heap,
                                       const hxhx::managed::Value& source,
                                       int& effects) {
  hxhx::managed::Root<hxhx::managed::Value> converted(heap);
#include "StdIntBoundary.inc"
  return converted.get().asInteger();
}

static void accepted(hxhx::managed::Heap& heap,
                     const hxhx::managed::Value& value, std::int32_t expected) {
  int effects = 0;
  if (observedConversion(heap, value, effects) != expected || effects != 1)
    throw std::runtime_error("Std.int changed conversion or operand count");
  if (heap.rootCount() != 0)
    throw std::runtime_error("Std.int retained an operand root");
}

static void unsupported(hxhx::managed::Heap& heap,
                        const hxhx::managed::Value& value,
                        const std::string& expected) {
  int effects = 0;
  bool rejected = false;
  try {
    observedConversion(heap, value, effects);
  } catch (const std::runtime_error& failure) {
    rejected = failure.what() == expected;
  }
  if (!rejected || effects != 1 || heap.rootCount() != 0)
    throw std::runtime_error("Std.int lost its unsupported-input boundary");
}

int main() {
  using hxhx::managed::Value;
  hxhx::managed::Heap heap(0);
  accepted(heap, Value::integer(std::numeric_limits<std::int32_t>::min()),
           std::numeric_limits<std::int32_t>::min());
  accepted(heap, Value::integer(std::numeric_limits<std::int32_t>::max()),
           std::numeric_limits<std::int32_t>::max());
  accepted(heap, Value::floating(17.875), 17);
  accepted(heap, Value::floating(-17.875), -17);
  accepted(heap, Value::floating(0.75), 0);
  accepted(heap, Value::floating(-0.75), 0);
  accepted(heap, Value{}, 0);
  accepted(heap, Value::boolean(false), 0);
  accepted(heap, Value::boolean(true), 1);
  accepted(heap, Value::floating(2147483647.0), 2147483647);
  accepted(heap, Value::floating(-2147483648.0), -2147483647 - 1);
  const auto negativeZero = Value::floating(-0.0);
  accepted(heap, negativeZero, 0);
  if (!std::signbit(negativeZero.asFloat()))
    throw std::runtime_error("Std.int changed its input storage");
  for (const auto value : {2147483647.875, -2147483648.875, 2147483648.0,
                          -2147483649.0, 1.0e100,
                          std::numeric_limits<double>::quiet_NaN(),
                          std::numeric_limits<double>::infinity(),
                          -std::numeric_limits<double>::infinity()})
    unsupported(heap, Value::floating(value),
                "unsupported Std.int value outside the finite Int32 range");
  unsupported(heap, Value::string("17.5"),
              "unsupported Std.int runtime value");
  hxhx_program_run(heap);
  heap.collect();
  // The complete real provider closure owns the same persistent values as the
  // standard string fixture. Temporary conversion roots must all unwind.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 15)
    throw std::runtime_error("Std.int retained unexpected program storage");
}
