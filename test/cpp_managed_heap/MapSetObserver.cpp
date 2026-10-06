#include HXHX_LOCAL_PROGRAM
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
using Callback = CallablePayload<void(Root<Value>&)>;
enum class Failure { None, Receiver, Key, Value };
static Failure failure = Failure::None;
static std::string effects;
static ErasedRef lastKey;
static ErasedRef lastValue;
static std::int32_t integerValue = 2;

static void require(bool condition) {
  if (!condition) throw std::runtime_error("Map.set contract changed");
}
static void stage(Heap& heap, const char* text, Failure point) {
  effects += text;
  heap.collect();
  if (failure == point) throw std::runtime_error(text);
}
static void receiver(Heap& heap, ErasedRef environment, Root<Value>& result) {
  stage(heap, "R", Failure::Receiver);
  result.set(Value::managed(environment));
}
static void key(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "K", Failure::Key);
  result.set(Value::string("item"));
}
static void boolean(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "V", Failure::Value);
  result.set(Value::boolean(true));
}
static void integerKey(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "K", Failure::Key);
  result.set(Value::integer(7));
}
static void text(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "V", Failure::Value);
  result.set(Value::string("value"));
}
static void integer(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "V", Failure::Value);
  result.set(Value::integer(integerValue));
}
static void freshReceiver(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "R", Failure::Receiver);
  Root<Ref<StringMapPayload>> map(heap);
  heap.allocateInto(map);
  result.set(Value::managed(map.get()));
}
static void objectKey(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "K", Failure::Key);
  Root<Ref<RecordPayload>> value(heap);
  heap.allocateInto(value);
  value.get()->define("id", Value::integer(1));
  lastKey = ErasedRef(value.get()); // Observation only; this is deliberately not an outside root.
  result.set(Value::managed(value.get()));
}
static void objectValue(Heap& heap, ErasedRef, Root<Value>& result) {
  stage(heap, "V", Failure::Value);
  Root<Ref<RecordPayload>> value(heap);
  heap.allocateInto(value);
  value.get()->define("name", Value::string("value"));
  heap.collect();
  lastValue = ErasedRef(value.get());
  result.set(Value::managed(value.get()));
}

static void run(Heap& heap) {
  Root<Ref<StringMapPayload>> strings(heap), numbers(heap);
  Root<Ref<IntMapPayload>> integers(heap);
  Root<Ref<ObjectMapPayload>> objects(heap);
  heap.allocateInto(strings);
  heap.allocateInto(numbers);
  heap.allocateInto(integers);
  heap.allocateInto(objects);
  Root<Ref<Callback>> receive(heap), selectedKey(heap), value(heap), fresh(heap);
  heap.allocateInto(receive, &receiver, ErasedRef(strings.get()));
  heap.allocateInto(selectedKey, &key, ErasedRef{});
  heap.allocateInto(value, &boolean, ErasedRef{});
  heap.allocateInto(fresh, &freshReceiver, ErasedRef{});
  for (Failure mode : {Failure::None, Failure::Receiver, Failure::Key, Failure::Value}) {
    strings.get()->insert("item", Value::boolean(false));
    failure = mode;
    effects.clear();
    bool threw = false;
    try { generated_strings(heap, Value::managed(receive.get()), Value::managed(selectedKey.get()), Value::managed(value.get())); }
    catch (const std::runtime_error& error) {
      threw = true;
      require(std::string(error.what()) == (mode == Failure::Receiver ? "R" : mode == Failure::Key ? "K" : "V"));
    }
    require(threw == (mode != Failure::None));
    require(effects == (mode == Failure::Receiver ? "R" : mode == Failure::Key ? "RK" : "RKV"));
    require(strings.get()->size() == 1 && strings.get()->readExisting("item").asBoolean() == (mode == Failure::None));
  }
  failure = Failure::None;
  effects.clear();
  generated_strings(heap, Value::managed(fresh.get()), Value::managed(selectedKey.get()), Value::managed(value.get()));
  require(effects == "RKV");
  heap.allocateInto(receive, &receiver, ErasedRef(numbers.get()));
  heap.allocateInto(value, &integer, ErasedRef{});
  for (std::int32_t sample : {2, -2147483647 - 1, -1, 0, 16777217, 2147483647}) {
    integerValue = sample;
    effects.clear();
    generated_number(heap, Value::managed(receive.get()), Value::managed(selectedKey.get()), Value::managed(value.get()));
    require(effects == "RKV" && numbers.get()->size() == 1);
    require(numbers.get()->readExisting("item").kind() == ValueKind::Float);
    require(numbers.get()->readExisting("item").asFloat() == static_cast<double>(sample));
  }
  heap.allocateInto(receive, &receiver, ErasedRef(integers.get()));
  heap.allocateInto(selectedKey, &integerKey, ErasedRef{});
  heap.allocateInto(value, &text, ErasedRef{});
  effects.clear();
  generated_integers(heap, Value::managed(receive.get()), Value::managed(selectedKey.get()), Value::managed(value.get()));
  require(effects == "RKV" && integers.get()->readExisting(7).asString() == "value");
  heap.allocateInto(receive, &receiver, ErasedRef(objects.get()));
  heap.allocateInto(selectedKey, &objectKey, ErasedRef{});
  heap.allocateInto(value, &objectValue, ErasedRef{});
  effects.clear();
  generated_objects(heap, Value::managed(receive.get()), Value::managed(selectedKey.get()), Value::managed(value.get()));
  heap.collect();
  require(effects == "RKV" && objects.get()->size() == 1 && objects.get()->contains(lastKey));
  require(objects.get()->readExisting(lastKey).asManaged() == lastValue);
  require(objects.get()->readExisting(lastKey).asManaged().as<RecordPayload>()->read("name").asString() == "value");
  require(lastKey.as<RecordPayload>()->read("id").asInteger() == 1);
}

int main() {
  Heap heap(0);
  run(heap);
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 0 && heap.liveCount() == 0);
}
