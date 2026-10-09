#include "ManagedValue.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

struct Record {
  Value callback;
  int* destroyed;
  explicit Record(int& destroyed) : destroyed(&destroyed) {}
  ~Record() noexcept { ++*destroyed; }
};
struct Environment {
  Value owner;
  int* destroyed;
  explicit Environment(int& destroyed) : destroyed(&destroyed) {}
  ~Environment() noexcept { ++*destroyed; }
};

namespace hxhx::managed {
template<> struct Trace<Record> {
  static void visit(const Record& value, Visitor& visitor) noexcept { Trace<Value>::visit(value.callback, visitor); }
};
template<> struct Trace<Environment> {
  static void visit(const Environment& value, Visitor& visitor) noexcept { Trace<Value>::visit(value.owner, visitor); }
};
}

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static void aliasAndPlace(std::size_t budget) {
  Heap heap(budget);
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Dynamic);
  array.get()->append(Value::boolean(true));
  const auto identity = array.get().allocationId();
  Root<Value> erased(heap, Value::managed(array.get()));
  require(erased.get().asManaged().hasLayout<ArrayPayload>(), "erased array lost its physical layout");
  require(!erased.get().asManaged().hasLayout<RecordPayload>(), "array acquired record layout");
  require(!ErasedRef{}.hasLayout<ArrayPayload>(), "null acquired array layout");
  Root<Ref<ArrayPayload>> recovered(heap, erased.get().asManaged().as<ArrayPayload>());
  require(recovered.get()->representation() == ArrayRepresentation::Dynamic, "erasure lost the selected array representation");
  require(recovered.get().allocationId() == identity && recovered.get() == array.get(), "erasure copied the array");
  recovered.get()->write(0, Value::boolean(false));
  require(!array.get()->read(0).asBoolean(), "recovered alias did not mutate original storage");
  Root<ArrayPlace> place(heap, {array.get(), 0});
  for (int index = 0; index < 4096; ++index) recovered.get()->append(Value::integer(index));
  array.set({});
  erased.set({});
  recovered.set({});
  heap.collect();
  place.get().write(Value::boolean(true));
  require(place.get().read().asBoolean(), "owner/index place did not survive vector growth and root release");
  require(heap.liveCount() == 1, "array place did not retain exactly its owner");
  place.set({});
  heap.collect();
  require(heap.liveCount() == 0, "array place leaked its owner");
}

static void mixedCycle(std::size_t budget) {
  int recordsDestroyed = 0;
  int environmentsDestroyed = 0;
  Heap heap(budget);
  Root<Value> escaped(heap);
  {
    Root<Ref<ArrayPayload>> array(heap);
    Root<Ref<Record>> record(heap);
    Root<Ref<Environment>> environment(heap);
    heap.allocateInto(array, ArrayRepresentation::Dynamic);
    heap.allocateInto(record, recordsDestroyed);
    heap.allocateInto(environment, environmentsDestroyed);
    array.get()->append(Value::managed(record.get()));
    record.get()->callback = Value::managed(environment.get());
    environment.get()->owner = Value::managed(array.get());
    escaped.set(Value::managed(environment.get()));
  }
  heap.collect();
  require(heap.liveCount() == 3 && recordsDestroyed == 0 && environmentsDestroyed == 0, "erased mixed cycle lost an edge");
  const auto owner = escaped.get().asManaged().as<Environment>()->owner.asManaged().as<ArrayPayload>();
  require(escaped.get().asManaged().hasLayout<Environment>(), "collection changed the rooted layout");
  require(!escaped.get().asManaged().hasLayout<Record>(), "physical guard confused graph members");
  require(owner->read(0).asManaged().as<Record>()->callback.asManaged() == escaped.get().asManaged(), "cycle identity changed");
  bool rejected = false;
  try { static_cast<void>(escaped.get().asManaged().as<Record>()); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected, "wrong physical payload layout was accepted");
  escaped.set({});
  heap.collect();
  heap.collect();
  require(heap.liveCount() == 0 && recordsDestroyed == 1 && environmentsDestroyed == 1, "mixed cycle was not destroyed exactly once");
}

