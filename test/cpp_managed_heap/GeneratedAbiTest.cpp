#include "ClosureAbi.generated.hpp"
#include <iostream>
#include <stdexcept>
#include <type_traits>
#include "IterationObserver.hpp"
#include "RecordReadObserver.hpp"

using namespace hxhx::managed;

// These independently specified native signatures must agree with Haxe output.
static_assert(std::is_same_v<Scalar::Entry, void (*)(Heap&, ErasedRef, Root<Value>&, Value)>);
static_assert(std::is_same_v<Managed::Entry, void (*)(Heap&, ErasedRef, Root<Value>&, Value, Value, Value)>);
static_assert(std::is_same_v<Empty::Entry, void (*)(Heap&, ErasedRef)>);
static_assert(std::is_same_v<Receiver::Entry, void (*)(Heap&, ErasedRef, Root<Value>&)>);
static_assert(std::is_same_v<decltype(&generatedCounterCreator), void (*)(Heap&, Root<Value>&)>);
static_assert(std::is_same_v<decltype(&generatedRootParameterCreator), void (*)(Heap&, Root<Value>&, Value, Value)>);
static_assert(std::is_same_v<decltype(&generatedRootBranch), std::int32_t (*)(Heap&, bool, std::int32_t)>);
static_assert(std::is_same_v<decltype(&generatedRootVoid), void (*)(Heap&)>);
static_assert(std::is_same_v<decltype(&generatedStaticMainentry), std::int32_t (*)(Heap&)>);
static_assert(std::is_same_v<decltype(&generatedStaticMainrelay), void (*)(Heap&, Root<Value>&, Value)>);

struct ReceiverRecord {
  std::int32_t base;
  explicit ReceiverRecord(std::int32_t base) : base(base) {}
};
namespace hxhx::managed {
template<> struct Trace<ReceiverRecord> {
  static void visit(const ReceiverRecord&, Visitor&) noexcept {}
};
}

static void scalarEntry(Heap& heap, ErasedRef environment, Root<Value>& output, Value value) {
  heap.collect();
  Root<Value> captured(heap);
  readCell0(environment.as<ScalarEnvironment>()->captured.cell0, captured);
  output.set(Value::integer(captured.get().asInteger() + value.asInteger()));
}

static void managedEntry(Heap& heap, ErasedRef environment, Root<Value>& result, Value value, Value other, Value choose) {
  if (other.asInteger() != 7) throw std::runtime_error("argument order changed");
  generatedManagedBody(heap, environment, result, std::move(value), std::move(other), choose);
}

static void throwingEntry(Heap& heap, ErasedRef, Root<Value>& result, Value value, Value other, Value choose) {
  managedEntry(heap, {}, result, std::move(value), std::move(other), choose);
  throw std::runtime_error("body failure after result publication");
}

static void emptyEntry(Heap& heap, ErasedRef) { heap.collect(); }

static void receiverEntry(Heap& heap, ErasedRef environment, Root<Value>& output) {
  heap.collect();
  output.set(Value::integer(environment.as<ReceiverEnvironment>()->captured.receiver->read().asManaged().as<ReceiverRecord>()->base));
}

static void require(bool condition) {
  if (!condition) throw std::runtime_error("generated ABI contract mismatch");
}

static void observeParameterRoots(Heap& heap, Value spare) {
  heap.collect();
  // This borrowed edge adds no root: ingress must have retained the later argument.
  require(spare.asManaged().as<ArrayPayload>()->read(0).asInteger() == 32);
}

static void parameterIngress(Heap& heap) {
  Root<Value> escaped(heap);
  Root<Value> secondEscaped(heap);
  Root<Value> returned(heap);
  for (int iteration = 0; iteration < 2; ++iteration) {
    Root<Ref<ArrayPayload>> first(heap);
    Root<Ref<ArrayPayload>> spare(heap);
    heap.allocateInto(first, ArrayRepresentation::Integer);
    first.get()->append(Value::integer(31 + iteration * 10));
    heap.allocateInto(spare, ArrayRepresentation::Integer);
    spare.get()->append(Value::integer(32));
    const auto firstIdentity = first.get().allocationId();
    const auto firstValue = Value::managed(first.get());
    const auto spareValue = Value::managed(spare.get());
    first.set({});
    spare.set({});
    // No collection occurs between borrowing the input values and entering.
    // The first promoted-cell allocation must see roots for BOTH arguments.
    auto& destination = iteration == 0 ? escaped : secondEscaped;
    generatedPromoterEntry(heap, {}, destination, firstValue, spareValue);
    heap.collect();
    generatedForward(heap, [&] { return destination.get().asManaged().as<Forward>(); }, returned);
    require(returned.get().asManaged().allocationId() == firstIdentity);
    require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 31 + iteration * 10);
  }
  generatedForward(heap, [&] { return escaped.get().asManaged().as<Forward>(); }, returned);
  require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 31);
  generatedForward(heap, [&] { return secondEscaped.get().asManaged().as<Forward>(); }, returned);
  require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 41);
  escaped.set({});
  secondEscaped.set({});
  returned.set({});
  heap.collect();
  require(heap.liveCount() == 0);
}

