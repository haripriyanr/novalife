# Project: Aether UI Design System & NovaLife App Modernization

## Architecture
- **Monorepo Structure**:
  - `packages/aether_ui/`: Independent, zero-external-dependency Flutter package providing OOP design system, dual-theme tokens, universal responsive layout abstractions, and 18 production-ready UI components.
  - `novalife_app/`: Clinical cross-platform application consuming `aether_ui` via local path dependency (`path: ../packages/aether_ui`).
  - `novalife_hub/`: Zynq-7010 FPGA PL Enclave hardware algorithms, FreeRTOS C firmware, and Python verification oracles.
  - `supabase/`: PostgreSQL schema and Cloud Job Queue (`hub_jobs`) supporting asynchronous hardware watermarking and verification.
- **Data Flow & Theming**:
  - `ThemeService` in `novalife_app` bridges user theme preference (System, Light, Dark) into `AetherThemeData`.
  - `AetherTheme` acts as the root InheritedWidget providing semantic color tokens (`AetherColors`), typography (`AetherTypography`), spacing, radii, and shadows to all subtree widgets.
  - Components query visual attributes strictly from `context.aetherColors` and `context.aetherTypography`. Zero hardcoded color literals.
- **Responsiveness Flow**:
  - `AetherResponsive` and `AetherResponsiveBuilder` evaluate layout constraints against 3 breakpoints: Mobile ($\le 600$px), Tablet ($601 - 1024$px), Desktop ($\ge 1025$px).
  - Scaffold automatically selects navigation chrome: Mobile Bottom Bar, Tablet Navigation Rail, Desktop Navigation Sidebar.
  - Split views render master-detail inline on desktop/tablet and single-pane drilldown on mobile.
- **Clinical & Hardware Preservation Contract**:
  - All Supabase DB operations (`hub_patients`, `hub_reports`, `hub_doctor_notes`, `hub_identity_links`), Cloud Job Queue (`HubJobsService.submitVerifyImage`, `submitMarkImage`), FPGA PL Enclave cycle counts, and native scan sharing (`ScanShareService`) remain 100% preserved.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F01 | Zero-Dependency Package Scaffolding | `packages/aether_ui/pubspec.yaml`, `analysis_options.yaml`, directory layout, generic naming | M1 | Survey |
