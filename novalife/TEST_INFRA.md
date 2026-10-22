# TEST_INFRA.md — Testing Infrastructure & Opaque-Box E2E Test Suite Specification

> **Project**: NovaLife Modernization & Aether UI Design System  
> **Workspace**: `/run/media/user/DATA/repos/embedded_proj`  
> **Author**: E2E Test Writer (`test_writer_e2e`)  
> **Date**: 2026-10-27  
> **Status**: ACTIVE & VERIFIED (95/95 E2E Tests Pass, 147/147 Full Suite Pass)

---

## 1. Overview & Testing Philosophy

The NovaLife Aether UI modernization mandates an **authoritative, requirement-driven opaque-box testing strategy**. The testing infrastructure treats components, theming tokens, responsive layouts, and clinical workflows as black-box systems verified strictly against their externally observable behavior, contracts, and WCAG AA accessibility standards.

### Core Testing Tenets:
1. **Opaque-Box Verification**: Tests validate user-visible behaviors, layout adaptations, public API contracts, and state transformations without coupling to internal private implementation details.
2. **Zero Third-Party UI Dependency**: All component contracts, visual renderers, and test harnesses rely strictly on the pure Flutter SDK foundation (`flutter: sdk: flutter`).
3. **Four-Tier Comprehensive Hierarchy**:
   - **Tier 1 — Feature Coverage**: Comprehensive baseline tests ($\ge 5$ tests per feature) exercising primary happy paths, visual variants, and state transitions.
   - **Tier 2 — Boundary & Corner Cases**: Extreme viewports (320px to 1920px), boundary cutoffs (600px/601px, 1024px/1025px), WCAG AA mathematical contrast ratios, empty/extreme inputs, rapid toggling stress, and static zero-hardcoded-color auditing.
   - **Tier 3 — Cross-Feature Combinations**: Pairwise integration matrix testing simultaneous theme switching with responsive resizing, navigation state transitions with content split views, and dialog overlays with runtime theme inheritance.
   - **Tier 4 — Real-World Clinical Workflows**: End-to-end multi-role scenarios for Patient, Doctor, and Lab Tech roles, cloud job queue verification of FPGA PL Enclave watermarking (119 PL cycles), and role-based security isolation.
4. **Preservation Guarantee**: 100% preservation of all clinical database models, Supabase Cloud Job Queue endpoints, and existing unit/widget test suites (52/52 baseline tests intact).

---

## 2. Directory Layout & File Inventory

```
novalife_app/
├── test/
│   ├── e2e_aether_ui_test.dart            # Primary 4-Tier E2E Opaque-Box Test Suite (95 tests)
│   ├── helpers/
│   │   └── aether_test_harness.dart       # Contract definitions, mocks & ColorAuditScanner
│   ├── e2e_three_roles_test.dart          # Multi-role API workflow tests (4 tests)
│   ├── widget_test.dart                   # ThemeService & context extension tests (10 tests)
│   ├── gateway_client_test.dart           # Gateway client protocol tests (3 tests)
│   ├── hub_jobs_service_test.dart         # Cloud job queue parsing tests (3 tests)
│   ├── no_silent_fallback_test.dart       # Data integrity & fail-loud tests (5 tests)
│   ├── password_policy_test.dart          # Clinical password complexity tests (10 tests)
│   ├── phase08_hub_api_test.dart          # REST API contracts & JSON mapping (11 tests)
│   └── session_service_test.dart          # Session management & user roles (6 tests)
```

---

## 3. Test Tier Breakdown & Test ID Catalog

The test suite in `novalife_app/test/e2e_aether_ui_test.dart` comprises **95 automated tests** distributed across 4 tiers:

