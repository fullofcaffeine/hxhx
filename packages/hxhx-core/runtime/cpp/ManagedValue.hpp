#pragma once

#include "ManagedHeap.hpp"
#include <map>
#include <string>
#include <variant>
#include <vector>

namespace hxhx::managed {

// Haxe-owned descriptor generation supplies the contents and static lifetime.
struct ClassDescriptor;
enum class ValueKind { Null, Boolean, Integer, Float, String, Managed, Descriptor };

// Common storage transport, not a Haxe conversion or type-membership engine.
// Managed alternatives are graph edges; descriptors never own live instances.
class Value {
  using Storage = std::variant<std::monostate, bool, std::int32_t, double, std::string, ErasedRef, const ClassDescriptor*>;
  Storage storage_;
  explicit Value(Storage storage) : storage_(std::move(storage)) {}
public:
  Value() noexcept = default;
  Value(const Value&) = default;
  Value(Value&&) noexcept = default;
  // Copy before replacing storage. A failing string allocation must not leave
  // a traced location without its previous value or with a valueless variant.
  Value& operator=(Value value) noexcept {
    static_assert(std::is_nothrow_swappable_v<Storage>);
    storage_.swap(value.storage_);
    return *this;
  }
  static Value boolean(bool value) { return Value(Storage(value)); }
  static Value integer(std::int32_t value) { return Value(Storage(value)); }
  static Value floating(double value) { return Value(Storage(value)); }
  static Value string(std::string value) { return Value(Storage(std::move(value))); }
  static Value managed(ErasedRef value) { return value ? Value(Storage(value)) : Value(); }
  template<class Payload> static Value managed(Ref<Payload> value) { return managed(ErasedRef(value)); }
  static Value descriptor(const ClassDescriptor* value) { return value == nullptr ? Value() : Value(Storage(value)); }

  ValueKind kind() const noexcept {
    if (storage_.valueless_by_exception()) std::terminate();
    return static_cast<ValueKind>(storage_.index());
  }
  bool asBoolean() const { return std::get<bool>(storage_); }
  std::int32_t asInteger() const { return std::get<std::int32_t>(storage_); }
  double asFloat() const { return std::get<double>(storage_); }
  const std::string& asString() const { return std::get<std::string>(storage_); }
  ErasedRef asManaged() const { return std::get<ErasedRef>(storage_); }
  const ClassDescriptor* asDescriptor() const { return std::get<const ClassDescriptor*>(storage_); }

