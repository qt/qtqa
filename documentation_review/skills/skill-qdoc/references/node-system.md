# Node System and Tree Architecture

## Node System: How QDoc Models Documentation

QDoc builds an in-memory **tree of nodes** representing every documentable entity.

### Node Hierarchy

```
INode (interface)
  └─ Node (base class)
       ├─ PageNode (generates output files)
       │    ├─ CollectionNode (Module, Group, QmlModule)
       │    ├─ ExampleNode
       │    └─ ExternalPageNode
       │
       └─ Aggregate (can have children)
            ├─ NamespaceNode
            ├─ ClassNode (class, struct, union)
            ├─ HeaderNode
            └─ QmlTypeNode
```

### Node Types by Category

| Category | Node Types |
|----------|------------|
| **C++** | Namespace, Class, Struct, Union, Function, Property, Variable, Enum, Typedef |
| **QML** | QmlType, QmlValueType, QmlProperty, QmlMethod, QmlSignal, QmlEnum, QmlModule |
| **Documentation** | Page, Example, ExternalPage, Group, Module |

### Genus System

QDoc classifies nodes by **genus** for targeted searches:
- `CPP` (0x1) - C++ entities
- `QML` (0x4) - QML entities
- `DOC` (0x8) - Documentation pages
- `API` (CPP|QML) - Any code entity
- `DontCare` (0x0) - Match anything

---

## Topic Commands Create Nodes

When QDoc encounters a topic command, it creates the corresponding node:

| Command | Node Created | Example |
|---------|--------------|---------|
| `\class` | ClassNode | `\class QWidget` |
| `\fn` | FunctionNode | `\fn void QWidget::show()` |
| `\enum` | EnumNode | `\enum Qt::AlignmentFlag` |
| `\property` | PropertyNode | `\property QWidget::visible` |
| `\qmltype` | QmlTypeNode | `\qmltype Rectangle` |
| `\qmlproperty` | QmlPropertyNode | `\qmlproperty int Item::width` |
| `\qmlmethod` | FunctionNode (QML) | `\qmlmethod void Item::update()` |
| `\qmlsignal` | FunctionNode (QML) | `\qmlsignal Item::clicked()` |
| `\page` | PageNode | `\page overview.html` |
| `\module` | CollectionNode | `\module QtCore` |
| `\group` | CollectionNode | `\group painting` |

**Critical**: Names must be **fully qualified**:
```cpp
// Correct
\fn void QGraphicsWidget::setWindowFlags(Qt::WindowFlags flags)

// Wrong - missing class prefix
\fn void setWindowFlags(Qt::WindowFlags flags)
```

### QML Method Return Types (IMPORTANT)

**`\qmlmethod` commands MUST include a return type** or the method won't be indexed:

```cpp
// CORRECT - will be indexed and linkable
\qmlmethod void TextToSpeech::say(string text)
\qmlmethod list<voice> TextToSpeech::availableVoices()

// WRONG - will NOT be indexed, links will fail
\qmlmethod TextToSpeech::say(string text)
```

**Root cause**: `cppcodeparser.cpp:726-742` parses `\qmlmethod` arguments by splitting on `::`.
The module name is only extracted when there are 3+ parts (return type + type + method).
Without a return type, the method is added to an orphan QmlTypeNode not linked to the module.

**Fix**: Add `void` for void-returning methods. This is the established Qt pattern used in
Qt3D, QtCharts, QtMultimedia, and other modules.

---

## Tree and Forest Architecture

### Single Module = One Tree

Each module builds a **Tree** with:
- `m_root` - Root NamespaceNode
- `m_nodesByTargetRef` - Targets indexed by anchor
- `m_nodesByTargetTitle` - Targets indexed by title
- `m_qmlTypeMap` - QML type lookup

### Multiple Modules = Forest

**QDocForest** manages multiple trees:
```
QDocDatabase (singleton)
└─ QDocForest
   ├─ Primary Tree (current module being documented)
   └─ Index Trees (loaded from .index files of dependencies)
```

When resolving links, QDoc searches trees in order until a match is found.

---

## Key Source Files

| File | Purpose |
|------|---------|
| `node.h/cpp` | Base Node class, type definitions |
| `aggregate.h/cpp` | Parent nodes with children |
| `tree.h/cpp` | Tree structure, target resolution |
| `qdocdatabase.h/cpp` | Forest management, resolution pipeline |
| `pagenode.h` | Documentation-generating nodes |
