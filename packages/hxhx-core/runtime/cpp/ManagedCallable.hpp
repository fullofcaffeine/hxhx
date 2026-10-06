#pragma once

#include "ManagedValue.hpp"
#include "ManagedMap.hpp"
#include "ManagedThrow.hpp"
#include <optional>

namespace hxhx::managed {

// The Haxe storage plan selects a physical write contract. Native code does not
// infer source mutability or decide where a new binding instance is created.
enum class CellWriteMode { Once, Replaceable };

// Presence is separate from null. Reading returns a value copy, never a movable
// reference to the surviving cell. Root that value before a collecting operation.
class CellPayload {
  const CellWriteMode mode_;
  std::optional<Value> value_;
public:
  explicit CellPayload(CellWriteMode mode) noexcept : mode_(mode) {}
  CellPayload(const CellPayload&) = delete;
  CellPayload& operator=(const CellPayload&) = delete;
  bool assigned() const noexcept { return value_.has_value(); }
  Value read() const {
    if (!value_) throw std::logic_error("managed cell is unassigned");
    return *value_;
  }
  void write(Value value) {
    if (value_ && mode_ == CellWriteMode::Once) throw std::logic_error("managed cell is already initialized");
    value_ = std::move(value);
  }
  void trace(Visitor& visitor) const noexcept {
    if (value_) value_->trace(visitor);
  }
};

template<> struct Trace<CellPayload> {
  static void visit(const CellPayload& cell, Visitor& visitor) noexcept { cell.trace(visitor); }
};

template<class Signature> class CallablePayload;
template<class Signature> class ActiveCall;

// The signature is selected by Haxe lowering. Leaf results may return directly;
// managed results require a caller-owned Root in the generated argument list.
// The environment is one traced edge, never an opaque native closure capture.
template<class Result, class... Arguments>
class CallablePayload<Result(Arguments...)> {
  template<class> friend class ActiveCall;
public:
  using Entry = Result (*)(Heap&, ErasedRef, Arguments...);
private:
  const Entry entry_;
  const ErasedRef environment_;
public:
  CallablePayload(Entry entry, ErasedRef environment) : entry_(entry), environment_(environment) {
    if (entry_ == nullptr) throw std::invalid_argument("managed callable has no entry point");
  }
  CallablePayload(const CallablePayload&) = delete;
  CallablePayload& operator=(const CallablePayload&) = delete;
  void trace(Visitor& visitor) const noexcept { visitor.mark(environment_); }
};

template<class Signature> struct Trace<CallablePayload<Signature>> {
  static void visit(const CallablePayload<Signature>& callable, Visitor& visitor) noexcept { callable.trace(visitor); }
};

// Construct before evaluating source arguments. The selected callable and its
// environment remain alive during argument effects, invocation, and unwinding.
// This root does not root argument temporaries: generated code must do that.
template<class Result, class... Arguments>
class ActiveCall<Result(Arguments...)> {
  Heap& heap_;
  Root<Ref<CallablePayload<Result(Arguments...)>>> selected_;
public:
  ActiveCall(Heap& heap, Ref<CallablePayload<Result(Arguments...)>> selected) : heap_(heap), selected_(heap, selected) {}
  ActiveCall(const ActiveCall&) = delete;
  ActiveCall& operator=(const ActiveCall&) = delete;
  Result invoke(Arguments... arguments) const {
    const auto selected = selected_.get();
    // Selection roots even a null value. Source argument effects must finish
    // before invocation reports the missing callable.
    if (!selected) throw std::invalid_argument("active call has no selected callable");
    return selected->entry_(heap_, selected->environment_, std::forward<Arguments>(arguments)...);
  }
};

}