static void localDeclarationEscape(Heap& heap) {
  Root<Value> escaped(heap);
  Root<Value> returned(heap);
  std::size_t identity;
  {
    Root<Ref<ArrayPayload>> input(heap);
    heap.allocateInto(input, ArrayRepresentation::Integer);
    input.get()->append(Value::integer(53));
    identity = input.get().allocationId();
    const auto borrowed = Value::managed(input.get());
    input.set({});
    generatedLocalCreator(heap, {}, escaped, borrowed);
  }
  heap.collect();
  {
    using Signature = void(Root<Value>&);
    ActiveCall<Signature> call(heap, escaped.get().asManaged().as<CallablePayload<Signature>>());
    call.invoke(returned);
  }
  require(returned.get().asManaged().allocationId() == identity);
  require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 53);
  escaped.set({});
  returned.set({});
  heap.collect();
  require(heap.liveCount() == 0);
}

static void rootParameterIngress(Heap& heap) {
  {
    Root<Ref<ArrayPayload>> input(heap), spare(heap);
    heap.allocateInto(input, ArrayRepresentation::Integer);
    input.get()->append(Value::integer(83));
    heap.allocateInto(spare, ArrayRepresentation::Integer);
    spare.get()->append(Value::integer(32));
    const auto identity = input.get().allocationId();
    const auto value = Value::managed(input.get());
    const auto other = Value::managed(spare.get());
    input.set({});
    spare.set({});
    Root<Value> escaped(heap), returned(heap);
    generatedRootParameterCreator(heap, escaped, value, other);
    heap.collect();
    ActiveCall<void(Root<Value>&, Value)> selected(heap, escaped.get().asManaged().as<CallablePayload<void(Root<Value>&, Value)>>());
    selected.invoke(returned, Value::boolean(true));
    require(returned.get().asManaged().allocationId() == identity);
    require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 83);
    heap.collect();
    selected.invoke(returned, Value::boolean(false));
    require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 32);
  }
  heap.collect();
  require(heap.liveCount() == 0);
}

static void sourceRecursiveDeclaration(Heap& heap) {
  Root<Value> escaped(heap);
  Root<Value> returned(heap);
  generatedRecursiveCreator(heap, {}, escaped);
  heap.collect();
  {
    using Signature = void(Root<Value>&);
    ActiveCall<Signature> call(heap, escaped.get().asManaged().as<CallablePayload<Signature>>());
    call.invoke(returned);
  }
  require(returned.get().asManaged().allocationId() == escaped.get().asManaged().allocationId());
  escaped.set({});
  returned.set({});
  heap.collect();
  require(heap.liveCount() == 0);
}

static void namedEntry(Heap& heap, ErasedRef environment, Root<Value>& output) {
  Root<Value> self(heap);
  readCell1(environment.as<NamedEnvironment>()->captured.cell0, self);
  heap.collect();
  require(static_cast<bool>(self.get().asManaged().as<Named>()));
  output.set(Value::integer(9));
}

