#include "ManagedEquality.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static const EnumConstructorDescriptor choiceConstructors[] = {{"Empty", 0}, {"Carry", 1}};
static const EnumConstructorDescriptor otherConstructors[] = {{"Empty", 0}};
static const EnumDescriptor choice{"example.Choice", choiceConstructors, 2};
static const EnumDescriptor other{"example.Other", otherConstructors, 1};

// A handle points at compiler-owned static metadata. Copying or storing it must
// not create a second identity, turn it into a class, or retain an enum instance.
static void descriptorTransport(std::size_t budget) {
  static const EnumDescriptor sameName{"example.Choice", choiceConstructors, 2};
  static const ClassDescriptor classWithSameName{"example.Choice", false, 0, nullptr};
  Heap heap(budget);
  {
    Root<Value> type(heap, Value::enumDescriptor(&choice));
    Root<Value> copy(heap, type.get());
    Value replaced = Value::string("previous");
    replaced = copy.get();
    require(replaced.kind() == ValueKind::EnumDescriptor && replaced.asEnumDescriptor() == &choice,
            "copy or replacement changed enum descriptor identity");
    require(Value::enumDescriptor(nullptr).kind() == ValueKind::Null,
            "null enum descriptor acquired a non-null tag");
    const auto classType = Value::descriptor(&classWithSameName);
    const auto otherType = Value::enumDescriptor(&sameName);
    require(dynamicEquality(heap, type.get(), copy.get(), false, nullptr)
                && !dynamicEquality(heap, type.get(), copy.get(), true, nullptr),
            "copied enum descriptors lost erased equality");
    require(!dynamicEquality(heap, type.get(), otherType, false, nullptr)
                && dynamicEquality(heap, type.get(), otherType, true, nullptr),
            "textual names replaced descriptor identity");
    require(!dynamicEquality(heap, type.get(), classType, false, nullptr)
                && !dynamicEquality(heap, classType, type.get(), false, nullptr)
                && dynamicEquality(heap, type.get(), classType, true, nullptr),
            "enum descriptor merged with a class descriptor");
    require(!dynamicEquality(heap, type.get(), Value{}, false, nullptr)
                && dynamicEquality(heap, Value{}, type.get(), true, nullptr),
            "enum descriptor merged with null");
    bool rejectedClass = false, rejectedManaged = false, rejectedEnum = false;
    try { (void)type.get().asDescriptor(); } catch (const std::bad_variant_access&) { rejectedClass = true; }
    try { (void)type.get().asManaged(); } catch (const std::bad_variant_access&) { rejectedManaged = true; }
    try { (void)classType.asEnumDescriptor(); } catch (const std::bad_variant_access&) { rejectedEnum = true; }
    require(rejectedClass && rejectedManaged && rejectedEnum,
            "descriptor transport accepted the wrong physical category");

    Root<Ref<EnumPayload>> first(heap), second(heap), different(heap);
    heap.allocateInto(first, choice, 1, std::vector<Value>{type.get()});
    heap.allocateInto(second, choice, 1, std::vector<Value>{copy.get()});
    heap.allocateInto(different, choice, 1, std::vector<Value>{otherType});
    require(enumEquality(heap, Value::managed(first.get()), Value::managed(second.get()), nullptr)
                && !enumEquality(heap, Value::managed(first.get()), Value::managed(different.get()), nullptr),
            "enum payload comparison lost descriptor identity");
    require(!enumPayloadEquality(heap, type.get(), classType, nullptr),
            "enum payload comparison merged descriptor categories");
    Root<Ref<ArrayPayload>> array(heap);
    heap.allocateInto(array, ArrayRepresentation::Reference);
    array.get()->append(type.get());
    array.get()->append(Value::managed(first.get()));
    first.set({});
    second.set({});
    different.set({});
    heap.collect();
    require(heap.liveCount() == 2 && array.get()->read(0).asEnumDescriptor() == &choice
                && &array.get()->read(1).asManaged().as<EnumPayload>()->descriptor() == &choice,
            "mixed array tracing lost a descriptor or live enum");
    array.set({});
    heap.collect();
    require(heap.liveCount() == 0 && heap.allocationBytes() == 0
                && type.get().asEnumDescriptor() == &choice && copy.get().asEnumDescriptor() == &choice,
            "enum handles retained an otherwise unreachable instance");
  }
  require(heap.rootCount() == 0, "descriptor transport leaked roots");
}

static void observe(std::size_t budget) {
  Heap heap(budget);
  Root<Ref<EnumPayload>> empty(heap);
  Root<Ref<EnumPayload>> otherEmpty(heap);
  heap.allocateInto(empty, choice, 0, std::vector<Value>{});
  heap.allocateInto(otherEmpty, other, 0, std::vector<Value>{});
  require(&empty.get()->descriptor() == &choice && &otherEmpty.get()->descriptor() == &other,
          "same constructor name merged distinct enum descriptors");
  require(empty.get()->constructorIndex() == 0 && empty.get()->size() == 0,
          "nullary constructor acquired a payload or wrong tag");

  Root<Ref<ArrayPayload>> values(heap);
  heap.allocateInto(values, ArrayRepresentation::Integer);
  values.get()->append(Value::integer(7));
  Root<Ref<EnumPayload>> payload(heap);
  heap.allocateInto(payload, choice, 1, std::vector<Value>{Value::managed(values.get())});
  values.get()->append(Value::managed(payload.get()));
  Root<Value> erased(heap, Value::managed(payload.get()));
  const auto identity = payload.get().allocationId();
  payload.set({});
  values.set({});
  heap.collect();
  require(heap.liveCount() == 4, "erased enum failed to trace its array cycle");
  const auto recovered = erased.get().asManaged().as<EnumPayload>();
  require(recovered.allocationId() == identity && recovered->constructorIndex() == 1,
          "erasure changed enum allocation identity or tag");
  require(recovered->read(0).asManaged().as<ArrayPayload>()->read(0).asInteger() == 7,
          "collection lost the enum payload");
  bool rejected = false;
  try { (void)recovered->read(1); } catch (const std::out_of_range&) { rejected = true; }
  require(rejected, "enum payload read accepted an invalid index");
  erased.set({});
  heap.collect();
  require(heap.liveCount() == 2, "unreachable enum-array cycle leaked");

  const auto retained = empty.get().allocationId();
  rejected = false;
  try { heap.allocateInto(empty, choice, 2, std::vector<Value>{}); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected && empty.get().allocationId() == retained && heap.liveCount() == 2,
          "invalid constructor tag changed the destination or leaked");
  rejected = false;
  try { heap.allocateInto(empty, choice, 1, std::vector<Value>{}); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected && empty.get().allocationId() == retained && heap.liveCount() == 2,
          "invalid constructor arity changed the destination or leaked");
  empty.set({});
  otherEmpty.set({});
  heap.collect();
  require(heap.liveCount() == 0 && heap.allocationBytes() == 0, "enum storage survived its roots");
}

int main() {
  descriptorTransport(0);
  descriptorTransport(1024 * 1024);
  observe(0);
  observe(1024 * 1024);
  std::cout << "CPP_MANAGED_ENUM:PASS\n";
}
