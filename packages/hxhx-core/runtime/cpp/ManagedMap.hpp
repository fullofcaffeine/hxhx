#pragma once

#include "ManagedValue.hpp"

namespace hxhx::managed {

// Haxe selects the key representation and source operations. This container
// owns only physical storage and traced value edges. Keys must be native
// integers or strings, never untraced references to managed payloads.
template<class Key> class KeyedMapPayload {
  static_assert(std::is_same_v<Key, std::int32_t> || std::is_same_v<Key, std::string>);
  std::map<Key, Value> entries_;
public:
  std::size_t size() const noexcept { return entries_.size(); }
  bool contains(const Key& key) const { return entries_.find(key) != entries_.end(); }
  Value readExisting(const Key& key) const { return entries_.at(key); }
  void insert(Key key, Value value) { entries_.insert_or_assign(std::move(key), std::move(value)); }
  void trace(Visitor& visitor) const noexcept {
    for (const auto& entry : entries_) entry.second.trace(visitor);
  }
};

template<class Key> struct Trace<KeyedMapPayload<Key>> {
  static void visit(const KeyedMapPayload<Key>& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

using IntMapPayload = KeyedMapPayload<std::int32_t>;
using StringMapPayload = KeyedMapPayload<std::string>;

// Both sides are graph edges. Stable allocation identity is selected by the
// Haxe target plan; this storage never interprets fields, classes, or enum data.
// A null edge is a valid distinct key. No iterator or borrowed entry escapes.
class ObjectMapPayload {
  struct IdentityLess {
    bool operator()(ErasedRef left, ErasedRef right) const noexcept {
      return left.identityBefore(right);
    }
  };
  std::map<ErasedRef, Value, IdentityLess> entries_;
public:
  std::size_t size() const noexcept { return entries_.size(); }
  bool contains(ErasedRef key) const { return entries_.find(key) != entries_.end(); }
  Value readExisting(ErasedRef key) const { return entries_.at(key); }
  void insert(ErasedRef key, Value value) { entries_.insert_or_assign(key, std::move(value)); }
  void trace(Visitor& visitor) const noexcept {
    for (const auto& entry : entries_) {
      visitor.mark(entry.first);
      entry.second.trace(visitor);
    }
  }
};

template<> struct Trace<ObjectMapPayload> {
  static void visit(const ObjectMapPayload& value, Visitor& visitor) noexcept { value.trace(visitor); }
};

}
