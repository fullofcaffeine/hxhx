# HXHX C++ Native Target Boundary

Status: first Stage3 target-core seam, not production-ready C++/hxcpp parity.

## Purpose

`--cpp` is part of the Full1 extended target matrix. After the Neko helper-tool
burn-down, focused Cpp evidence now reaches actual Stage3 C++ target dispatch.

This document defines the first honest boundary for that dispatch:

- `cpp-native` is a real builtin backend registration.
- The implementation starts as a small C++ source-emission MVP.
- Unsupported Haxe semantics must fail with C++-specific diagnostics instead of
  falling back to a generic "backend not implemented" placeholder.

## What Works Today

The current target core can emit and optionally build a tiny static `main`
program that uses:

- literal strings, integers, floats, booleans, and `null`,
- local variables,
- `Sys.println(...)`,
- `Std.string(...)`,
- simple binary operators,
- string concatenation for supported literal/local shapes.

The focused local smoke is:

```bash
npm run test:m14:cpp-native-backend-smoke
```

If a C++ compiler is available on `PATH` (`c++`, `g++`, or `clang++`), the smoke
also builds and runs the generated executable.

## What Is Not Ready

This is not a hxcpp replacement yet. In particular, it does not yet implement:

- hxcpp runtime layout,
- generated class/module layout compatible with upstream hxcpp,
- reflection, dynamic values, arrays, maps, enums, abstracts, exceptions, or
  target stdlib coverage beyond the tiny smoke subset,
- upstream `tests/unit` Cpp parity.

The Full1 Cpp gate remains failing until the upstream-derived Cpp lane passes or
the release scope is explicitly narrowed and reviewed.

## Growth Rule

Grow this target by CI-discovered seams:

1. Add a focused repo-local regression for the next unsupported C++ shape.
2. Implement only the smallest honest behavior slice.
3. Rerun focused `Gate 3 Full1 / Extended Targets Strict` with `targets=Cpp`.
4. Record the next blocker or the pass evidence in the owning bead.

Do not add large inline runtime stubs to unrelated shared emitters to satisfy one
Cpp failure. Target runtime/API surfaces should live behind C++ target-owned
modules or small templates.

## Class Reference Ownership Model

Current `cpp-native` class emission uses a source-MVP ownership model:

- `new SomeClass(...)` and generated `__hxhx_make_shared_*` factories return
  owning `std::shared_ptr<SomeClass>` handles.
- Class-typed fields, constructor arguments, method arguments, and return values
  use `std::shared_ptr<T>` handles so helper/runtime classes have one consistent
  reference shape.
- Passing the current receiver (`this`) to another helper constructor uses
  `__hxhx_borrowed_shared<T>(this)`. This is a non-owning `shared_ptr` handle
  with a no-op deleter, valid only for immediate helper/runtime aliasing where
  the receiver outlives the borrowed call path. It must not be used as a general
  lifetime-extension mechanism.
- Primitive values, strings, arrays/vectors, and primitive-backed abstracts keep
  value semantics unless a target runtime API explicitly requires a handle.
- Target runtime wrappers such as `Any`, `EnumValue`, iterators, event-loop
  helpers, and Cpp-specific extern support live in C++ target-owned runtime
  support, not in shared emitters or broad fake generated classes.

If a future Cpp gate needs persistent aliasing, cyclic object graphs, hxcpp ABI
layout, or ownership transfer across runtime queues, file a dedicated follow-up
instead of expanding the borrowed receiver helper.
