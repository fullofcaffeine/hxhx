#include HXHX_LOCAL_PROGRAM
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
using Callback = CallablePayload<void(Root<Value>&)>;
enum class Failure { None, Receiver, Value };
static Failure failure = Failure::None;
static std::string effects;
static bool nullReceiver = false;

static void require(bool condition) {
  if (!condition) throw std::runtime_error("record assignment contract changed");
}

static void receive(Heap& heap, ErasedRef environment, Root<Value>& result) {
  effects += "R";
  heap.collect();
  if (failure == Failure::Receiver) throw std::runtime_error("receiver-failure");
  result.set(nullReceiver ? Value() : Value::managed(environment));
}

static void booleanValue(Heap& heap, ErasedRef, Root<Value>& result) {
  effects += "V";
  heap.collect();
  if (failure == Failure::Value) throw std::runtime_error("value-failure");
  result.set(Value::boolean(true));
}

static void textValue(Heap& heap, ErasedRef, Root<Value>& result) {
  effects += "V";
  heap.collect();
  result.set(Value::string("after"));
}

static void objectValue(Heap& heap, ErasedRef, Root<Value>& result) {
  effects += "V";
  Root<Ref<RecordPayload>> value(heap);
  heap.allocateInto(value);
  value.get()->define("name", Value::string("payload"));
  heap.collect();
  result.set(Value::managed(value.get()));
}

// No outside root keeps this receiver alive during the allocating RHS callback.
static void freshReceiver(Heap& heap, ErasedRef, Root<Value>& result) {
  effects += "R";
  Root<Ref<RecordPayload>> value(heap);
  heap.allocateInto(value);
  value.get()->define("item", Value());
  result.set(Value::managed(value.get()));
}

static void booleanWrites(Heap& heap) {
  Root<Ref<RecordPayload>> record(heap);
  heap.allocateInto(record);
  record.get()->define("item", Value::boolean(false));
  Root<Ref<Callback>> receiver(heap), value(heap);
  heap.allocateInto(receiver, &receive, ErasedRef(record.get()));
  heap.allocateInto(value, &booleanValue, ErasedRef{});
  for (bool discard : {false, true}) {
    for (Failure mode : {Failure::None, Failure::Receiver, Failure::Value}) {
      failure = mode;
      effects.clear();
      record.get()->write("item", Value::boolean(false));
      Root<Value> result(heap, Value::string("unchanged"));
      bool threw = false;
      try {
        if (discard) generated_discard(heap, Value::managed(receiver.get()), Value::managed(value.get()));
        else generated_assign(heap, result, Value::managed(receiver.get()), Value::managed(value.get()));
      } catch (const std::runtime_error& error) {
        threw = true;
        require(std::string(error.what()) == (mode == Failure::Receiver ? "receiver-failure" : "value-failure"));
      }
      require(threw == (mode != Failure::None));
      require(effects == (mode == Failure::Receiver ? "R" : "RV"));
      const auto stored = record.get()->read("item");
      require(stored.kind() == ValueKind::Boolean && stored.asBoolean() == (mode == Failure::None));
      if (discard || threw) require(result.get().asString() == "unchanged");
      else require(result.get().kind() == ValueKind::Boolean && result.get().asBoolean());
    }
  }
  failure = Failure::None;
  nullReceiver = true;
  effects.clear();
  Root<Value> result(heap, Value::string("unchanged"));
  bool rejected = false;
  try { generated_assign(heap, result, Value::managed(receiver.get()), Value::managed(value.get())); }
  catch (const std::invalid_argument& error) {
    rejected = std::string(error.what()) == "field assignment has no record";
  }
  require(rejected && effects == "RV" && result.get().asString() == "unchanged");
  nullReceiver = false;
  generated_local(heap, result, true);
  require(result.get().kind() == ValueKind::Boolean && result.get().asBoolean());
  generated_local(heap, result, false);
  require(result.get().kind() == ValueKind::Boolean && !result.get().asBoolean());
}

static void textAndObjects(Heap& heap) {
  Root<Ref<RecordPayload>> record(heap), outer(heap);
  heap.allocateInto(record);
  record.get()->define("item", Value::string("before"));
  heap.allocateInto(outer);
  outer.get()->define("inner", Value::managed(record.get()));
  Root<Ref<Callback>> receiver(heap), value(heap), nestedReceiver(heap), object(heap), fresh(heap);
  heap.allocateInto(receiver, &receive, ErasedRef(record.get()));
  heap.allocateInto(nestedReceiver, &receive, ErasedRef(outer.get()));
  heap.allocateInto(value, &textValue, ErasedRef{});
  heap.allocateInto(object, &objectValue, ErasedRef{});
  heap.allocateInto(fresh, &freshReceiver, ErasedRef{});
  Root<Value> result(heap);
  effects.clear();
  generated_text(heap, result, Value::managed(receiver.get()), Value::managed(value.get()));
  require(effects == "RV" && result.get().asString() == "after" && record.get()->read("item").asString() == "after");
  record.get()->write("item", Value::string("before"));
  effects.clear();
  generated_nested(heap, result, Value::managed(nestedReceiver.get()), Value::managed(value.get()));
  require(effects == "RV" && result.get().asString() == "after" && record.get()->read("item").asString() == "after");
  record.get()->write("item", Value());
  effects.clear();
  generated_object(heap, result, Value::managed(receiver.get()), Value::managed(object.get()));
  heap.collect();
  require(effects == "RV" && result.get().asManaged() == record.get()->read("item").asManaged());
  require(result.get().asManaged().as<RecordPayload>()->read("name").asString() == "payload");
  effects.clear();
  generated_object(heap, result, Value::managed(fresh.get()), Value::managed(object.get()));
  heap.collect();
  require(effects == "RV" && result.get().asManaged().as<RecordPayload>()->read("name").asString() == "payload");
}

static void optionalWrite(Heap& heap) {
  Root<Ref<RecordPayload>> record(heap);
  heap.allocateInto(record);
  Root<Ref<Callback>> receiver(heap), value(heap);
  heap.allocateInto(receiver, &receive, ErasedRef(record.get()));
  heap.allocateInto(value, &booleanValue, ErasedRef{});
  require(!record.get()->contains("item"));
  Root<Value> result(heap);
  for (int attempt = 0; attempt < 2; ++attempt) {
    effects.clear();
    generated_optional(heap, result, Value::managed(receiver.get()), Value::managed(value.get()));
    require(effects == "RV" && record.get()->contains("item") && record.get()->read("item").asBoolean());
  }
}

int main() {
  Heap heap(0);
  booleanWrites(heap);
  textAndObjects(heap);
  optionalWrite(heap);
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 0 && heap.liveCount() == 0);
}