static void generatedCellOperations(Heap& heap) {
  Root<Value> result(heap, Value::integer(41));
  {
    Root<Ref<CellPayload>> scalar(heap);
    allocateCell0(heap, scalar);
    writeCell0(heap, [&] { return scalar.get(); }, [] { return Value::integer(17); }, result);
    require(result.get().asInteger() == 17);
    result.set(Value::integer(41));
    const auto roots = heap.rootCount();
    bool failed = false;
    try {
      writeCell0(heap, [&] { return scalar.get(); }, [&]() -> Value {
        heap.collect();
        throw std::runtime_error("failed initializer");
      }, result);
    } catch (const std::runtime_error&) { failed = true; }
    require(failed && result.get().asInteger() == 41 && heap.rootCount() == roots);
    readCell0(scalar.get(), result);
    require(result.get().asInteger() == 17);
  }
  {
    Root<Ref<CellPayload>> self(heap);
    allocateCell1(heap, self);
    Root<Ref<Named>> callable(heap);
    constructNamed(heap, callable, &namedEntry, self.get());
    writeCell1(heap, [&] { return self.get(); }, [&] { return Value::managed(callable.get()); }, result);
    const auto identity = callable.get().allocationId();
    bool failed = false;
    try {
      writeCell1(heap, [&] { return self.get(); }, [] { return Value(); }, result);
    } catch (const std::logic_error&) { failed = true; }
    require(failed && result.get().asManaged().allocationId() == identity);
    Root<Value> output(heap);
    generatedNamed(heap, [&] { return callable.get(); }, output);
    require(output.get().asInteger() == 9);
    callable.set({});
    self.set({});
    result.set({});
  }
  heap.collect();
  require(heap.liveCount() == 0);
  {
    Root<Ref<CellPayload>> erased(heap);
    allocateCell2(heap, erased);
    std::string order;
    writeCell2(heap, [&] {
      order += "place;";
      return erased.get();
    }, [&] {
      order += "value;";
      erased.set({});
      heap.collect();
      Root<Ref<ArrayPayload>> array(heap);
      heap.allocateInto(array, ArrayRepresentation::Integer);
      array.get()->append(Value::integer(29));
      return Value::managed(array.get());
    }, result);
    require(order == "place;value;");
    heap.collect();
    // Only the assignment result retains the array. The selected cell must now die.
    require(heap.liveCount() == 1);
    require(result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 29);
  }
  result.set({});
  heap.collect();
  require(heap.liveCount() == 0);
}

static void mutableCapture(Heap& heap) {
  Root<Value> escaped(heap);
  Root<Value> copy(heap);
  Root<Value> returned(heap);
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(Value::integer(11));
  generatedMutation0(heap, {}, escaped, Value::managed(array.get()));
  copy.set(escaped.get());
  for (int value : {22, 33}) {
    heap.allocateInto(array, ArrayRepresentation::Integer);
    array.get()->append(Value::integer(value));
    const auto identity = array.get().allocationId();
    using Signature = void(Root<Value>&, Value, Value);
    ActiveCall<Signature> call(heap, copy.get().asManaged().as<CallablePayload<Signature>>());
    call.invoke(returned, Value::managed(array.get()), Value::boolean(false));
    require(returned.get().asManaged().allocationId() == identity);
    require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == value);
  }
  {
    using Signature = void(Root<Value>&, Value, Value);
    ActiveCall<Signature> call(heap, escaped.get().asManaged().as<CallablePayload<Signature>>());
    call.invoke(returned, Value(), Value::boolean(true));
  }
  const auto replacement = returned.get().asManaged().allocationId();
  escaped.set({});
  copy.set({});
  array.set({});
  heap.collect();
  {
    using Signature = void(Root<Value>&);
    ActiveCall<Signature> call(heap, returned.get().asManaged().as<CallablePayload<Signature>>());
    call.invoke(returned);
  }
  require(returned.get().asManaged().allocationId() == replacement);
  returned.set({});
  heap.collect();
  require(heap.liveCount() == 0);
}

static void selectedSourceEntry(Heap& heap, ErasedRef, Root<Value>& result, Value first, Value second) {
  heap.collect();
  require(first.kind() == ValueKind::Managed);
  result.set(second);
}

static void replacedSourceEntry(Heap&, ErasedRef, Root<Value>&, Value, Value) {
  throw std::runtime_error("argument effects changed the already selected source callee");
}

static void authoredCallOrder(Heap& heap) {
  using Signature = void(Root<Value>&, Value, Value);
  using Function = CallablePayload<Signature>;
  Root<Ref<Function>> first(heap);
  Root<Ref<Function>> replacement(heap);
  Root<Ref<ArrayPayload>> array(heap);
  Root<Value> escaped(heap);
  Root<Value> returned(heap);
  heap.allocateInto(first, &selectedSourceEntry, ErasedRef{});
  heap.allocateInto(replacement, &replacedSourceEntry, ErasedRef{});
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(Value::integer(67));
  const auto identity = array.get().allocationId();
  const auto selectedValue = Value::managed(first.get());
  const auto replacementValue = Value::managed(replacement.get());
  const auto input = Value::managed(array.get());
  first.set({});
  replacement.set({});
  array.set({});
  generatedSourceCall(heap, {}, escaped, selectedValue, replacementValue, input);
  heap.collect();
  {
    using Child = void(Root<Value>&);
    ActiveCall<Child> call(heap, escaped.get().asManaged().as<CallablePayload<Child>>());
    call.invoke(returned);
  }
  require(returned.get().asManaged().allocationId() == identity);
  require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 67);
  escaped.set({});
  returned.set({});
  heap.collect();
  require(heap.liveCount() == 0);
}

