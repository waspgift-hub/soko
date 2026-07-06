# Soko Vibe — Dart Comment Conventions

## Purpose
All code in this project follows these commenting rules. Comments exist to explain **why**, not **what** — the code itself should be self-documenting for the **what**.

## Rules

### 1. NO comments on trivial code
```dart
// BAD
setState(() {}); // call setState

// GOOD
setState(() {}); // rebuild after async callback completes
```

### 2. Document WHY, not WHAT
```dart
// BAD
final now = DateTime.now(); // get current time

// GOOD
final now = DateTime.now(); // use server timestamp to avoid clock skew
```

### 3. Public API docs required
Every public class, method, top-level function, and field must have a `///` doc comment only if its purpose is non-obvious from its signature.

```dart
/// Parses a TSh amount string like "TSh 5,000" into an int.
int parsePrice(String raw);
```

**Exceptions (no docs needed):**
- Simple getters/setters
- Overrides of parent methods (inherit docs)
- Widget build() methods
- Test method names that read as sentences

### 4. Formatting
- Use `///` for documentation comments (applies to declarations)
- Use `//` for inline/block comments (inside method bodies)
- Never use `/* */` block comments in Dart code (reserved for temporarily disabling code)
- One space after `//` and `///`
- 80-char max line length for comments (code can go to 100)

### 5. TODOs and FIXMEs
```dart
// TODO(username): extract magic number to constant
// FIXME: this query O(n) on large datasets
```

Every TODO/FIXME must:
- Have a ticket/issue reference if the fix is deferred
- Include the author's identifier

### 6. What to NEVER comment
- Closing braces (`} // end if`)
- Import statements (`// models`)
- Obvious parameter meanings in named parameters
- Self-explanatory code like `i++` (loop increment)

### 7. What MUST be commented
- **Security decisions**: why a particular approach was taken
  ```dart
  // SHA-256, not bcrypt, because PIN is low-entropy and we need fast local hash
  ```
- **Workarounds**: any non-obvious fix for a third-party bug
  ```dart
  // flutter_image_compress 0.4.0 ignores quality on Android — workaround with resize
  ```
- **Performance choices**: why O(n^2) was accepted or avoided
  ```dart
  // cached network image — n=5 banners, re-fetching every frame is wasteful
  ```
- **Business logic**: rules that came from product/legal requirements
  ```dart
  // Tanzania Communications Act 2023 requires 8+ char passwords
  ```

### 8. Translation-related comments
- Never comment `context.tr('key')` calls — the key name is the documentation
- Add a comment only when the translation has nuances:
  ```dart
  // 'ask_deletion' uses male-gendered noun in Swahili — confirmed with linguist
  ```

### 9. No commented-out code
Delete dead code. Do not leave commented-out blocks. Use version control history instead.

### 10. Migration/breaking-change comments
When changing an API, add a one-line comment at the old call site:
```dart
@Deprecated('Use AuthNotifier instead')
class LegacyAuthService {}
```

## Enforcement
- `flutter analyze` will catch `Deprecated` annotations, unused imports, and dead code
- Code review must reject any PR that violates rules 1, 6, or 9
- Rule 3 is enforced by review discretion — if a reader can't understand the public API without docs, add them
