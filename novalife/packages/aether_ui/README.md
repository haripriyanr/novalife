# Aether UI

A pure Flutter, zero-dependency, object-oriented responsive design system and component catalog.

## Architectural Principles

1. **Zero External Dependencies**: Built strictly using Flutter SDK primitives (`dart:ui`, `package:flutter/widgets.dart`, `package:flutter/material.dart`).
2. **Domain Agnostic**: 100% neutral naming conventions (`Aether*`). Zero domain-specific or application-specific leakage.
3. **Dual-Theme Token System**: Mathematically verified WCAG AA contrast compliance across comprehensive Light and Dark palettes.
4. **Universal Responsiveness**: Adaptive layouts supporting mobile (phone: $\le 600$px), tablet ($601 - 1024$px), and desktop/wide web ($\ge 1025$px).

## Package Structure

- `lib/aether_ui.dart`: Public barrel export.
- `lib/src/theme/`: Semantic tokens, typography, spacing, shadows, and theme scope.
- `lib/src/responsive/`: Breakpoint enums, query utilities, and responsive builders.
- `lib/src/components/`: Layout, input, display, and feedback widget catalog.
- `lib/src/utils/`: Contrast evaluators and `BuildContext` extensions.