static void sourceLeafEntry(Heap& heap, ErasedRef, Root<Value>& output, Value value) {
  heap.collect();
  output.set(Value::boolean(!value.asBoolean()));
}

static int sourceVoidCalls = 0;
static void sourceVoidEntry(Heap& heap, ErasedRef) {
  heap.collect();
  ++sourceVoidCalls;
}

static int sourceArgumentEffects = 0;
static void sourceEffectEntry(Heap& heap, ErasedRef, Root<Value>& output) {
  heap.collect();
  ++sourceArgumentEffects;
  output.set(Value::integer(79));
}

static void sourceEchoEntry(Heap& heap, ErasedRef, Root<Value>& output, Value value) {
  heap.collect();
  output.set(value);
}

static void authoredCallResults(Heap& heap) {
  {
    Root<Ref<CallablePayload<void(Root<Value>&, Value)>>> leaf(heap);
    Root<Ref<CallablePayload<void()>>> ignored(heap);
    Root<Value> result(heap);
    heap.allocateInto(leaf, &sourceLeafEntry, ErasedRef{});
    heap.allocateInto(ignored, &sourceVoidEntry, ErasedRef{});
    generatedSourceLeaf0(heap, {}, result, Value::managed(leaf.get()), Value::boolean(false));
    require(result.get().asBoolean());
    generatedSourceLeaf0(heap, {}, result, Value::managed(leaf.get()), Value::boolean(true));
    require(!result.get().asBoolean());
    generatedSourceLeaf1(heap, {}, Value::managed(ignored.get()));
    require(sourceVoidCalls == 1);
    Root<Ref<CallablePayload<void(Root<Value>&)>>> effect(heap);
    Root<Ref<CallablePayload<void(Root<Value>&, Value)>>> echo(heap);
    heap.allocateInto(effect, &sourceEffectEntry, ErasedRef{});
    heap.allocateInto(echo, &sourceEchoEntry, ErasedRef{});
    result.set(Value::integer(93));
    bool rejected = false;
    try { generatedSourceLeaf2(heap, {}, result, Value(), Value::managed(effect.get())); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected && sourceArgumentEffects == 1 && result.get().asInteger() == 93);
    generatedSourceLeaf2(heap, {}, result, Value::managed(echo.get()), Value::managed(effect.get()));
    require(sourceArgumentEffects == 2 && result.get().asInteger() == 79);
  }
  heap.collect();
  require(heap.liveCount() == 0);
}

static void directReturnEntry(Heap& heap, ErasedRef, Root<Value>& output, Value value) {
  heap.collect();
  output.set(value);
}

static void authoredDirectReturn(Heap& heap) {
  {
    Root<Ref<CallablePayload<void(Root<Value>&, Value)>>> callback(heap);
    heap.allocateInto(callback, &directReturnEntry, ErasedRef{});
    Root<Value> result(heap);
    for (std::int32_t value : {INT32_MIN, -1, 0, 1, INT32_MAX}) {
      generatedDirectReturn(heap, {}, result, Value::managed(callback.get()), Value::integer(value));
      require(result.get().asInteger() == value);
    }
    Root<Ref<CallablePayload<void(Root<Value>&, Value)>>> stringCallback(heap);
    heap.allocateInto(stringCallback, &sourceEchoEntry, ErasedRef{});
    generatedStringReturn(heap, {}, result, Value::managed(stringCallback.get()), Value());
    require(result.get().kind() == ValueKind::Null);
    generatedStringReturn(heap, {}, result, Value::managed(stringCallback.get()), Value::string(""));
    require(result.get().kind() == ValueKind::String && result.get().asString().empty());
    const std::string text(1024, 'x');
    generatedStringReturn(heap, {}, result, Value::managed(stringCallback.get()), Value::string(text));
    heap.collect();
    require(result.get().asString() == text);
  }
  heap.collect();
  require(heap.liveCount() == 0);
}

static int integerEffectCount = 0;
static int conditionChecks = 0;
static void conditionEffect(Heap& heap, ErasedRef, Root<Value>& output) {
  heap.collect();
  output.set(Value::boolean(++conditionChecks < 3));
}
static void throwingCondition(Heap& heap, ErasedRef, Root<Value>&) {
  heap.collect();
  throw std::runtime_error("condition failure");
}
static int staticVoidEffectCount = 0;
static void staticVoidEffect(Heap& heap, ErasedRef) {
  ++staticVoidEffectCount;
  heap.collect();
}
static void integerEffect(Heap& heap, ErasedRef, Root<Value>& output) {
  heap.collect();
  output.set(Value::integer(++integerEffectCount == 1 ? 3 : 8));
}

