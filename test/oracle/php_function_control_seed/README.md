# PHP function control

This fixture checks that a nested function returns to its own caller and keeps
its local variables separate from other invocations and enclosing variables.
Sibling closures must observe updates to the same captured variable. A returned
closure must retain both its creator's local variable and a variable from the
outer function. An argument that shadows the outer variable must stay separate.
Two factory calls must create separate local storage. Loop iterations must also
create separate storage, while repeated calls to one closure share its updates.

The final case returns the String type value from a nested function. This
combines function-body emission with the existing exact runtime-type operand
validation.

FieldClosures also checks static and instance field initializers, receiver
capture in a constructor, and a captured method parameter. Ownership checks
reject copied, foreign, changed, and removed projected closures.

Run `npm run test:m14:php-function-control` from the repository root.
The test requires PHP. It compares the independently authored expected output
with upstream Haxe evaluation and generated native PHP execution. A compiler
rejection is a failing regression, not an accepted alternative.
The test also runs in `npm run test:m14:runtime-type-operands`.
