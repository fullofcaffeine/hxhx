#pragma once

#include "ManagedValue.hpp"
#include <memory>

namespace hxhx::managed {

// Native unwinding transport, separate from every Haxe Exception object/view.
// Construction roots an already evaluated value before its source scope exits.
// Copies retain the same stable root without allocation or Haxe execution.
// The Heap must outlive every copy and exception_ptr that retains this carrier.
// Never store this carrier in a managed payload: its external root would keep
// that payload's cycle alive. Haxe owns catch selection and wrapper creation.
class ThrownValue final {
  std::shared_ptr<const Root<Value>> value_;
public:
  explicit ThrownValue(Heap& heap, Value value)
      : value_(std::make_shared<Root<Value>>(heap, std::move(value))) {}
  ThrownValue(const ThrownValue&) noexcept = default;
  ThrownValue& operator=(const ThrownValue&) noexcept = default;
  const Value& value() const noexcept { return value_->get(); }
};

}
