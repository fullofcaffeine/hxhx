# Ordinary instance dispatch

This program checks direct calls, overrides through base references, inherited
methods that call an override, explicit `super` calls, sibling classes, receiver
identity after mutation, and receiver-before-argument evaluation. Each assertion
must pass. Successful execution writes no output.

An override allocates another subclass and returns it through a base reference.
The compiler must discover that allocation before it finalizes method targets.
An unused generic subclass must not require a native layout merely because it
is loaded. Another call keeps a temporary receiver alive while its argument
allocates an object.

```sh
haxe -cp test/oracle/cpp_instance_dispatch_seed -main Main --interp
npm run test:m14:cpp-instance-dispatch
```

The first command is the upstream Haxe reference. The second checks dispatch
ownership, types the same source, builds a native managed C++ program, and runs
it. The constructor test chain includes this command.

The native observer collects before every allocation and checks that temporary
roots and objects disappear after execution. It runs with AddressSanitizer and
UndefinedBehaviorSanitizer at `-O0` and `-O2`. Each observer compilation has a
60-second limit; each execution has a 30-second limit. The plan test rejects
foreign calls, changed source and projected bodies, and allocations discovered
after the target list was finalized. Editing a returned list cannot change the
plan.

The program defines every nominal class it uses. It does not substitute an
exception provider or claim exception, generic-method, interface, or stored
method-value support. Those remain separate requirements of the complete target.
README Goals readiness remains unchanged.
