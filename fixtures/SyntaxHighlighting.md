# Code-block syntax highlighting

Reader colors follow the document theme. Inline code stays plain: `let value = 42`.

## Swift

```swift
// Unicode stays selectable: 中文 🙂
struct Greeting {
    let message: String = "Hello, Kasumi!"
    let count: Int = 42
    func show() { print(message) }
}
```

## Python

```py
# Aliased fence language; multiline strings keep their state.
def greet(name: str):
    message = """Hello,
中文 and emoji 🙂"""
    return f"{message}, {name}!"
```

## TypeScript

```ts
interface Reader { title: string; count: number }
const reader: Reader = { title: "Kasumi", count: 42 };
console.log(reader.title);
```

## Rust: multiline comments and wrapping

```rust
/* A comment that continues
   across two lines. */
let message: String = "A long string should keep its color when it wraps across several lines in a narrow reading column.";
let count: u32 = 12345;
```

## Plain fallback

```unknown-language
let value = "Unknown languages remain readable";
```

```
let value = "Unlabeled code stays plain";
```

## Derive common traits

```rust
#[derive(Debug, Clone, PartialEq)]
struct Point {
    x: i32,
    y: i32,
}

let point = Point { x: 1, y: 2 };
assert_eq!(point, point.clone());
println!("{point:?}");
```
