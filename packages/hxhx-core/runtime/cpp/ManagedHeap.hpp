#pragma once

#include <cstddef>
#include <cstdint>
#include <exception>
#include <functional>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <vector>

// Memory primitives only. Haxe-owned plans select payloads, roots and capture
// placement. Native constructors, trace hooks and destructors cannot run Haxe.
namespace hxhx::managed {

class Heap;
class Visitor;
class ErasedRef;
template<class Payload> struct Trace; // No implicit pointer-free fallback.
template<class Payload> struct Node;

// Physical layout identity only. Semantic class identity belongs to descriptors.
struct LayoutIdentity final {};
template<class Payload> inline const LayoutIdentity layoutIdentity{};

struct NodeBase {
  Heap* owner;
  NodeBase* next = nullptr;
  NodeBase* pending = nullptr;
  bool marked = false;
  const std::uint64_t id;
  const std::size_t bytes;
  const LayoutIdentity* const layout;
  NodeBase(Heap& owner, std::uint64_t id, std::size_t bytes, const LayoutIdentity& layout) noexcept
      : owner(&owner), id(id), bytes(bytes), layout(&layout) {}
  virtual void trace(Visitor&) noexcept = 0;
  virtual ~NodeBase() noexcept = default;
};

// A reference is an internal graph edge, not a registered root. The heap and
// all referenced nodes must outlive its use. Cross-heap edges are forbidden.
template<class Payload> class Ref {
  friend class Heap;
  friend class Visitor;
  friend class ErasedRef;
  Node<Payload>* node_ = nullptr;
  explicit Ref(Node<Payload>* node) noexcept : node_(node) {}
public:
  Ref() noexcept = default;
  explicit operator bool() const noexcept { return node_ != nullptr; }
  Payload* operator->() const noexcept;
  std::uint64_t allocationId() const noexcept { return node_ == nullptr ? 0 : node_->id; }
  bool operator==(Ref other) const noexcept { return node_ == other.node_; }
};

// Type erasure preserves one allocation and its trace function. Recovery checks
// the physical layout before casting; it does not implement source isOfType.
class ErasedRef {
  friend class Visitor;
  NodeBase* node_ = nullptr;
public:
  ErasedRef() noexcept = default;
  template<class Payload> explicit ErasedRef(Ref<Payload> value) noexcept : node_(value.node_) {}
  explicit operator bool() const noexcept { return node_ != nullptr; }
  std::uint64_t allocationId() const noexcept { return node_ == nullptr ? 0 : node_->id; }
  bool operator==(ErasedRef other) const noexcept { return node_ == other.node_; }
  // A total ordering of physical identities for compiler-selected identity maps.
  // It neither compares payload fields nor assigns source-language class identity.
  bool identityBefore(ErasedRef other) const noexcept {
    return std::less<NodeBase*>{}(node_, other.node_);
  }
  template<class Payload> Ref<Payload> as() const;
  // A non-throwing physical read guard for Haxe-selected runtime operations.
  // This does not establish a Haxe class, generic argument, or Map family.
  template<class Payload> bool hasLayout() const noexcept {
    return node_ != nullptr && node_->layout == &layoutIdentity<Payload>;
  }
};

class Visitor {
  friend class Heap;
  Heap* heap_;
  NodeBase* pending_ = nullptr;
  explicit Visitor(Heap& heap) noexcept : heap_(&heap) {}
  void markNode(NodeBase* node) noexcept {
    if (node == nullptr) return;
    if (node->owner != heap_) std::terminate();
    if (node->marked) return;
    node->marked = true;
    node->pending = pending_;
    pending_ = node;
  }
public:
  template<class Payload> void mark(Ref<Payload> reference) noexcept { markNode(reference.node_); }
  void mark(ErasedRef reference) noexcept { markNode(reference.node_); }
};

template<> struct Trace<ErasedRef> {
  static void visit(ErasedRef value, Visitor& visitor) noexcept { visitor.mark(value); }
};

template<class Payload> struct Trace<Ref<Payload>> {
  static void visit(Ref<Payload> value, Visitor& visitor) noexcept { visitor.mark(value); }
};

template<class Payload> struct Node final : NodeBase {
  Payload payload;
  template<class... Arguments>
  Node(Heap& heap, std::uint64_t id, Arguments&&... arguments)
      : NodeBase(heap, id, sizeof(Node), layoutIdentity<Payload>), payload(std::forward<Arguments>(arguments)...) {
    static_assert(std::is_nothrow_destructible_v<Payload>, "managed payload destruction must be noexcept");
    static_assert(noexcept(Trace<Payload>::visit(payload, std::declval<Visitor&>())), "managed tracing must be noexcept");
  }
  void trace(Visitor& visitor) noexcept override { Trace<Payload>::visit(payload, visitor); }
};

template<class Payload> Payload* Ref<Payload>::operator->() const noexcept { return &node_->payload; }

template<class Payload> Ref<Payload> ErasedRef::as() const {
  if (node_ == nullptr) return {};
  if (node_->layout != &layoutIdentity<Payload>) throw std::invalid_argument("managed payload layout mismatch");
  // The exact Node<Payload> constructor installs this token; no unchecked
  // source-level downcast or semantic class-membership inference occurs here.
  return Ref<Payload>(static_cast<Node<Payload>*>(node_));
}

class RootBase {
  friend class Heap;
  Heap* heap_;
  RootBase* previous_ = nullptr;
  RootBase* next_ = nullptr;
protected:
  explicit RootBase(Heap& heap) noexcept;
  ~RootBase() noexcept;
  virtual void trace(Visitor&) noexcept = 0;
public:
  RootBase(const RootBase&) = delete;
  RootBase& operator=(const RootBase&) = delete;
};

// Stable-address RAII registration. Copy values into another root explicitly;
// never embed a Root in a managed payload, where it would make cycles immortal.
template<class Value> class Root final : public RootBase {
  Value value_;
  void trace(Visitor& visitor) noexcept override { Trace<Value>::visit(value_, visitor); }
public:
  explicit Root(Heap& heap, Value value = {}) noexcept(std::is_nothrow_move_constructible_v<Value>)
      : RootBase(heap), value_(std::move(value)) {
    static_assert(noexcept(Trace<Value>::visit(value_, std::declval<Visitor&>())), "root tracing must be noexcept");
  }
  const Value& get() const noexcept { return value_; }
  void set(Value value) noexcept(std::is_nothrow_move_assignable_v<Value>) { value_ = std::move(value); }
};

// Single-mutator, synchronous, non-moving heap. Every live external value must
// be rooted at collection. Destruction is passive and never visits managed peers.
class Heap {
  friend class RootBase;
  NodeBase* nodes_ = nullptr;
  RootBase* roots_ = nullptr;
  // Published program storage stays rooted for this heap's lifetime. The
  // generated payload type identifies a storage layout, never a Haxe class.
  std::vector<NodeBase*> staticRoots_;
  std::size_t live_ = 0;
  std::size_t bytes_ = 0;
  std::size_t rootCount_ = 0;
  std::size_t allocatedSinceCollection_ = 0;
  std::size_t collectionBudget_;
  std::uint64_t nextId_ = 1;
  bool busy_ = false;

