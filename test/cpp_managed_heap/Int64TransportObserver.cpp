#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include "src/ManagedEquality.hpp"
#include <stdexcept>

// The ordinary generated program proves provider conversion and recovery.
// Direct storage observations additionally check tracing, layout and rejection.
int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("Int64 transport retained temporary roots");
  const auto retained = heap.liveCount();
  {
    Root<Value> wide(heap, boxInt64(heap, 1, 7));
    Root<Value> other(heap, boxInt64(heap, -2, 7));
    heap.collect();
    if (!isInt64Value(wide.get()) || int64High(wide.get()) != 1 || int64Low(wide.get()) != 7 ||
        int64String(wide.get()) != "4294967303" || int64String(other.get()) != "-8589934585" ||
        reflectionClass(wide.get(), nullptr, nullptr).kind() != ValueKind::Null ||
        wide.get().asManaged().hasLayout<InstancePayload>())
      throw std::runtime_error("Int64 transport lost its physical representation");
    for (const auto value : {Value(), Value::boolean(true), Value::floating(256.0), Value::string("2")}) {
      if (isInt64Value(value)) throw std::runtime_error("unrelated value acquired Int64 membership");
      bool rejected = false;
      try { (void)int64High(value); }
      catch (const std::invalid_argument&) { rejected = true; }
      if (!rejected) throw std::runtime_error("unsupported recovery silently converted a value");
    }
    if (!isInt64Value(Value::integer(-2)) || int64High(Value::integer(-2)) != -1 || int64Low(Value::integer(-2)) != -2)
      throw std::runtime_error("integer recovery lost sign extension");
    bool equalityRejected = false;
    try { (void)dynamicEquality(heap, wide.get(), other.get(), false, nullptr); }
    catch (const std::invalid_argument&) { equalityRejected = true; }
    if (!equalityRejected) throw std::runtime_error("unsupported Int64 equality became object identity");
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.liveCount() != retained)
    throw std::runtime_error("Int64 payloads survived their final roots");
}