| F02 | Dual-Theme Semantic Tokens | `AetherTheme`, `AetherColors` (Light/Dark), `AetherTypography`, `AetherSpacing`, `AetherRadii`, `AetherShadows`, WCAG AA `ContrastChecker` | M1 | Survey |
| F03 | 3-Tier Responsive Framework | `AetherBreakpoint`, `AetherResponsive`, `AetherResponsiveBuilder`, mobile/tablet/desktop cutoffs | M1 | Survey |
| F04 | Layout & Structure Components | `AetherResponsiveScaffold`, `AetherAdaptiveNavigation`, `AetherHeaderBar`, `AetherSectionCard`, `AetherSplitView` | M2 | Survey |
| F05 | Inputs & Controls Components | `AetherTextField`, `AetherSearchInput`, `AetherChoiceChipGroup`, `AetherButton` (5 variants, hover/focus), `AetherSwitchTile` | M2 | Survey |
| F06 | Data Display & Status Components | `AetherDataCard`, `AetherStatusBadge` (5 semantic states), `AetherMetricTile`, `AetherAvatarBadge` | M2 | Survey |
| F07 | Feedback & Overlays Components | `AetherAdaptiveDialog`, `AetherBottomSheet`, `AetherImageViewer` (interactive zoom/pan/actions), `AetherToastBanner` | M2 | Survey |
| F08 | Public Barrel & Extensions | `lib/aether_ui.dart` export, `BuildContext` extensions, accessibility semantics | M2 | Survey |
| F09 | `aether_ui` Unit & Widget Tests | Test suite in `packages/aether_ui/test/` covering tokens, contrast, responsiveness, and components | M2 | Survey |
| F10 | Host Dependency & Theme Bridge | Configure `path: ../packages/aether_ui` in `novalife_app/pubspec.yaml`, bridge `ThemeService` to `AetherTheme` | M3 | Survey |
| F11 | Auth Screens Refactoring | Refactor `login_screen.dart`, `signup_screen.dart`, `magic_link_screen.dart`, `verify_email_screen.dart` | M3 | Survey |
| F12 | Shell & Profile Refactoring | Refactor `home_screen.dart` (adaptive navigation rail/sidebar/bottom bar), `profile_screen.dart` | M3 | Survey |
| F13 | Records & Search Refactoring | Refactor `patient_records_screen.dart`, `doctor_search_screen.dart`, `report_list_screen.dart`, `patient_list_screen.dart` | M4 | Survey |
| F14 | Diagnostic & Imaging Refactoring | Refactor `report_detail_screen.dart`, `scan_verify_screen.dart`, `ehr_upload_screen.dart`, `ehr_screen.dart` with 100% preserved FPGA/Cloud queue | M4 | Survey |
| F15 | Opaque-Box E2E Test Suite | Design Tiers 1-4 test suite, test runner, publish `TEST_READY.md` | E2E Track | Survey |
| F16 | Final Integration & Build Validation | Pass 100% E2E tests, `flutter analyze` 0 issues, `flutter test`, `flutter build linux`, `flutter build apk --debug` | M5 | Survey |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| E2E | E2E Testing Track | Requirement-driven opaque-box test suite (Tiers 1-4), runner, publish `TEST_READY.md` | None | DONE |
| M1 | `aether_ui` Core & Design Tokens | Package scaffolding, `AetherColors` (Light/Dark), `AetherTypography`, `AetherSpacing`, `AetherRadii`, `AetherShadows`, `ContrastChecker`, `AetherBreakpoint`, `AetherResponsive`, `AetherResponsiveBuilder`, `AetherTheme` scope, unit tests | None | DONE |
| M2 | `aether_ui` 18 Component Catalog | Implement 18 components (Layout, Inputs, Display, Feedback), public export barrel `lib/aether_ui.dart`, comprehensive widget tests | M1 | IN_PROGRESS |
| M3 | Host Integration & Screens Phase A | `pubspec.yaml` path dependency, `ThemeService` root bridge, refactor Auth screens (`login`, `signup`, `magic_link`, `verify_email`), Shell (`home_screen` adaptive nav), and `profile_screen` | M2 | PLANNED |
| M4 | Screens Phase B (Clinical & Diagnostic) | Refactor `patient_records`, `doctor_search`, `report_list`, `report_detail`, `scan_verify`, `ehr_upload`, `ehr_screen`, `patient_list`. Full FPGA/Cloud queue preservation. Zero hardcoded colors. | M3 | PLANNED |
| M5 | Final E2E Pass & Build Verification | Pass 100% of E2E test suite (`TEST_READY.md`), pass `flutter analyze` across both packages, run `flutter build linux` and `flutter build apk --debug` | M4, E2E | PLANNED |

---

## Interface Contracts

### `aether_ui` ↔ `novalife_app`
- **Import**: `import 'package:aether_ui/aether_ui.dart';`
- **Theming**:
  - `AetherTheme` wraps the application root in `novalife_app/lib/main.dart`:
    ```dart
    AetherTheme(
      data: themeService.isDarkMode ? AetherThemeData.dark() : AetherThemeData.light(),
      child: MaterialApp(...),
    )
    ```
  - In screens and widgets:
    ```dart
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    ```
- **Responsiveness**:
  - `AetherResponsive.of(context)` returns `AetherBreakpoint.mobile`, `tablet`, or `desktop`.
  - `AetherResponsive.value<T>(context, mobile: ..., tablet: ..., desktop: ...)` selects responsive values.
  - `AetherResponsiveBuilder(builder: (context, breakpoint, constraints) => ...)` adapts nested widgets.