### Tier 1: Feature Coverage (50 Tests)
| Feature Group | Test IDs | Count | Scope & Behaviors Tested |
|---|---|---|---|
| **1.1 Theme Tokens** | T1.1.1 – T1.1.5 | 5 | Light tokens, Dark tokens, Semantic quads (`base`, `container`, `onBase`, `onContainer`), Typography scale (12 styles), Spacing/Radii/Shadows. |
| **1.2 Responsive Breakpoints** | T1.2.1 – T1.2.5 | 5 | Mobile ($\le 600$px), Tablet ($601-1024$px), Desktop ($\ge 1025$px), `AetherResponsive.value<T>`, `AetherResponsiveBuilder` local constraints. |
| **1.3 Adaptive Navigation** | T1.3.1 – T1.3.5 | 5 | Mobile bottom navigation bar, Tablet navigation rail, Desktop sidebar, `onIndexChanged` callback, `AetherResponsiveScaffold` integration. |
| **1.4 Input Fields** | T1.4.1 – T1.4.5 | 5 | Label/hint/input text, password reveal toggle (`obscureText`), error state, custom prefix/suffix icons, disabled state. |
| **1.5 Search Input** | T1.5.1 – T1.5.5 | 5 | Search prefix/placeholder, debounced `onChanged` timing, clear button, `onSubmitted` trigger, `onFilterTap` action. |
| **1.6 Buttons** | T1.6.1 – T1.6.5 | 5 | Primary button tap, secondary/outline variants, danger variant, loading spinner disables click, disabled state with null callback. |
| **1.7 Status Badges** | T1.7.1 – T1.7.5 | 5 | 5 semantic statuses (`success`, `danger`, `warning`, `info`, `neutral`), subtle container style, solid style, outline style, status dot & icon. |
| **1.8 Metric Tiles** | T1.8.1 – T1.8.5 | 5 | Label/value/unit rendering, positive trend indicator, negative trend indicator, leading metric icon, `onTap` interaction. |
| **1.9 Dialogs & Overlays** | T1.9.1 – T1.9.5 | 5 | Adaptive dialog title/content/actions, mobile bottom sheet delegation, desktop centered modal, bottom sheet drag handle, toast banner dismiss. |
| **1.10 Image Viewers** | T1.10.1 – T1.10.5 | 5 | `InteractiveViewer` integration, programmatic zoom in (`scaleByDouble`), programmatic zoom out, reset to identity, double-tap focal zoom. |

### Tier 2: Boundary & Corner Cases (26 Tests)
| Domain | Test IDs | Count | Boundary Conditions Tested |
|---|---|---|---|
| **2.1 Extreme Screen Sizes** | T2.1.1 – T2.1.6 | 6 | 320px mobile min (zero overflow, $\ge 48$px touch target), 600px mobile edge, 601px tablet edge, 1024px tablet edge, 1025px desktop edge, 1920px wide web (`kMaxContentWidth` containment). |
| **2.2 WCAG AA Contrast** | T2.2.1 – T2.2.5 | 5 | Light `textPrimary` on `background` ($>15:1$), Dark `textPrimary` on `background` ($>15:1$), `textSecondary` on `surface` ($\ge 4.5:1$), semantic containers ($\ge 7.0:1$), ITU-R BT.709 relative luminance math. |
| **2.3 Empty & Extreme Inputs** | T2.3.1 – T2.3.5 | 5 | Null label/empty input, 10,000 character string stress, rapid empty search clear, ultra-long button text wrapping/ellipsizing, empty fields in data cards. |
| **2.4 Rapid Toggling Stress** | T2.4.1 – T2.4.5 | 5 | Rapid theme toggling (Light/Dark $\times 6$), rapid navigation index cycling ($0 \rightarrow 1 \rightarrow 2 \rightarrow 0$), rapid password reveal toggle ($\times 8$), rapid search typing/clearing, rapid dialog open/close. |
| **2.5 Static Color Audit** | T2.5.1 – T2.5.5 | 5 | `ColorAuditScanner` regex detection of legacy `Colors.*` and `Color(0x...)`, clean token pattern verification, `lib/screens` legacy catalog scanner for M4 gating, non-null token palettes, unmounted theme fallback. |

### Tier 3: Cross-Feature Combinations (9 Tests)
| Pairwise Matrix | Test IDs | Count | Integration Behavior Tested |
|---|---|---|---|
| **3.1 Theming + Viewport Resize** | T3.1.1 – T3.1.3 | 3 | Light $\rightarrow$ Dark transition while resizing Mobile ($360$px) $\rightarrow$ Desktop ($1440$px); Dark $\rightarrow$ Light transition while resizing Desktop ($1280$px) $\rightarrow$ Tablet ($768$px); rapid multi-size viewport resize with alternating themes. |
| **3.2 Navigation + Content Split** | T3.2.1 – T3.2.3 | 3 | Tablet/Desktop tab switch preserving dual-pane split view state; Mobile drilldown to detail pane with `onBackToMaster` return; empty detail placeholder on master list. |
| **3.3 Dialog Overlays + Theme** | T3.3.1 – T3.3.3 | 3 | Modal dialog inheriting runtime Dark theme change; bottom sheet elevated surface theming; toast banner semantic status rendering under Dark theme. |

