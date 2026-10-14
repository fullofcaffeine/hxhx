#include "ManagedValue.hpp"
#include "FloatArray.hpp"
#include <cmath>
#include <stdexcept>
using namespace hxhx::managed;

// The authored read/write methods must select positive-zero defaults for both
// missing reads and grown slots. Existing signed values must remain untouched.
static void floatDefaults(Heap& heap) {
  Root<Ref<ArrayPayload>> values(heap);
  heap.allocateInto(values, ArrayRepresentation::Float);
  const auto source = Value::managed(values.get());
  for (int index : {-1, 0, 3}) {
    const double missing = observe_readFloat(heap, source, index);
    if (missing != 0.0 || std::signbit(missing))
      throw std::runtime_error("missing Float read did not return positive zero");
  }
  const double assigned = observe_writeFloat(heap, source, 3, -0.0);
  if (assigned != 0.0 || !std::signbit(assigned) || values.get()->size() != 4)
    throw std::runtime_error("Float assignment lost negative zero or growth");
  heap.collect();
  for (int index : {0, 1, 2}) {
    const auto stored = values.get()->read(index);
    const double observed = observe_readFloat(heap, source, index);
    if (stored.kind() != ValueKind::Float || stored.asFloat() != 0.0
        || std::signbit(stored.asFloat()) || observed != 0.0 || std::signbit(observed))
      throw std::runtime_error("grown Float gap did not retain positive zero");
  }
  if (!std::signbit(observe_readFloat(heap, source, 3)))
    throw std::runtime_error("Float read lost stored negative zero");
}

int main() {
  for (int run = 0; run < 2; ++run) {
    Heap heap(0);
    floatDefaults(heap);
    if (heap.rootCount() != 0) throw std::runtime_error("Float array roots escaped");
    heap.collect();
    if (heap.liveCount() != 0) throw std::runtime_error("Float array survived without roots");
  }
}