- **Layout Widgets**:
  - `AetherResponsiveScaffold(body: ..., header: ..., navigationItems: ..., currentIndex: ..., onNavigationChanged: ...)`
  - `AetherSplitView(master: ..., detail: ..., masterRatio: 0.35, showDetailOnMobile: ...)`
  - `AetherSectionCard(title: ..., subtitle: ..., child: ..., footer: ...)`
  - `AetherHeaderBar(titleText: ..., actions: ..., searchSlot: ...)`
- **Input Widgets**:
  - `AetherTextField(controller: ..., label: ..., hintText: ..., errorText: ..., isPassword: ..., onChanged: ...)`
  - `AetherSearchInput(controller: ..., hintText: ..., onChanged: ..., onClear: ...)`
  - `AetherChoiceChipGroup<T>(options: ..., selectedValue: ..., onSelected: ...)`
  - `AetherButton(label: ..., variant: AetherButtonVariant.primary, icon: ..., onPressed: ...)`
  - `AetherSwitchTile(title: ..., value: ..., onChanged: ...)`
- **Display & Feedback Widgets**:
  - `AetherDataCard(title: ..., subtitle: ..., leading: ..., trailing: ..., onTap: ...)`
  - `AetherStatusBadge(label: ..., variant: AetherStatusVariant.success)`
  - `AetherMetricTile(label: ..., value: ..., unit: ..., icon: ...)`
  - `AetherAvatarBadge(name: ..., imageUrl: ..., size: ...)`
  - `AetherImageViewer(imageBytes: ..., enableZoom: true, actions: ...)`
  - `AetherAdaptiveDialog(title: ..., content: ..., actions: ...)`
  - `AetherBottomSheet(title: ..., child: ...)`
  - `AetherToastBanner(message: ..., variant: AetherStatusVariant.danger)`

### Error Handling & Backwards Compatibility
- `AetherTheme.of(context)` includes safe fallback to `Theme.of(context).brightness` if unmounted.
- All existing Supabase exceptions (`HubJobsException`, `HubDataException`, `AuthException`) and error states are displayed via `AetherToastBanner` or semantic error cards without altering exception propagation.

---

## Code Layout
- `packages/aether_ui/`:
  - `pubspec.yaml`
  - `analysis_options.yaml`
  - `lib/aether_ui.dart`
  - `lib/src/theme/`: `aether_theme.dart`, `aether_colors.dart`, `aether_typography.dart`, `aether_spacing.dart`, `aether_radii.dart`, `aether_shadows.dart`
  - `lib/src/responsive/`: `aether_breakpoint.dart`, `aether_responsive.dart`, `aether_responsive_builder.dart`
  - `lib/src/components/layout/`: `aether_responsive_scaffold.dart`, `aether_adaptive_navigation.dart`, `aether_header_bar.dart`, `aether_section_card.dart`, `aether_split_view.dart`
  - `lib/src/components/inputs/`: `aether_text_field.dart`, `aether_search_input.dart`, `aether_choice_chip_group.dart`, `aether_button.dart`, `aether_switch_tile.dart`
  - `lib/src/components/display/`: `aether_data_card.dart`, `aether_status_badge.dart`, `aether_metric_tile.dart`, `aether_avatar_badge.dart`
  - `lib/src/components/feedback/`: `aether_adaptive_dialog.dart`, `aether_bottom_sheet.dart`, `aether_image_viewer.dart`, `aether_toast_banner.dart`
  - `lib/src/utils/`: `contrast_checker.dart`, `extensions.dart`
  - `test/`: Theme, responsive, and component unit/widget test suites.
- `novalife_app/lib/screens/`:
  - `login_screen.dart`, `signup_screen.dart`, `magic_link_screen.dart`, `verify_email_screen.dart`
  - `home_screen.dart`, `profile_screen.dart`
  - `patient_records_screen.dart`, `doctor_search_screen.dart`, `report_list_screen.dart`, `patient_list_screen.dart`
  - `report_detail_screen.dart`, `scan_verify_screen.dart`, `ehr_upload_screen.dart`, `ehr_screen.dart`
- `novalife_app/test/`:
  - Existing 52 tests maintained intact.
  - `test/e2e_aether_ui_test.dart`: Opaque-box E2E test suite from E2E Testing Track.
