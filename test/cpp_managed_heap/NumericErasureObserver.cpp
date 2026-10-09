#include HXHX_LOCAL_PROGRAM
#include <cmath>
#include <limits>
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Supply Float ABI inputs to authored Haxe functions. The observer never boxes
// them into Dynamic itself, so a missing source conversion cannot pass this test.
static void observe(Heap& heap, double value, bool integer) {
  const double kept = generated_preserve(heap, value);
  require(std::isnan(value) ? std::isnan(kept) : kept == value, "typed Float transport changed a value");
  if (value == 0.0)
    require(std::signbit(kept) == std::signbit(value), "typed Float transport changed signed zero");
  using Erase = void (*)(Heap&, Root<Value>&, double);
  for (Erase erase : {generated_erase, generated_eraseAny, generated_thrown,
                     generated_called, generated_closure,
                     generated_initialized, generated_assigned, generated_record,
                     generated_recordWrite, generated_array, generated_arrayPush,
                     generated_arrayWrite, generated_mapLiteral, generated_mapSet}) {
    Root<Value> result(heap);
    erase(heap, result, value);
    heap.collect();
    require(result.get().kind() == (integer ? ValueKind::Integer : ValueKind::Float), "opaque erasure selected the wrong numeric kind");
    if (integer) {
      require(result.get().asInteger() == static_cast<std::int32_t>(value), "opaque integer value changed");
    } else {
      const double number = result.get().asFloat();
      require(std::isnan(value) ? std::isnan(number) : number == value, "opaque Float value changed");
    }
  }
}

int main() {
  Heap heap(0);
  {
    Root<Value> kept(heap);
    generated_keepOpaque(heap, kept, Value::floating(7.0));
    require(kept.get().kind() == ValueKind::Float, "an already opaque value was reclassified");
  }
  for (int step = -8192; step <= 8192; ++step)
    observe(heap, step / 2.0, step >= -2 && step <= 510 && step % 2 == 0);
  for (double value : {-2147483649.0, -2147483648.0, -2147483647.0, 2147483646.0, 2147483647.0, 2147483648.0,
                       -0.25, 0.25, 254.99999999999997, 255.00000000000003,
                       std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::infinity(),
                       -std::numeric_limits<double>::infinity()})
    observe(heap, value, false);
  observe(heap, -0.0, true);
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 0 && heap.liveCount() == 0,
          "numeric transport retained roots or allocations");
}
