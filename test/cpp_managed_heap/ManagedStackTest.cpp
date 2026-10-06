#include "ManagedStack.hpp"
#include <iostream>
#include <stdexcept>
#include <type_traits>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Metadata stands in for static records selected by the Haxe emitter. The
// primitive never discovers source functions from native symbol spellings.
static const StackFrameInfo caller{"Sample", "caller", "Sample.hx", 10};
static const StackFrameInfo callee{"Sample", "callee", "Sample.hx", 20};

int main() {
  static_assert(!std::is_copy_constructible_v<StackFrame>);
  static_assert(!std::is_move_constructible_v<StackFrame>);
  StackState first;
  StackState second;
  require(first.capture().empty(), "new stack is not empty");
  require(first.exceptionSnapshot().empty(), "new context retained an exception origin");
  std::vector<StackFrameValue> captured;
  {
    StackFrame outer(first, caller);
    require(second.capture().empty(), "independent stack contexts leaked frames");
    {
      StackFrame inner(first, callee);
      inner.setLine(27);
      captured = first.capture();
      first.replaceException(captured);
      require(captured.size() == 2, "capture lost nested frames");
      require(captured[0].method == "callee" && captured[0].line == 27,
              "capture lost the innermost source position");
      require(captured[1].method == "caller" && captured[1].line == 10,
              "capture reversed frame order");
      inner.setLine(28);
      require(captured[0].line == 27, "later source execution changed a snapshot");
    }
    require(first.capture().size() == 1, "ordinary scope exit retained a frame");
    try {
      StackFrame inner(first, callee);
      throw std::runtime_error("unwind");
    } catch (const std::runtime_error&) {
      require(first.capture().size() == 1, "unwinding retained a dead frame");
    }
  }
  require(first.capture().empty(), "caller scope exit retained a frame");
  require(captured[0].method == "callee" && captured[1].method == "caller",
          "snapshot borrowed expired frames");
  const auto firstOrigin = first.exceptionSnapshot();
  require(firstOrigin[0].line == 27 && second.exceptionSnapshot().empty(),
          "exception origin changed during unwind or leaked between contexts");
  first.replaceException({StackFrameValue{"Later", "rethrow", "Later.hx", 42}});
  require(first.exceptionSnapshot().size() == 1 && first.exceptionSnapshot()[0].line == 42
          && firstOrigin.size() == 2 && firstOrigin[0].line == 27,
          "new exception origin changed a retained snapshot");

  std::vector<StackFrameValue> ownedText;
  {
    const std::string temporaryName = "temporary";
    const StackFrameInfo temporary{"Temporary", temporaryName.c_str(), "temporary.hx", 1};
    StackFrame frame(first, temporary);
    ownedText = first.capture();
    const StackFrameInfo invalid{nullptr, "invalid", "invalid.hx", 0};
    bool rejected = false;
    try { StackFrame bad(first, invalid); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected && first.capture().size() == 1,
            "failed frame entry changed the existing stack");
  }
  require(ownedText[0].method == "temporary", "snapshot borrowed expired metadata text");

  Heap heap(0);
  {
    Root<Ref<StackSnapshotPayload>> snapshot(heap);
    heap.allocateInto(snapshot, captured);
    Root<Value> erased(heap, Value::managed(snapshot.get()));
    snapshot.set({});
    captured[0].method = "changed";
    heap.collect();
    auto restored = erased.get().asManaged().as<StackSnapshotPayload>();
    require(restored->frames()[0].method == "callee", "payload retained mutable input storage");
    require(restored->frames()[0].line == 27, "collection changed the saved origin");
    bool rejected = false;
    try { erased.get().asManaged().as<ArrayPayload>(); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected, "snapshot was accepted as an unrelated physical layout");
    // Another collecting allocation must not replace an already captured origin.
    Root<Ref<StackSnapshotPayload>> later(heap);
    heap.allocateInto(later, first.capture());
    require(later.get()->frames().empty() && restored->frames().size() == 2,
            "later capture replaced the saved origin");
  }
  heap.collect();
  require(heap.liveCount() == 0 && heap.rootCount() == 0,
          "released snapshots retained native allocations or roots");
  std::cout << "CPP_MANAGED_STACK:PASS\n";
}