  struct Phase {
    bool& busy;
    explicit Phase(bool& busy) : busy(busy) {
      if (busy) throw std::logic_error("managed heap operation reentered a native phase");
      busy = true;
    }
    ~Phase() noexcept { busy = false; }
  };
public:
  explicit Heap(std::size_t collectionBudget = 65536) noexcept : collectionBudget_(collectionBudget) {}
  Heap(const Heap&) = delete;
  Heap& operator=(const Heap&) = delete;
  ~Heap() noexcept {
    if (roots_ != nullptr || busy_) std::terminate();
    busy_ = true;
    while (nodes_ != nullptr) {
      auto* node = nodes_;
      nodes_ = node->next;
      delete node;
    }
  }

  // Inputs must already be rooted. Native construction creates only trace-safe
  // storage. Authored initialization runs later, after publication into target.
  template<class Payload, class... Arguments>
  void allocateInto(Root<Ref<Payload>>& target, Arguments&&... arguments) {
    if (target.heap_ != this) throw std::invalid_argument("allocation destination belongs to another heap");
    if (allocatedSinceCollection_ >= collectionBudget_) collect();
    Phase phase(busy_);
    auto* node = new Node<Payload>(*this, nextId_, std::forward<Arguments>(arguments)...);
    node->next = nodes_;
    nodes_ = node;
    ++nextId_;
    ++live_;
    bytes_ += node->bytes;
    allocatedSinceCollection_ += node->bytes;
    target.set(Ref<Payload>(node));
  }