static int aggregateEffects = 0;
static int aggregateFailAt = 0;
static void aggregateEffect(Heap& heap, ErasedRef, Root<Value>& output) {
  heap.collect();
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(Value::integer(++aggregateEffects));
  if (aggregateEffects == aggregateFailAt) throw std::runtime_error("aggregate child failure");
  output.set(Value::managed(array.get()));
}

static void aggregateOrder(Heap& heap, ErasedRef, Root<Value>& output) {
  heap.collect();
  output.set(Value::integer(++aggregateEffects));
}

// All constructions below are authored Haxe. These reads independently observe
// the resulting graph after collecting allocation, creator exit, and copying.
static void authoredAggregates(Heap& heap) {
  {
    Root<Value> result(heap);
    generatedAggregaterecords(heap, result);
    heap.collect();
    auto records = result.get().asManaged().as<ArrayPayload>();
    require(records->size() == 2);
    require(records->read(0).asManaged().as<RecordPayload>()->read("name").asString() == "first");
    require(records->read(1).asManaged().as<RecordPayload>()->read("name").asString() == "hit");
    generatedAggregateempty(heap, result);
    require(result.get().asManaged().as<ArrayPayload>()->size() == 0);
    generatedAggregatestrings(heap, result);
    heap.collect();
    auto strings = result.get().asManaged().as<ArrayPayload>();
    require(strings->size() == 3 && strings->read(0).asString().empty());
    require(strings->read(1).asString() == std::string("\303\251", 2));
    require(strings->read(2).asString() == std::string("a\0b9", 4));

    Root<Ref<CallablePayload<void(Root<Value>&)>>> ordered(heap);
    heap.allocateInto(ordered, &aggregateOrder, ErasedRef{});
    aggregateEffects = 0;
    generatedAggregateordered(heap, result, Value::managed(ordered.get()));
    heap.collect();
    auto record = result.get().asManaged().as<RecordPayload>();
    // Type fields are sorted a,z; evaluation must retain the authored z,a order.
    require(aggregateEffects == 2 && record->read("z").asInteger() == 1 && record->read("a").asInteger() == 2);
    require(!record->contains("optional"));
    record->define("optional", Value());
    require(record->contains("optional") && record->read("optional").kind() == ValueKind::Null);

    Root<Ref<CallablePayload<void(Root<Value>&)>>> effect(heap);
    heap.allocateInto(effect, &aggregateEffect, ErasedRef{});
    aggregateEffects = 0;
    generatedAggregatemixed(heap, result, Value::managed(effect.get()));
    require(aggregateEffects == 2);
    Root<Value> copied(heap, result.get());
    result.set({});
    heap.collect();
    record = copied.get().asManaged().as<RecordPayload>();
    const auto values = record->read("values").asManaged();
    const auto valuesIdentity = values.allocationId();
    auto array = values.as<ArrayPayload>();
    require(array->read(0).asManaged().as<RecordPayload>()->read("tag").asString() == "first");
    require(array->read(1).asManaged().as<RecordPayload>()->read("tag").asString() == "second");
    for (std::size_t index = 0; index < 2; ++index)
      require(array->read(index).asManaged().as<RecordPayload>()->read("items").asManaged().as<ArrayPayload>()->read(0).asInteger()
        == static_cast<std::int32_t>(index + 1));
    {
      ActiveCall<void(Root<Value>&)> call(heap, record->read("callback").asManaged().as<CallablePayload<void(Root<Value>&)>>());
      copied.set({});
      heap.collect();
      call.invoke(result);
    }
    heap.collect();
    require(result.get().asManaged().allocationId() == valuesIdentity);
    require(result.get().asManaged().as<ArrayPayload>()->read(1).asManaged().as<RecordPayload>()->read("tag").asString() == "second");

    // Fail after the first complete child and another collecting allocation.
    // The previously returned array must remain the caller's result.
    aggregateEffects = 0;
    aggregateFailAt = 2;
    bool rejected = false;
    try { generatedAggregatemixed(heap, result, Value::managed(effect.get())); }
    catch (const std::runtime_error&) { rejected = true; }
    aggregateFailAt = 0;
    heap.collect();
    require(rejected && aggregateEffects == 2 && result.get().asManaged().allocationId() == valuesIdentity);
  }
  heap.collect();
  require(heap.liveCount() == 0);
}