static void localResultSlot() {
  Heap heap(0);
  {
    LocalSlot slot(heap);
    bool rejected = false;
    try { static_cast<void>(slot.get()); }
    catch (const std::logic_error&) { rejected = true; }
    require(rejected, "unassigned local slot silently produced a value");
    slot.set(Value());
    require(slot.get().kind() == ValueKind::Null, "assigned null became an unassigned slot");
    Root<Ref<ArrayPayload>> array(heap);
    heap.allocateInto(array, ArrayRepresentation::Dynamic);
    array.get()->append(Value::integer(43));
    slot.set(Value::managed(array.get()));
    array.set({});
    heap.collect();
    require(slot.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 43, "local slot did not root its assigned graph");
    slot.set(Value::integer(17));
    heap.collect();
    require(slot.get().asInteger() == 17 && heap.liveCount() == 0, "slot replacement retained the old graph");
  }
  heap.collect();
  require(heap.liveCount() == 0, "local slot failed to leave its root scope");
}

// Layout identity is separate from spelling, and instance fields are strong graph edges.
static void instanceGraph() {
  static const ClassDescriptor first{"SameSpelling", true, 2, nullptr};
  static const ClassDescriptor foreign{"SameSpelling", true, 2, nullptr};
  static const InstanceDescriptor application{first};
  Heap heap(0);
  Root<Ref<InstancePayload>> instance(heap);
  heap.allocateInto(instance, application, std::vector<Value>{Value::integer(0), Value{}});
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Dynamic);
  instance.get()->write(first, 1, Value::managed(array.get()));
  array.get()->append(Value::managed(instance.get()));
  array.set({});
  heap.collect();
  require(heap.liveCount() == 2, "instance did not retain its array field");
  require(instance.get()->read(first, 1).asManaged().as<ArrayPayload>()->read(0).asManaged()
      == Value::managed(instance.get()).asManaged(), "instance cycle lost identity");
  bool rejected = false;
  try { static_cast<void>(instance.get()->read(foreign, 0)); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected, "same-spelled foreign descriptor read the instance");
  rejected = false;
  try { instance.get()->write(foreign, 0, Value::integer(99)); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected && instance.get()->read(first, 0).asInteger() == 0, "foreign write changed storage");
  rejected = false;
  try { static_cast<void>(instance.get()->read(first, 2)); }
  catch (const std::out_of_range&) { rejected = true; }
  require(rejected, "out-of-layout field read succeeded");
  instance.set({});
  heap.collect();
  require(heap.liveCount() == 0, "unreachable instance cycle leaked");
}

// Identically empty generic fields cannot identify the compiled application.
// Its explicit descriptor survives collection without splitting public identity.
static void appliedInstances() {
  static const ClassDescriptor owner{"Generic", true, 1, nullptr};
  static const InstanceDescriptor integers{owner}, strings{owner};
  Heap heap(0);
  Root<Ref<InstancePayload>> first(heap), second(heap), repeated(heap);
  heap.allocateInto(first, integers, std::vector<Value>{Value{}});
  heap.allocateInto(second, strings, std::vector<Value>{Value{}});
  heap.allocateInto(repeated, integers, std::vector<Value>{Value{}});
  heap.collect();
  require(&first.get()->descriptor() == &owner && &second.get()->descriptor() == &owner,
          "applied instances split public class identity");
  require(&first.get()->instanceDescriptor() != &second.get()->instanceDescriptor()
          && &first.get()->instanceDescriptor() == &repeated.get()->instanceDescriptor(),
          "applied instance identity was inferred from fields or allocation address");
  first.get()->write(owner, 0, Value::integer(3));
  second.get()->write(owner, 0, Value::string("text"));
  require(first.get()->read(owner, 0).asInteger() == 3
          && second.get()->read(owner, 0).asString() == "text",
          "common class owner conflated applied instance fields");
  first.set({}); second.set({}); repeated.set({});
  heap.collect();
  require(heap.liveCount() == 0, "instance descriptors retained released objects");
}

static void emptyArrayRepresentations() {
  Heap heap(0);
  Root<Ref<ArrayPayload>> boolean(heap), integer(heap);
  heap.allocateInto(boolean, ArrayRepresentation::Boolean);
  heap.allocateInto(integer, ArrayRepresentation::Integer);
  Root<Value> erased(heap, Value::managed(boolean.get()));
  boolean.set({});
  heap.collect();
  const auto recovered = erased.get().asManaged().as<ArrayPayload>();
  require(recovered->size() == 0 && integer.get()->size() == 0, "empty array test gained an element");
  require(recovered->representation() == ArrayRepresentation::Boolean
          && integer.get()->representation() == ArrayRepresentation::Integer,
          "empty arrays lost their distinct selected representations");
}

