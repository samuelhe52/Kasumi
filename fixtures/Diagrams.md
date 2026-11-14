# Native diagrams

## Flowchart

```mermaid
flowchart LR
  A([Open a document]) --> B{Ready?}
  B -->|Yes| C[Read and annotate]
  B -->|No| D[(Load resources)]
  D --> B
```

## Sequence

```mermaid
sequenceDiagram
  participant R as Reader
  participant C as Core
  R->>+C: Lay out document
  Note over R,C: Native text and vector drawing
  alt Cached
    C-->>R: Reuse scene
  else Changed
    C-->>R: Rebuild scene
  end
  C-->>-R: Ready
```

## Pie

```mermaid
pie showData title Reading time
  "Books" : 45
  "Articles" : 35
  "Notes" : 20
```

## Mindmap

```mermaid
mindmap
  root((Reading))
    Documents
      Markdown
      Plain text
    Rendering
      Math
      Diagrams
```

## Tree

```mermaid
treeView-beta
  Library
    Books
      Chapter one
      Chapter two
    Notes
```

## State

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Reading: open
  Reading --> Idle: close
  Idle --> [*]
```

## Class

```mermaid
classDiagram
  class Document {
    +String title
    +open()
  }
  Document <|-- Markdown
```

## Entity relationships

```mermaid
erDiagram
  LIBRARY ||--o{ DOCUMENT : contains
  DOCUMENT {
    string title
    int pages
  }
```

## Unsupported syntax

```mermaid
gantt
  title A schedule
  dateFormat YYYY-MM-DD
  Task :2026-01-01, 1d
```

## Invalid syntax

```mermaid
graph LR
  A[
```