  void trace(Visitor& visitor) const noexcept {
    if (const auto* edge = std::get_if<ErasedRef>(&storage_)) visitor.mark(*edge);
  }
};

template<> struct Trace<Value> {
  static void visit(const Value& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

// A compiler-selected lexical result slot registers its root before branch
// evaluation. Missing assignment is distinct from assigned Null. This storage
// never escapes its scope; captured bindings use separately traced cells.
class LocalSlot {
  Root<Value> value_;
  bool assigned_ = false;
public:
  explicit LocalSlot(Heap& heap) : value_(heap) {}
  Value get() const {
    if (!assigned_) throw std::logic_error("managed local slot is unassigned");
    return value_.get();
  }
  void set(Value value) {
    value_.set(std::move(value));
    assigned_ = true;
  }
};

// One physical array family for all source element types. Haxe plans own source
// indexing, growth and conversion rules; these methods are checked storage I/O.
// No element reference escapes because native vector growth can invalidate it.
enum class ArrayRepresentation { Boolean, Integer, Float, String, Reference, Dynamic };

class ArrayPayload {
  const ArrayRepresentation representation_;
  std::vector<Value> elements_;
public:
  // The Haxe allocation plan selects this immutable fact. Storage never derives
  // a source representation from current elements, including an empty array.
  explicit ArrayPayload(ArrayRepresentation representation) noexcept : representation_(representation) {}
  ArrayRepresentation representation() const noexcept { return representation_; }
  std::size_t size() const noexcept { return elements_.size(); }
  Value read(std::size_t index) const { return elements_.at(index); }
  void write(std::size_t index, Value value) { elements_.at(index) = std::move(value); }
  void append(Value value) { elements_.push_back(std::move(value)); }
  void trace(Visitor& visitor) const noexcept {
    for (const auto& value : elements_) value.trace(visitor);
  }
};

template<> struct Trace<ArrayPayload> {
  static void visit(const ArrayPayload& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

// Anonymous fields have named common-value storage. The compiler selects
// fields and source types; these operations provide checked physical I/O only.
// An absent field is distinct from a field containing Null. No borrowed value
// or map iterator escapes across collecting source operations.
class RecordPayload {
  std::map<std::string, Value> fields_;
public:
  bool contains(const std::string& name) const { return fields_.find(name) != fields_.end(); }
  Value read(const std::string& name) const { return fields_.at(name); }
  void define(std::string name, Value value) {
    if (!fields_.emplace(std::move(name), std::move(value)).second)
      throw std::invalid_argument("record field is already defined");
  }
  void write(const std::string& name, Value value) { fields_.at(name) = std::move(value); }
  void trace(Visitor& visitor) const noexcept {
    for (const auto& field : fields_) field.second.trace(visitor);
  }
};

template<> struct Trace<RecordPayload> {
  static void visit(const RecordPayload& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

// Haxe owns canonical declaration identity and field layout. This is not a
// public reflection name, constructor factory, or native type-inference rule.
// A descriptor has static lifetime and never retains an instance.
// Identity-only descriptors do not authorize allocation, even with zero fields.
struct ClassDescriptor {
  const char* identity;
  bool hasInstanceLayout;
  std::size_t fieldCount;
  const ClassDescriptor* parent;
};

// Haxe selects one immutable identity for each applied instance layout. Several
// applications can share a public class while selecting different compiled
// method bodies. This reference never adds managed ownership or native lookup.
struct InstanceDescriptor {
  const ClassDescriptor& declaration;
};

// One traced allocation stores the fields selected by the Haxe layout plan.
// Defaults arrive explicitly; native storage never invents source initialization.
// The Haxe plan preserves each ancestor layout as a prefix and supplies the
// complete acyclic parent chain. Native storage only checks those exact owners.
class InstancePayload {
  const InstanceDescriptor* instanceDescriptor_;
  std::vector<Value> fields_;
  void requireOwner(const ClassDescriptor& owner) const {
    if (!hasOwner(owner)) throw std::invalid_argument("instance field belongs to another layout");
  }
public:
  InstancePayload(const InstanceDescriptor& instanceDescriptor, std::vector<Value> defaults)
      : instanceDescriptor_(&instanceDescriptor), fields_(std::move(defaults)) {
    const auto& descriptor = instanceDescriptor.declaration;
    if (descriptor.identity == nullptr || descriptor.identity[0] == '\0' || !descriptor.hasInstanceLayout || fields_.size() != descriptor.fieldCount)
      throw std::invalid_argument("instance allocation requires its complete declared layout");
  }
  const ClassDescriptor& descriptor() const noexcept { return instanceDescriptor_->declaration; }
  const InstanceDescriptor& instanceDescriptor() const noexcept { return *instanceDescriptor_; }
  bool hasOwner(const ClassDescriptor& owner) const noexcept {
    for (auto current = &descriptor(); current != nullptr; current = current->parent)
      if (current == &owner) return true;
    return false;
  }
  Value read(const ClassDescriptor& owner, std::size_t index) const {
    requireOwner(owner);
    if (index >= owner.fieldCount) throw std::out_of_range("field exceeds its declaring layout");
    return fields_.at(index);
  }
  void write(const ClassDescriptor& owner, std::size_t index, Value value) {
    requireOwner(owner);
    if (index >= owner.fieldCount) throw std::out_of_range("field exceeds its declaring layout");
    fields_.at(index) = std::move(value);
  }
  void trace(Visitor& visitor) const noexcept {
    for (const auto& value : fields_) value.trace(visitor);
  }
};

template<> struct Trace<InstancePayload> {
  static void visit(const InstancePayload& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

// Haxe emits these immutable tables with static lifetime from exact declaration
// facts. The native primitive validates physical bounds, not source lookup,
// generic specialization, equality, or constructor initialization order.
struct EnumConstructorDescriptor {
  const char* name;
  std::size_t arity;
};

struct EnumDescriptor {
  const char* identity;
  const EnumConstructorDescriptor* constructors;
  std::size_t constructorCount;
};

// Constructor payloads are immutable graph edges. A referenced array or object
// can still mutate and can point back to this enum. Return values by copy so no
// borrowed payload element escapes across a collecting source operation.
class EnumPayload {
  const EnumDescriptor* descriptor_;
  std::size_t constructor_;
  std::vector<Value> values_;
public:
  EnumPayload(const EnumDescriptor& descriptor, std::size_t constructor, std::vector<Value> values)
      : descriptor_(&descriptor), constructor_(constructor), values_(std::move(values)) {
    if (descriptor.identity == nullptr || descriptor.identity[0] == '\0' ||
        descriptor.constructors == nullptr || constructor >= descriptor.constructorCount)
      throw std::invalid_argument("enum allocation requires a valid descriptor and constructor tag");
    const auto& selected = descriptor.constructors[constructor];
    if (selected.name == nullptr || selected.name[0] == '\0' || selected.arity != values_.size())
      throw std::invalid_argument("enum allocation requires its declared payload arity");
  }
  const EnumDescriptor& descriptor() const noexcept { return *descriptor_; }
  std::size_t constructorIndex() const noexcept { return constructor_; }
  // Physical descriptor validation only. Haxe decides whether an ordinal
  // preserves the selected source operation (for example, a nullary enum key).
  std::size_t constructorIndex(const EnumDescriptor& expected) const {
    if (descriptor_ != &expected)
      throw std::invalid_argument("enum constructor index belongs to another descriptor");
    return constructor_;
  }
  std::size_t size() const noexcept { return values_.size(); }
  Value read(std::size_t index) const { return values_.at(index); }
  void trace(Visitor& visitor) const noexcept {
    for (const auto& value : values_) value.trace(visitor);
  }
};

template<> struct Trace<EnumPayload> {
  static void visit(const EnumPayload& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

// A suspended element access retains owner plus index, not a borrowed native
// element address. Keep the place in a Root across any collecting source call.
struct ArrayPlace {
  Ref<ArrayPayload> owner;
  std::size_t index = 0;
  Value read() const {
    if (!owner) throw std::invalid_argument("array place has no owner");
    return owner->read(index);
  }
  void write(Value value) const {
    if (!owner) throw std::invalid_argument("array place has no owner");
    owner->write(index, std::move(value));
  }
};

template<> struct Trace<ArrayPlace> {
  static void visit(const ArrayPlace& place, Visitor& visitor) noexcept { visitor.mark(place.owner); }
};

}