static int controlReads = 0;
static int controlProduces = 0;
static std::int32_t controlInput = 0;
static bool controlNull = false;
static bool controlReadThrows = false;
static bool controlProduceThrows = false;
static void controlRead(Heap& heap, ErasedRef, Root<Value>& output) {
  heap.collect();
  ++controlReads;
  if (controlReadThrows) throw std::runtime_error("scrutinee failure");
  output.set(Value::integer(controlInput));
}
static void controlProduce(Heap& heap, ErasedRef, Root<Value>& result, Value value) {
  heap.collect();
  ++controlProduces;
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(value);
  if (controlProduceThrows) throw std::runtime_error("arm failure");
  result.set(controlNull ? Value() : Value::managed(array.get()));
}

// Switch selection and result writes come from Haxe. Native callbacks force
// collection and distinguish once-only selection from execution of other arms.
static void authoredControlValues(Heap& heap) {
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> read(heap);
    Root<Ref<CallablePayload<void(Root<Value>&, Value)>>> produce(heap);
    heap.allocateInto(read, &controlRead, ErasedRef{});
    heap.allocateInto(produce, &controlProduce, ErasedRef{});
    Root<Value> result(heap);
    for (std::int32_t input : {1, 2, 3, 4}) {
      controlInput = input;
      controlReads = controlProduces = 0;
      generatedControlValueselect(heap, result, Value::managed(read.get()), Value::managed(produce.get()));
      heap.collect();
      require(controlReads == 1 && controlProduces == 1);
      require(result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == (input < 3 ? 7 : input == 3 ? 8 : 9));
    }
    for (bool flag : {false, true}) {
      controlProduces = 0;
      generatedControlValueconditional(heap, result, flag, Value::managed(produce.get()));
      heap.collect();
      require(controlProduces == 1 && result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == (flag ? 4 : 5));
      controlProduces = 0;
      generatedControlValueearly(heap, result, flag, Value::managed(produce.get()));
      heap.collect();
      require(controlProduces == 1 && result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == (flag ? 11 : 12));
      require(generatedControlValuebools(heap, flag) == (flag ? 1 : 2));
    }
    require(generatedControlValuestrings(heap, Value()) == 2);
    require(generatedControlValuestrings(heap, Value::string("")) == 3);
    require(generatedControlValuestrings(heap, Value::string("hit")) == 1);
    require(generatedControlValuedefaultFirst(heap, 1) == 1);
    require(generatedControlValuedefaultFirst(heap, 8) == 9);
    require(generatedControlValuenested(heap, 1) == 7);
    require(generatedControlValuenested(heap, 3) == 9);
    require(generatedControlValueloop(heap) == 1);
    controlNull = true;
    generatedControlValueselect(heap, result, Value::managed(read.get()), Value::managed(produce.get()));
    require(result.get().kind() == ValueKind::Null);
    controlNull = false;
    for (bool failRead : {false, true}) {
      controlReads = controlProduces = 0;
      controlReadThrows = failRead;
      controlProduceThrows = !failRead;
      result.set(Value::integer(83));
      bool rejected = false;
      try { generatedControlValueselect(heap, result, Value::managed(read.get()), Value::managed(produce.get())); }
      catch (const std::runtime_error&) { rejected = true; }
      heap.collect();
      require(rejected && result.get().asInteger() == 83 && controlReads == 1 && controlProduces == (failRead ? 0 : 1));
    }
    controlReadThrows = controlProduceThrows = false;
  }
  heap.collect();
  require(heap.liveCount() == 0);
}