  // Register one generated storage payload before authored initialization runs.
  // Haxe owns defaults, field identity, initialization order and failure policy.
  // This primitive never invokes source code or retries an existing registration.
  template<class Payload, class... Arguments>
  void allocateStaticInto(Root<Ref<Payload>>& target, Arguments&&... arguments) {
    if (busy_) throw std::logic_error("static publication reentered a native phase");
    if (target.heap_ != this) throw std::invalid_argument("static destination belongs to another heap");
    for (const auto* node : staticRoots_)
      if (node->layout == &layoutIdentity<Payload>) throw std::logic_error("static storage already published");
    // Reserve before allocation/publication so a registry allocation failure
    // leaves both the destination and the existing static graph unchanged.
    staticRoots_.reserve(staticRoots_.size() + 1);
    allocateInto(target, std::forward<Arguments>(arguments)...);
    staticRoots_.push_back(target.get().node_);
  }

  // No lazy initialization: absence is a compiler/host lifecycle error. Exact
  // layout identity proves the Node cast, as it does for ordinary erased edges.
  template<class Payload> Ref<Payload> requireStatic() const {
    for (auto* node : staticRoots_)
      if (node->layout == &layoutIdentity<Payload>) return Ref<Payload>(static_cast<Node<Payload>*>(node));
    throw std::logic_error("static storage has not been published");
  }

  void collect() {
    Phase phase(busy_);
    Visitor visitor(*this);
    for (auto* root = roots_; root != nullptr; root = root->next_) root->trace(visitor);
    for (auto* node : staticRoots_) visitor.markNode(node);
    while (visitor.pending_ != nullptr) {
      auto* node = visitor.pending_;
      visitor.pending_ = node->pending;
      node->pending = nullptr;
      node->trace(visitor);
    }
    auto** cursor = &nodes_;
    while (*cursor != nullptr) {
      auto* node = *cursor;
      if (node->marked) {
        node->marked = false;
        cursor = &node->next;
      } else {
        *cursor = node->next;
        --live_;
        bytes_ -= node->bytes;
        delete node;
      }
    }
    allocatedSinceCollection_ = 0;
  }

  std::size_t liveCount() const noexcept { return live_; }
  std::size_t rootCount() const noexcept { return rootCount_; }
  std::size_t staticRootCount() const noexcept { return staticRoots_.size(); }
  // Allocation blocks only; payload-owned native buffers need their own observer.
  std::size_t allocationBytes() const noexcept { return bytes_; }
};

inline RootBase::RootBase(Heap& heap) noexcept : heap_(&heap) {
  if (heap.busy_) std::terminate();
  next_ = heap.roots_;
  if (next_ != nullptr) next_->previous_ = this;
  heap.roots_ = this;
  ++heap.rootCount_;
}

inline RootBase::~RootBase() noexcept {
  if (heap_->busy_) std::terminate();
  if (previous_ != nullptr) previous_->next_ = next_;
  else heap_->roots_ = next_;
  if (next_ != nullptr) next_->previous_ = previous_;
  --heap_->rootCount_;
}

}
