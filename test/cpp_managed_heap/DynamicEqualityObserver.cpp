#include HXHX_LOCAL_PROGRAM
#include <fstream>
#include <limits>
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// The expected rows come from the independent upstream source program. Keep
// equality and inequality separate, including numeric/String incomparability.
static void scalars(Heap& heap) {
  const std::vector<Value> values = {
    Value(), Value::boolean(false), Value::boolean(true), Value::integer(0),
    Value::integer(1), Value::integer(-1), Value::integer(255), Value::integer(256),
    Value::floating(0.0), Value::floating(-0.0), Value::floating(1.0), Value::floating(1.5),
    Value::floating(std::numeric_limits<double>::quiet_NaN()),
    Value::floating(std::numeric_limits<double>::infinity()),
    Value::floating(-std::numeric_limits<double>::infinity()),
    Value::string(""), Value::string("0"), Value::string("1"), Value::string("true")
  };
  std::ifstream expected("test/oracle/cpp_dynamic_equality_seed/expected.cpp.stdout");
  require(expected.good(), "missing upstream equality observations");
  for (std::size_t i = 0; i < values.size(); ++i) {
    std::string row;
    require(static_cast<bool>(std::getline(expected, row)), "missing upstream matrix row");
    const auto first = row.find(':');
    const auto second = row.find(':', first + 1);
    require(first != std::string::npos && second != std::string::npos, "malformed upstream matrix row");
    const auto equal = row.substr(first + 1, second - first - 1);
    const auto different = row.substr(second + 1);
    require(equal.size() >= values.size() && different.size() == equal.size(), "truncated upstream matrix row");
    for (std::size_t j = 0; j < values.size(); ++j) {
      require(generated_equal(heap, values[i], values[j]) == (equal[j] == '1'), "erased equality differs from upstream");
      require(generated_different(heap, values[i], values[j]) == (different[j] == '1'), "erased inequality differs from upstream");
      require(generated_anyEqual(heap, values[i], values[j]) == (equal[j] == '1'), "Any lost erased equality");
    }
  }
}

static int calls = 0;
static ErasedRef firstAllocation;

// The only surviving root for the first result during the second call belongs
// to the generated binary expression, not this observer or the callback.
static void leftEntry(Heap& heap, ErasedRef, Root<Value>& result) {
  require(calls++ == 0, "left operand evaluated out of order or more than once");
  Root<Ref<RecordPayload>> record(heap);
  heap.allocateInto(record);
  record.get()->define("answer", Value::integer(42));
  firstAllocation = ErasedRef(record.get());
  result.set(Value::managed(record.get()));
}

static void rightEntry(Heap& heap, ErasedRef, Root<Value>& result) {
  require(calls++ == 1, "right operand evaluated out of order or more than once");
  heap.collect();
  require(firstAllocation.as<RecordPayload>()->read("answer").asInteger() == 42, "first operand lost its root");
  result.set(Value::managed(firstAllocation));
}

static void throwingEntry(Heap& heap, ErasedRef, Root<Value>&) {
  require(calls++ == 1, "throwing right operand lost evaluation order");
  heap.collect();
  throw std::runtime_error("right operand failed");
}

static void lifetimes(Heap& heap) {
  using Callback = CallablePayload<void(Root<Value>&)>;
  Root<Ref<Callback>> left(heap), right(heap), throwing(heap);
  heap.allocateInto(left, &leftEntry, ErasedRef{});
  heap.allocateInto(right, &rightEntry, ErasedRef{});
  heap.allocateInto(throwing, &throwingEntry, ErasedRef{});
  require(generated_ordered(heap, Value::managed(left.get()), Value::managed(right.get())), "ordered comparison lost identity");
  require(calls == 2, "comparison repeated an operand");
  heap.collect();
  require(heap.liveCount() == 3, "successful comparison retained its result allocation");
  calls = 0;
  bool failed = false;
  try { generated_ordered(heap, Value::managed(left.get()), Value::managed(throwing.get())); }
  catch (const std::runtime_error& error) { failed = std::string(error.what()) == "right operand failed"; }
  require(failed && calls == 2, "comparison swallowed an operand failure");
  heap.collect();
  require(heap.liveCount() == 3, "failed comparison retained its first operand");
}

// Independent allocations retain identity even when their contents match.
// Descriptor names are deliberately identical: addresses identify declarations.
static void references(Heap& heap) {
  Root<Ref<RecordPayload>> record(heap), recordCopy(heap);
  heap.allocateInto(record);
  heap.allocateInto(recordCopy);
  record.get()->define("name", Value::string("same"));
  recordCopy.get()->define("name", Value::string("same"));
  Root<Ref<ArrayPayload>> array(heap), arrayCopy(heap);
  heap.allocateInto(array, ArrayRepresentation::String);
  heap.allocateInto(arrayCopy, ArrayRepresentation::String);
  array.get()->append(Value::string("same"));
  arrayCopy.get()->append(Value::string("same"));
  static const ClassDescriptor descriptor{"Same", true, 0, nullptr};
  static const ClassDescriptor otherDescriptor{"Same", true, 0, nullptr};
  static const InstanceDescriptor application{descriptor};
  Root<Ref<InstancePayload>> instance(heap), instanceCopy(heap);
  heap.allocateInto(instance, application, std::vector<Value>{});
  heap.allocateInto(instanceCopy, application, std::vector<Value>{});
  using Callback = CallablePayload<void(Root<Value>&)>;
  Root<Ref<Callback>> callable(heap), callableCopy(heap);
  heap.allocateInto(callable, &leftEntry, ErasedRef{});
  heap.allocateInto(callableCopy, &leftEntry, ErasedRef{});
  const std::vector<Value> first = {Value::managed(record.get()), Value::managed(array.get()),
    Value::managed(instance.get()), Value::managed(callable.get()), Value::descriptor(&descriptor)};
  const std::vector<Value> copies = {Value::managed(recordCopy.get()), Value::managed(arrayCopy.get()),
    Value::managed(instanceCopy.get()), Value::managed(callableCopy.get()), Value::descriptor(&otherDescriptor)};
  for (std::size_t i = 0; i < first.size(); ++i) {
    require(generated_equal(heap, first[i], first[i]), "alias lost identity");
    require(!generated_different(heap, first[i], first[i]), "alias became unequal");
    require(!generated_equal(heap, first[i], copies[i]), "independent values acquired the same identity");
    require(generated_different(heap, first[i], copies[i]), "independent values became equal");
    for (const Value& other : {Value(), Value::boolean(false), Value::integer(0), Value::string("")}) {
      require(!generated_equal(heap, first[i], other) && !generated_equal(heap, other, first[i]), "reference acquired scalar equality");
      require(generated_different(heap, first[i], other) && generated_different(heap, other, first[i]), "reference lost scalar inequality");
    }
  }
}

int main() {
  Heap heap(0);
  scalars(heap);
  lifetimes(heap);
  references(heap);
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 0 && heap.liveCount() == 0,
    "equality retained temporary roots or allocations");
}