int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "original") {
    Heap heap(0);
    generatedOriginalmain(heap);
    heap.collect();
    if (heap.liveCount() != 0) throw std::runtime_error("original counter retained its graph");
    return 0;
  }
  Heap heap(0);
  authoredControlValues(heap);
  managed_iteration_test::run(heap);
  managed_record_test::run(heap);
  authoredAggregates(heap);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> test(heap);
    heap.allocateInto(test, &conditionEffect, ErasedRef{});
    require(generatedConditionbranch(heap, Value::managed(test.get())) == 1);
    require(conditionChecks == 1);
    conditionChecks = 2;
    require(generatedConditionbranch(heap, Value::managed(test.get())) == 2);
    require(conditionChecks == 3);
    conditionChecks = 0;
    require(generatedConditionloop(heap, Value::managed(test.get())) == 2);
    require(conditionChecks == 3);
    conditionChecks = 0;
    require(generatedConditiondoLoop(heap, Value::managed(test.get())) == 3);
    require(conditionChecks == 3);
    heap.allocateInto(test, &throwingCondition, ErasedRef{});
    int previous = 17;
    bool caught = false;
    try { previous = generatedConditionbranch(heap, Value::managed(test.get())); }
    catch (const std::runtime_error&) { caught = true; }
    require(caught && previous == 17);
  }
  heap.collect();
  require(heap.liveCount() == 0);
  require(generatedRootBranch(heap, true, 12) == 12);
  require(generatedRootBranch(heap, false, 12) == 7);
  generatedRootVoid(heap);
  require(generatedStaticMainentry(heap) == -2);
  require(generatedStaticMainowners(heap) == 7);
  {
    Root<Value> deferred(heap);
    generatedStaticMaindeferred(heap, deferred, 9);
    heap.collect();
    ActiveCall<void(Root<Value>&)> selected(heap, deferred.get().asManaged().as<CallablePayload<void(Root<Value>&)>>());
    Root<Value> returned(heap);
    selected.invoke(returned);
    require(returned.get().asInteger() == 8);
  }
  heap.collect();
  require(heap.liveCount() == 0);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> effect(heap);
    heap.allocateInto(effect, &integerEffect, ErasedRef{});
    require(generatedStaticMainordered(heap, Value::managed(effect.get())) == -5);
    require(integerEffectCount == 2);
    integerEffectCount = 0;
  }
  {
    Root<Ref<ArrayPayload>> value(heap);
    heap.allocateInto(value, ArrayRepresentation::Integer);
    value.get()->append(Value::integer(97));
    Root<Value> returned(heap);
    generatedStaticMainrelay(heap, returned, Value::managed(value.get()));
    value.set({});
    heap.collect();
    require(returned.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 97);
  }
  {
    Root<Ref<CallablePayload<void()>>> effect(heap);
    heap.allocateInto(effect, &staticVoidEffect, ErasedRef{});
    generatedStaticMainrun(heap, Value::managed(effect.get()));
    require(staticVoidEffectCount == 1);
  }
  heap.collect();
  require(heap.liveCount() == 0);
  {
    Root<Value> returned(heap);
    generatedIntegerAdd(heap, {}, returned, Value::integer(INT32_MAX));
    require(returned.get().asInteger() == INT32_MIN);
    generatedIntegerSubtract(heap, {}, returned, Value::integer(INT32_MIN));
    require(returned.get().asInteger() == INT32_MAX);
    generatedIntegerPostIncrement(heap, {}, returned, Value::integer(INT32_MAX));
    require(returned.get().asInteger() == INT32_MAX);
    generatedIntegerPreIncrement(heap, {}, returned, Value::integer(INT32_MAX));
    require(returned.get().asInteger() == INT32_MIN);
    generatedIntegerPostDecrement(heap, {}, returned, Value::integer(INT32_MIN));
    require(returned.get().asInteger() == INT32_MIN);
    generatedIntegerPreDecrement(heap, {}, returned, Value::integer(INT32_MIN));
    require(returned.get().asInteger() == INT32_MAX);
  }
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> effect(heap);
    heap.allocateInto(effect, &integerEffect, ErasedRef{});
    Root<Value> returned(heap);
    generatedIntegerEffects(heap, {}, returned, Value::managed(effect.get()));
    require(returned.get().asInteger() == -5);
    require(integerEffectCount == 2);
  }
  {
    Root<Value> first(heap), second(heap), copy(heap);
    generatedCounterCreator(heap, first);
    generatedCounterCreator(heap, second);
    copy.set(first.get());
    first.set({});
    heap.collect();
    ActiveCall<void(Root<Value>&, Value)> counter(heap, copy.get().asManaged().as<CallablePayload<void(Root<Value>&, Value)>>());
    Root<Value> returned(heap);
    counter.invoke(returned, Value::integer(2));
    require(returned.get().asInteger() == 3);
    heap.collect();
    counter.invoke(returned, Value::integer(1));
    require(returned.get().asInteger() == 5);
    ActiveCall<void(Root<Value>&, Value)> independent(heap, second.get().asManaged().as<CallablePayload<void(Root<Value>&, Value)>>());
    independent.invoke(returned, Value::integer(0));
    require(returned.get().asInteger() == 1);
  }
  heap.collect();
  require(heap.liveCount() == 0);
  generatedCellOperations(heap);
  parameterIngress(heap);
  rootParameterIngress(heap);
  localDeclarationEscape(heap);
  sourceRecursiveDeclaration(heap);
  mutableCapture(heap);
  authoredCallOrder(heap);
  authoredCallResults(heap);
  authoredDirectReturn(heap);
  {
    Root<Ref<CellPayload>> seed(heap);
    allocateCell0(heap, seed);
    Root<Value> assignment(heap);
    writeCell0(heap, [&] { return seed.get(); }, [] { return Value::integer(17); }, assignment);
    Root<Ref<Scalar>> scalar(heap);
    constructScalar(heap, scalar, &scalarEntry, seed.get());
    const auto originalIdentity = scalar.get().allocationId();
    heap.collect();
    const auto beforeFailure = heap.liveCount();
    bool constructionFailed = false;
    try { constructScalar(heap, scalar, nullptr, seed.get()); }
    catch (const std::invalid_argument&) { constructionFailed = true; }
    heap.collect();
    require(constructionFailed && scalar.get().allocationId() == originalIdentity);
    require(heap.liveCount() == beforeFailure);
    // Distinct environment instances must retain the same mutable source cell.
    Root<Ref<Scalar>> sibling(heap);
    constructScalar(heap, sibling, &scalarEntry, seed.get());
    seed.get()->write(Value::integer(18));
    Root<Value> siblingOutput(heap);
    generatedScalar(heap, [&] { return sibling.get(); }, [] { return Value::integer(4); }, siblingOutput);
    require(siblingOutput.get().asInteger() == 22);
    seed.get()->write(Value::integer(17));
    Root<Value> output(heap);
    generatedScalar(heap, [&] { return scalar.get(); }, [&] {
      scalar.set({});
      seed.set({});
      heap.collect();
      return Value::integer(5);
    }, output);
    require(output.get().asInteger() == 22);
  }
  Root<Value> result(heap);
  {
    Root<Ref<ArrayPayload>> input(heap);
    heap.allocateInto(input, ArrayRepresentation::Integer);
    input.get()->append(Value::integer(9));
    const auto identity = input.get().allocationId();
    Root<Ref<Managed>> managed(heap);
    constructManaged(heap, managed, &managedEntry);
    std::string order;
    generatedManaged(heap, [&] {
      order += "callee;";
      return managed.get();
    }, [&] {
      order += "first;";
      managed.set({});
      heap.collect();
      return Value::managed(input.get());
    }, [&] {
      order += "second;";
      input.set({});
      heap.collect();
      return Value::integer(7);
    }, [] { return Value::boolean(true); }, result);
    require(order == "callee;first;second;");
    heap.collect();
    require(result.get().asManaged().allocationId() == identity);
  }
  heap.collect();
  require(result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 9);
  result.set({});
  {
    Root<Ref<Empty>> empty(heap);
    constructEmpty(heap, empty, &emptyEntry);
    generatedEmpty(heap, [&] { return empty.get(); });
  }
  {
    Root<Ref<ReceiverRecord>> instance(heap);
    heap.allocateInto(instance, 23);
    Root<Ref<CellPayload>> receiver(heap);
    heap.allocateInto(receiver, CellWriteMode::Replaceable);
    receiver.get()->write(Value::managed(instance.get()));
    Root<Ref<Receiver>> callable(heap);
    constructReceiver(heap, callable, &receiverEntry, receiver.get());
    instance.set({});
    receiver.set({});
    Root<Value> output(heap);
    generatedReceiver(heap, [&] { return callable.get(); }, output);
    require(output.get().asInteger() == 23);
  }
  // Argument and body failures must unwind generated roots and leave the
  // caller's previous result intact, even if the callee wrote its result slot.
  for (bool failArgument : {false, true}) {
    Root<Ref<Managed>> callable(heap);
    constructManaged(heap, callable, &throwingEntry);
    result.set(Value::integer(41));
    bool caught = false;
    try {
      generatedManaged(heap, [&] { return callable.get(); }, [&] {
        callable.set({});
        heap.collect();
        return Value::integer(19);
      }, [&]() -> Value {
        heap.collect();
        if (failArgument) throw std::runtime_error("argument failure");
        return Value::integer(7);
      }, [] { return Value::boolean(true); }, result);
    } catch (const std::runtime_error&) { caught = true; }
    require(caught && result.get().asInteger() == 41);
    heap.collect();
    require(heap.liveCount() == 0);
  }
  bool argumentRan = false;
  bool nullRejected = false;
  Root<Value> unchanged(heap, Value::integer(51));
  try {
    generatedScalar(heap, [] { return Ref<Scalar>(); }, [&] {
      argumentRan = true;
      return Value::integer(0);
    }, unchanged);
  } catch (const std::invalid_argument&) { nullRejected = true; }
  require(nullRejected && argumentRan && unchanged.get().asInteger() == 51);
  // Both branches are authored Haxe control flow, rendered through the shared
  // control-region owner with the managed caller-owned result convention.
  for (bool choose : {false, true}) {
    generatedManagedBody(heap, {}, result, Value::integer(61), Value::integer(62), Value::boolean(choose));
    require(result.get().asInteger() == (choose ? 61 : 62));
  }
  heap.collect();
  require(heap.liveCount() == 0);
  std::cout << "CPP_MANAGED_ABI:PASS\n";
}