// Ancestor access addresses a prefix of the same allocation, never another object.
static void inheritedInstance() {
  static const ClassDescriptor base{"Base", true, 1, nullptr};
  static const ClassDescriptor child{"Child", true, 2, &base};
  static const ClassDescriptor leaf{"Leaf", true, 3, &child};
  static const ClassDescriptor foreign{"Base", true, 1, nullptr};
  static const InstanceDescriptor application{leaf};
  Heap heap(0);
  Root<Ref<InstancePayload>> instance(heap);
  heap.allocateInto(instance, application, std::vector<Value>{Value::integer(7), Value::string("child"), Value{}});
  instance.get()->write(base, 0, Value::integer(11));
  require(instance.get()->read(leaf, 0).asInteger() == 11, "upcast lost inherited alias");
  require(&instance.get()->descriptor() == &leaf && instance.get()->hasOwner(base)
      && instance.get()->hasOwner(child) && !instance.get()->hasOwner(foreign), "allocated class identity changed");
  bool rejected = false;
  try { instance.get()->write(base, 1, Value::integer(99)); }
  catch (const std::out_of_range&) { rejected = true; }
  require(rejected && instance.get()->read(child, 1).asString() == "child", "base access overwrote child storage");
  rejected = false;
  try { static_cast<void>(instance.get()->read(foreign, 0)); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected, "foreign ancestor spelling authorized storage access");
  instance.set({});
  heap.collect();
  require(heap.liveCount() == 0, "inherited instance leaked");
}

// Field order is compiler-selected metadata; values remain live mutable storage.
static void recordFieldOrder() {
  Heap heap(0);
  Root<Ref<RecordPayload>> record(heap);
  heap.allocateInto(record);
  record.get()->define("first", Value::integer(1));
  record.get()->define("later", Value::integer(2));
  bool rejected = false;
  try { static_cast<void>(record.get()->fieldNames()); }
  catch (const std::logic_error&) { rejected = true; }
  require(rejected, "record silently invented field order");
  for (const auto& invalid : std::vector<std::vector<std::string>>{{"first"}, {"first", "first"}, {"first", "foreign"}}) {
    rejected = false;
    try { record.get()->setFieldOrder(invalid); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected, "invalid record field order was accepted");
  }
  record.get()->setFieldOrder({"later", "first"});
  auto names = record.get()->fieldNames();
  names[0] = "foreign";
  record.get()->write("later", Value::integer(3));
  heap.collect();
  require(record.get()->fieldNames() == std::vector<std::string>{"later", "first"}, "field names were borrowed or sorted again");
  require(record.get()->read("later").asInteger() == 3, "field order froze its values");
  record.set({});
  heap.collect();
  require(heap.liveCount() == 0, "field order retained its record");
}

int main() {
  recordFieldOrder();
  appliedInstances();
  inheritedInstance();
  emptyArrayRepresentations();
  instanceGraph();
  localResultSlot();
  aliasAndPlace(65536);
  aliasAndPlace(0);
  mixedCycle(65536);
  mixedCycle(0);
  require(Value{}.kind() == ValueKind::Null, "default value is not null");
  require(Value::managed(Ref<ArrayPayload>{}).kind() == ValueKind::Null, "null reference changed category");
  require(Value::integer(7).asInteger() == 7 && Value::floating(2.5).asFloat() == 2.5, "primitive value changed");
  require(Value::string("stored").asString() == "stored", "string transport changed");
  bool rejected = false;
  try { static_cast<void>(Value::integer(1).asBoolean()); }
  catch (const std::bad_variant_access&) { rejected = true; }
  require(rejected, "storage access performed an implicit semantic conversion");
  static const ClassDescriptor descriptor{"Probe", false, 0, nullptr};
  static const InstanceDescriptor application{descriptor};
  Heap heap;
  Root<Value> type(heap, Value::descriptor(&descriptor));
  heap.collect();
  require(type.get().kind() == ValueKind::Descriptor && type.get().asDescriptor() == &descriptor && heap.liveCount() == 0,
          "descriptor acquired instance ownership");
  {
    Root<Ref<InstancePayload>> instance(heap);
    bool refused = false;
    try { heap.allocateInto(instance, application, std::vector<Value>{}); }
    catch (const std::invalid_argument&) { refused = true; }
    require(refused && !instance.get() && heap.liveCount() == 0,
            "identity-only descriptor acquired an instance layout");
  }
  std::cout << "CPP_MANAGED_VALUE:PASS\n";
}
