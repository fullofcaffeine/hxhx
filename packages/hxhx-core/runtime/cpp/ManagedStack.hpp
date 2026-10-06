#pragma once

#include "ManagedValue.hpp"

namespace hxhx::managed {

// Haxe emission owns these static-lifetime source records and chooses frame
// placement. Native code does not infer Haxe functions from machine symbols.
struct StackFrameInfo {
  const char* owner;
  const char* method;
  const char* file;
  std::int32_t line;
};

// A snapshot owns its text and position. It cannot borrow a native frame that
// will disappear during return or unwinding, nor follow later line updates.
struct StackFrameValue {
  std::string owner;
  std::string method;
  std::string file;
  std::int32_t line;
};

class StackFrame;

// One explicit synchronous execution context, with no process/thread singleton.
// The caller keeps it alive until all its frames leave. Separate contexts can
// run nested or on separate threads; sharing one concurrently is unsupported.
class StackState final {
  friend class StackFrame;
  const StackFrame* top_ = nullptr;
  std::vector<StackFrameValue> lastException_;
public:
  StackState() noexcept = default;
  StackState(const StackState&) = delete;
  StackState& operator=(const StackState&) = delete;
  ~StackState() noexcept { if (top_ != nullptr) std::terminate(); }
  std::vector<StackFrameValue> capture() const;
  // Haxe selects the throw boundary and supplies its completed snapshot.
  // Replacement cannot fail or mutate a snapshot already returned to a caller.
  void replaceException(std::vector<StackFrameValue> frames) noexcept {
    lastException_.swap(frames);
  }
  std::vector<StackFrameValue> exceptionSnapshot() const { return lastException_; }
};

// Address-stable, allocation-free frame registration. C++ scope unwinding only
// unlinks the frame; Haxe decides when a snapshot becomes an exception origin.
// The supplied metadata and its strings must outlive this frame.
class StackFrame final {
  friend class StackState;
  StackState& state_;
  const StackFrame* previous_;
  const StackFrameInfo& info_;
  std::int32_t line_;
public:
  StackFrame(StackState& state, const StackFrameInfo& info)
      : state_(state), previous_(state.top_), info_(info), line_(info.line) {
    if (info.owner == nullptr || info.method == nullptr || info.file == nullptr)
      throw std::invalid_argument("stack frame requires source metadata");
    state_.top_ = this;
  }
  StackFrame(const StackFrame&) = delete;
  StackFrame& operator=(const StackFrame&) = delete;
  StackFrame(StackFrame&&) = delete;
  StackFrame& operator=(StackFrame&&) = delete;
  ~StackFrame() noexcept {
    if (state_.top_ != this) std::terminate();
    state_.top_ = previous_;
  }
  void setLine(std::int32_t line) noexcept { line_ = line; }
};

inline std::vector<StackFrameValue> StackState::capture() const {
  std::vector<StackFrameValue> result;
  for (auto* frame = top_; frame != nullptr; frame = frame->previous_)
    result.push_back({frame->info_.owner, frame->info_.method, frame->info_.file, frame->line_});
  return result;
}

// Physical opaque storage for the selected native snapshot. The Haxe binding
// must check this layout before converting its contents to source StackItems.
// All text is owned and there are no managed graph edges or hidden roots.
class StackSnapshotPayload final {
  const std::vector<StackFrameValue> frames_;
public:
  explicit StackSnapshotPayload(std::vector<StackFrameValue> frames) : frames_(std::move(frames)) {}
  const std::vector<StackFrameValue>& frames() const noexcept { return frames_; }
};

template<> struct Trace<StackSnapshotPayload> {
  static void visit(const StackSnapshotPayload&, Visitor&) noexcept {}
};

}
