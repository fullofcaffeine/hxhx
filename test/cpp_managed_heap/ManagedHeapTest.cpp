#include "ManagedHeap.hpp"
#include <array>
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace hxhx::managed;

struct Vertex {
  std::size_t index;
  std::array<int, 6>* destroyed;
  std::vector<Ref<Vertex>> edges;
  Vertex(std::size_t index, std::array<int, 6>& destroyed)
      : index(index), destroyed(&destroyed) {}
  ~Vertex() noexcept { ++(*destroyed)[index]; }
};

struct Holder {
  Ref<Vertex> child;
};

struct ConstructionFailure {
  ConstructionFailure() { throw std::runtime_error("native construction failed"); }
};

struct alignas(64) AlignedValue {
  int value;
  explicit AlignedValue(int value) : value(value) {
    if (value < 0) throw std::runtime_error("replacement construction failed");
  }
};

namespace hxhx::managed {
template<> struct Trace<Vertex> {
  static void visit(const Vertex& value, Visitor& visitor) noexcept {
    for (const auto edge : value.edges) visitor.mark(edge);
  }
};
template<> struct Trace<Holder> {
  static void visit(const Holder& value, Visitor& visitor) noexcept { visitor.mark(value.child); }
};
template<> struct Trace<ConstructionFailure> {
  static void visit(const ConstructionFailure&, Visitor&) noexcept {}
};
template<> struct Trace<AlignedValue> {
  static void visit(const AlignedValue&, Visitor&) noexcept {}
};
}

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// This graph model never reads the runtime's edge inventory or mark state.
static std::array<bool, 6> expectedReachability(unsigned roots) {
  const std::array<std::vector<int>, 6> adjacency = {{{1}, {2}, {0}, {4}, {}, {5}}};
  std::array<bool, 6> seen{};
  std::vector<int> pending;
  for (int index = 0; index < 6; ++index)
    if (roots & (1u << index)) pending.push_back(index);
  while (!pending.empty()) {
    const auto index = pending.back();
    pending.pop_back();
    if (seen[index]) continue;
    seen[index] = true;
    for (const auto child : adjacency[index]) pending.push_back(child);
  }
  return seen;
}

static void graphCases(std::size_t collectionBudget) {
  for (unsigned mask = 0; mask < 64; ++mask) {
    std::array<int, 6> destroyed{};
    Heap heap(collectionBudget);
    {
      Root<Ref<Vertex>> first(heap), second(heap), third(heap), fourth(heap), fifth(heap), sixth(heap);
      const std::array<Root<Ref<Vertex>>*, 6> roots = {&first, &second, &third, &fourth, &fifth, &sixth};
      for (std::size_t index = 0; index < roots.size(); ++index)
        heap.allocateInto(*roots[index], index, destroyed);
      first.get()->edges.push_back(second.get());
      second.get()->edges.push_back(third.get());
      third.get()->edges.push_back(first.get());
      fourth.get()->edges.push_back(fifth.get());
      sixth.get()->edges.push_back(sixth.get());
      for (std::size_t index = 0; index < roots.size(); ++index)
        if (!(mask & (1u << index))) roots[index]->set({});
      heap.collect();
      const auto expected = expectedReachability(mask);
      std::size_t expectedLive = 0;
      for (std::size_t index = 0; index < roots.size(); ++index) {
        require(destroyed[index] == (expected[index] ? 0 : 1), "reachability differs from independent graph model");
        if (expected[index]) ++expectedLive;
        roots[index]->set({});
      }
      require(heap.liveCount() == expectedLive, "live allocation count differs");
      heap.collect();
      heap.collect();
      for (const auto count : destroyed) require(count == 1, "payload destruction must occur exactly once");
      require(heap.liveCount() == 0 && heap.allocationBytes() == 0, "unrooted cycle remains allocated");
    }
    require(heap.rootCount() == 0, "root registration leaked");
  }
}

static void handoffAndFailure() {
  std::array<int, 6> destroyed{};
  Heap heap(0);
  Root<Ref<Vertex>> result(heap);
  {
    Root<Ref<Vertex>> input(heap);
    heap.allocateInto(input, 0, destroyed);
    Root<Ref<Holder>> holder(heap);
    heap.allocateInto(holder);
    holder.get()->child = input.get();
    input.set({});
    heap.collect();
    require(destroyed[0] == 0, "mixed payload edge did not retain its child");
    result.set(holder.get()->child);
  }
  heap.collect();
  require(result.get()->index == 0 && heap.liveCount() == 1, "rooted result handoff lost its value");
  {
    Root<Ref<Vertex>> copy(heap, result.get());
    result.set({});
    heap.collect();
    require(destroyed[0] == 0, "a copied root did not preserve the value");
  }
  heap.collect();
  require(destroyed[0] == 1, "last root release did not permit collection");
  Root<Ref<ConstructionFailure>> failed(heap);
  bool observed = false;
  try { heap.allocateInto(failed); }
  catch (const std::runtime_error&) { observed = true; }
  require(observed && !failed.get() && heap.liveCount() == 0, "failed native construction published a node");
  const auto rootsBefore = heap.rootCount();
  try {
    Root<Ref<Vertex>> temporary(heap);
    heap.allocateInto(temporary, 1, destroyed);
    throw std::runtime_error("source unwind observer");
  } catch (const std::runtime_error&) {}
  require(heap.rootCount() == rootsBefore, "exception unwind leaked a root");
  heap.collect();
  require(destroyed[1] == 1, "exception unwind retained an unreachable payload");
}

int main() {
  graphCases(65536);
  graphCases(0);
  handoffAndFailure();
  {
    Heap heap(0);
    Root<Ref<AlignedValue>> value(heap);
    heap.allocateInto(value, 42);
    const auto originalId = value.get().allocationId();
    require(reinterpret_cast<std::uintptr_t>(value.get().operator->()) % 64 == 0, "payload alignment lost");
    bool failed = false;
    try { heap.allocateInto(value, -1); }
    catch (const std::runtime_error&) { failed = true; }
    heap.collect();
    require(failed && value.get()->value == 42 && value.get().allocationId() == originalId,
            "failed replacement must preserve the previous rooted value");
    require(heap.liveCount() == 1, "failed replacement leaked a published node");
  }
  std::array<int, 6> destroyed{};
  {
    Heap heap;
    Root<Ref<Vertex>> value(heap);
    heap.allocateInto(value, 0, destroyed);
    value.get()->edges.push_back(value.get());
  }
  require(destroyed[0] == 1, "heap teardown did not destroy an uncollected cycle");
  std::cout << "CPP_MANAGED_HEAP:PASS\n";
}
