#define main generated_main
#include "src/Main.cpp"
#undef main
#include "NullRead.hpp"
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static int indexCalls = 0;
static std::string writeEvents;
static void writeIndex(Heap& heap, ErasedRef, Root<Value>& result) {
  writeEvents += 'i';
  heap.collect();
  result.set(Value::integer(2));
}
static void writeValue(Heap& heap, ErasedRef, Root<Value>& result) {
  writeEvents += 'v';
  heap.collect();
  result.set(Value::integer(7));
}
static void indexEffect(Heap& heap, ErasedRef, Root<Value>& result) {
  ++indexCalls;
  heap.collect();
  result.set(Value::integer(0));
}

static void recovery(Heap& heap) {
  Root<Value> result(heap);
  for (const auto source : {Value{}, Value::integer(7), Value::string("not an array")}) {
    observe_recoverBoolean(heap, result, source);
    if (result.get().kind() != ValueKind::Null) throw std::runtime_error("non-array recovery was not null");
  }
  for (const auto representation : {ArrayRepresentation::Boolean, ArrayRepresentation::Dynamic, ArrayRepresentation::Integer}) {
    Root<Ref<ArrayPayload>> original(heap);
    heap.allocateInto(original, representation);
    observe_recoverBoolean(heap, result, Value::managed(original.get()));
    auto recovered = result.get().asManaged().as<ArrayPayload>();
    const bool aliases = representation != ArrayRepresentation::Integer;
    if ((recovered == original.get()) != aliases) throw std::runtime_error("empty recovery lost representation identity");
    original.get()->append(representation == ArrayRepresentation::Boolean ? Value::boolean(true) : Value::integer(2));
    observe_returnBoolean(heap, result, Value::managed(original.get()));
    recovered = result.get().asManaged().as<ArrayPayload>();
    if ((recovered == original.get()) != aliases || !observe_readBoolean(heap, result.get(), 0))
      throw std::runtime_error("recovery lost conversion or alias identity");
    if (observe_writeBoolean(heap, result.get(), 0, false)) throw std::runtime_error("array write returned another value");
    if (aliases ? original.get()->read(0).asBoolean() : original.get()->read(0).asInteger() != 2)
      throw std::runtime_error("recovery mutation changed the wrong allocation");
    heap.collect();
    if (observe_readBoolean(heap, result.get(), 0)) throw std::runtime_error("collected recovery lost mutation");
  }
  Root<Ref<ArrayPayload>> dynamic(heap);
  heap.allocateInto(dynamic, ArrayRepresentation::Dynamic);
  dynamic.get()->append(Value::integer(0));
  dynamic.get()->append(Value::integer(-1));
  dynamic.get()->append(Value{});
  dynamic.get()->append(Value::string("yes"));
  observe_recoverBoolean(heap, result, Value::managed(dynamic.get()));
  if (observe_readBoolean(heap, result.get(), 0) || !observe_readBoolean(heap, result.get(), 1)
      || observe_readBoolean(heap, result.get(), 2) || observe_readBoolean(heap, result.get(), 3))
    throw std::runtime_error("Boolean Dynamic view differs from native conversion");
  if (!observe_writeBoolean(heap, result.get(), 6, true) || dynamic.get()->size() != 7
      || dynamic.get()->read(4).kind() != ValueKind::Boolean || dynamic.get()->read(4).asBoolean()
      || dynamic.get()->read(5).asBoolean() || !dynamic.get()->read(6).asBoolean())
    throw std::runtime_error("Boolean view growth lost its typed gap defaults or alias");
  if (!observe_writeBoolean(heap, result.get(), -1, true) || dynamic.get()->size() != 7)
    throw std::runtime_error("negative write changed storage or lost its result");
  if (observe_pushBoolean(heap, result.get(), false) != 8 || dynamic.get()->size() != 8 || dynamic.get()->read(7).asBoolean())
    throw std::runtime_error("push through recovered view lost its alias or returned length");
  observe_discardPush(heap, result.get(), true);
	if (dynamic.get()->size() != 9 || !dynamic.get()->read(8).asBoolean())
		throw std::runtime_error("discarded public push lost its mutation");
  heap.collect();
  if (observe_lengthBoolean(heap, result.get()) != 9)
    throw std::runtime_error("array length did not observe shared push mutation");
  bool rejected = false;
  try { observe_lengthBoolean(heap, Value{}); }
  catch (const std::invalid_argument& error) { rejected = std::string(error.what()) == "array length has no array"; }
  if (!rejected || heap.rootCount() != 2)
    throw std::runtime_error("null length read passed or leaked roots");
}

