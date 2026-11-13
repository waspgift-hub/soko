# Phase 3 - Core Navigation and Architecture Consolidation

## Current State
- Navigation: GoRouter with 92 routes (lib/app/router.dart), routes defined in lib/app/routes.dart
- Bottom nav: Custom glass nav in lib/widgets/bottom_nav_bar.dart (MainScreen with IndexedStack)
- Screens: lib/screens/ (88), lib/screens_new/ (11), lib/ui/ (11) - multiple UI layers
- DS: lib/widgets/ds/ has components, lib/theme/design_tokens.dart has Ds facade
- Admin: 9 screens under lib/screens/admin/ with routes

## Consolidation Plan
1. **Navigation**: Keep GoRouter as single routing solution. Standardize navigation patterns (context.push/go) via extensions/utilities.
2. **Bottom Navigation**: Create DS-compliant bottom nav component using design tokens, maintain existing MainScreen structure to avoid breaking routes.
3. **Route Organization**: Keep existing route structure; add route grouping comments/docs.
4. **Architecture**: Document feature-based organization. Avoid mass file moves; consolidate via exports/re-exports.
5. **Admin/Staff**: Admin routes exist; staff console not separate - document role-based access pattern.

## Actions Taken
- Created DS barrel (lib/design_system/soko_vibe_ds.dart)
- Created DS showcase screen
- Documented architecture

## No Breaking Changes
- No routes modified
- No navigation logic changed
- All existing functionality preserved
