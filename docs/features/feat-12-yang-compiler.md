---
title: "Feature 12: YANG-to-JSON Build-Time Schema Compiler"
type: "feature"
interface_type: "config"
generation_mode: "subagent"
spec_source: "docs/designs/persistence-architecture-blueprint.md"
issue_id: 54
---

# Feature: YANG-to-JSON Build-Time Schema Compiler

## Parent Epic
- [ ] #[EpicID] - [Epic Title](https://github.com/gintatkinson/digital-pipeline-repo/blob/master/docs/epics/epic-XX-name.md) (semantic linkage justification)

## Description
Details the DevOps compilation pipeline parsing OpenConfig YANG schemas into platform-agnostic JSON schemas mapping types, lists, leaves, ranges, and patterns with absolute XPaths as keys.

## UML Class Diagram
```mermaid
classDiagram
    class AST
    class ASTNode
    class YangCompiler {
        +parseYangFile(filePath : String) AST [1]
        +walkAST(node : ASTNode) AttributeDefinition [0..*]
        +generateAbsoluteXPath(node : ASTNode) String [1]
        +mapYangType(yangType : String) String [1]
        +writeLuiJson(outputPath : String) Boolean [1]
    }
    class AttributeDefinition {
        +key : String [1]
        +label : String [1]
        +type : String [1]
        +sectionGroup : String [1]
        +options : String [0..*]
        +isRequired : Boolean [1]
        +regexPattern : String [0..1]
        +minValue : Real [0..1]
        +maxValue : Real [0..1]
    }
    YangCompiler --> AttributeDefinition : generates
    YangCompiler --> AST : uses
    YangCompiler --> ASTNode : uses
```

## Interface Requirements
### 1. Test Data Shape
The output JSON schema (`logical-layout.json`) is structured as a collection of AttributeDefinitions:
```json
{
  "attributes": [
    {
      "key": "interfaces/interface/state/mtu",
      "label": "Mtu",
      "type": "int",
      "sectionGroup": "interfaces/interface/state",
      "isRequired": false,
      "minValue": 68,
      "maxValue": 65535
    }
  ]
}
```

### 3. Logical Operations & Interface Messages
1. The DevOps CI/CD pipeline triggers the schema compiler script.
2. The script loads OpenConfig YANG schemas (`.yang` files).
3. The parser walks the YANG Abstract Syntax Tree (AST).
4. Container and list constructs are mapped to UI section groups.
5. Leaf constructs are mapped to data-bound form inputs, mapping type declarations, mandatory status, ranges, and patterns.
6. The absolute XPath is set as the unique identifier (`key`) for each mapped attribute.
7. The compiled platform-agnostic JSON layout is saved to disk for runtime consumption.

### 4. Interactive Flow & States
1. YANG Syntax Error: If the source `.yang` file contains semantic or syntactic errors, the compiler prints compilation diagnostics to stdout and exits with code 1, halting the build.
2. Duplicate XPath: If two leaves resolve to the same absolute XPath, the compiler flags a duplication exception and aborts.