static void writes(Heap& heap) {
  Root<Ref<ArrayPayload>> values(heap);
  heap.allocateInto(values, ArrayRepresentation::Integer);
  values.get()->append(Value::integer(1));
  if (observe_writeInteger(heap, Value::managed(values.get()), 3, 8) != 8 || values.get()->size() != 4
      || values.get()->read(0).asInteger() != 1 || values.get()->read(1).asInteger() != 0
      || values.get()->read(2).asInteger() != 0 || values.get()->read(3).asInteger() != 8)
    throw std::runtime_error("integer write growth differs from native behavior");
  Root<Ref<CallablePayload<void(Root<Value>&)>>> index(heap), value(heap);
  heap.allocateInto(index, &writeIndex, ErasedRef{});
  heap.allocateInto(value, &writeValue, ErasedRef{});
  if (observe_writeWithIndex(heap, Value::managed(values.get()), Value::managed(index.get()), Value::managed(value.get())) != 7
      || writeEvents != "vi" || values.get()->read(2).asInteger() != 7)
    throw std::runtime_error("collecting assignment changed evaluation order or storage");
  writeEvents.clear();
  bool rejected = false;
  try { observe_writeWithIndex(heap, Value{}, Value::managed(index.get()), Value::managed(value.get())); }
  catch (const std::invalid_argument& error) {
    rejected = std::string(error.what()) == "array assignment has no array";
  }
  if (!rejected || writeEvents != "vi" || heap.rootCount() != 3)
    throw std::runtime_error("failed array assignment lost effects or leaked roots");
  writeEvents.clear();
  if (observe_pushWithValue(heap, Value::managed(values.get()), Value::managed(value.get())) != 5
      || writeEvents != "v" || values.get()->read(4).asInteger() != 7)
    throw std::runtime_error("collecting push lost its array or result");
  writeEvents.clear();
  rejected = false;
  try { observe_pushWithValue(heap, Value{}, Value::managed(value.get())); }
  catch (const std::invalid_argument& error) { rejected = std::string(error.what()) == "array append has no array"; }
  if (!rejected || writeEvents != "v" || heap.rootCount() != 3)
    throw std::runtime_error("failed push lost argument effects or leaked roots");
}

int main() {
  Heap heap(0);
  hxhx_program_run(heap);
  recovery(heap);
  writes(heap);
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("array read leaked a temporary root");
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> effect(heap);
    heap.allocateInto(effect, &indexEffect, ErasedRef{});
    bool rejected = false;
    try { observeArrayRead(heap, Value{}, Value::managed(effect.get())); }
    catch (const std::invalid_argument& error) {
      rejected = std::string(error.what()) == "array read has no array";
    }
    if (!rejected || indexCalls != 1 || heap.rootCount() != 1)
      throw std::runtime_error("null receiver lost index effects or leaked roots");
    Root<Ref<ArrayPayload>> values(heap);
    heap.allocateInto(values, ArrayRepresentation::Integer);
    values.get()->append(Value::integer(9));
    if (observeArrayRead(heap, Value::managed(values.get()), Value::managed(effect.get())) != 9
        || indexCalls != 2 || heap.rootCount() != 2)
      throw std::runtime_error("collecting index changed a valid array read");
  }
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("array boundary roots escaped their scope");
  heap.collect();
}