### Tier 4: Real-World Clinical Workflows (10 Tests)
| Workflow | Test IDs | Count | Clinical Flow & Verification |
|---|---|---|---|
| **4.1 Patient Role Workflow** | T4.1.1 – T4.1.2 | 2 | Patient login (`patient_001`), ABHA verification (`12345678901234`), personal diagnostic report review, authenticated scan share trigger. |
| **4.2 Doctor Role Workflow** | T4.2.1 – T4.2.2 | 2 | Doctor login (`doctor_001`), patient vault search, imaging stego payload inspection ($1024$ bytes), clinical diagnostic note entry and persistence. |
| **4.3 Lab Tech Role Workflow** | T4.3.1 – T4.3.2 | 2 | Lab Tech login (`lab_tech_001`), patient directory access, scan upload interface with 128-bit FPGA PL hardware watermark toggle. |
| **4.4 FPGA Hardware Pipeline** | T4.4.1 – T4.4.2 | 2 | Cloud job queue verification of Zynq-7010 PL Enclave cycle count ($119$ cycles, verdict `pass`), audit card rendering for `pass`, `revoked`, and `fail` states. |
| **4.5 Multi-Role Security** | T4.5.1 – T4.5.2 | 2 | Cross-role credential rejection with HTTP 401 across all 3 roles, non-existent patient query returning HTTP 404 without leaking patient metadata. |

---

## 4. Execution Commands & Runner Configuration

### 4.1 Running the Opaque-Box E2E Test Suite Alone
```bash
cd /run/media/user/DATA/repos/embedded_proj/novalife_app
flutter test test/e2e_aether_ui_test.dart
```

### 4.2 Running Specific Test Tiers
```bash
# Tier 1 only
flutter test test/e2e_aether_ui_test.dart --name "Tier 1"

# Tier 2 only
flutter test test/e2e_aether_ui_test.dart --name "Tier 2"

# Tier 3 only
flutter test test/e2e_aether_ui_test.dart --name "Tier 3"

# Tier 4 only
flutter test test/e2e_aether_ui_test.dart --name "Tier 4"
```

### 4.3 Running the Full Monorepo Test Suite (147 Tests)
```bash
cd /run/media/user/DATA/repos/embedded_proj/novalife_app
flutter test
```

### 4.4 Running Static Analysis
```bash
cd /run/media/user/DATA/repos/embedded_proj/novalife_app
flutter analyze
```

---

## 5. Traceability Matrix

| Requirement | Feature | Covered By Test IDs | Status |
|---|---|---|---|
| **R1. Package Architecture** | F01, F08 | T1.1.1 – T1.1.5, T2.5.4, T2.5.5 | **PASS** |
| **R1. Taxonomy: Layout** | F04 | T1.3.1 – T1.3.5, T3.2.1 – T3.2.3 | **PASS** |
| **R1. Taxonomy: Inputs** | F05 | T1.4.1 – T1.4.5, T1.5.1 – T1.5.5, T1.6.1 – T1.6.5, T4.3.2 | **PASS** |
| **R1. Taxonomy: Display** | F06 | T1.7.1 – T1.7.5, T1.8.1 – T1.8.5, T2.3.5, T4.4.2 | **PASS** |
| **R1. Taxonomy: Feedback** | F07 | T1.9.1 – T1.9.5, T1.10.1 – T1.10.5, T3.3.1 – T3.3.3 | **PASS** |
| **R2. Universal Responsiveness** | F03 | T1.2.1 – T1.2.5, T2.1.1 – T2.1.6, T3.1.1 – T3.1.3 | **PASS** |
| **R3. Dual-Theme Tokens** | F02 | T1.1.1 – T1.1.3, T2.4.1, T3.1.1 – T3.1.2 | **PASS** |
| **R3. WCAG AA Contrast** | F02 | T2.2.1 – T2.2.5 | **PASS** |
| **R3. Zero Hardcoded Colors** | F02 | T2.5.1 – T2.5.3 | **PASS** |
| **R4. Client Screen Workflows** | F11–F14 | T4.1.1 – T4.5.2 | **PASS** |
| **R4. FPGA / Cloud Preservation** | F14 | T4.3.2, T4.4.1, T4.4.2 | **PASS** |
