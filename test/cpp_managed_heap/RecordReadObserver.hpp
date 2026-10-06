#pragma once

namespace managed_record_test {
using namespace hxhx::managed;
static unsigned effects = 0;
static bool failRight = false;
static void require(bool value) {
  if (!value) throw std::runtime_error("managed record read contract changed");
}
static void left(Heap& heap, ErasedRef, Root<Value>& result) {
  require(effects++ == 0);
  heap.collect();
  result.set(Value::string("same"));
}
static void right(Heap& heap, ErasedRef, Root<Value>& result) {
  require(effects++ == 1);
  heap.collect();
  if (failRight) throw std::runtime_error("record operand failure");
  result.set(Value::string("same"));
}
static void run(Heap& heap) {
  require(generatedRecordequal(heap, {}, {}));
  require(!generatedRecordequal(heap, {}, Value::string("")));
  require(!generatedRecordequal(heap, Value::string(""), {}));
  require(generatedRecordequal(heap, Value::string(""), Value::string("")));
  const auto bytes = Value::string(std::string("h\xc3\xa9\0z", 5));
  require(generatedRecordequal(heap, bytes, bytes));
  require(generatedRecordunequal(heap, Value::string("a"), Value::string("b")));
  require(!generatedRecordunequal(heap, {}, {}));
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> a(heap), b(heap);
    heap.allocateInto(a, &left, ErasedRef{});
    heap.allocateInto(b, &right, ErasedRef{});
    require(generatedRecordordered(heap, Value::managed(a.get()), Value::managed(b.get())));
    require(effects == 2);
    effects = 0;
    failRight = true;
    bool threw = false;
    try { generatedRecordordered(heap, Value::managed(a.get()), Value::managed(b.get())); }
    catch (const std::runtime_error&) { threw = true; }
    require(threw && effects == 2);
    failRight = false;
  }
  heap.collect();
  require(heap.liveCount() == 0);
}
} // namespace managed_record_test
