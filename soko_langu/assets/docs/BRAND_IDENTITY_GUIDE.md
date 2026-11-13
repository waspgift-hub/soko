# SOKO VIBE - Brand Identity Guide

## Brand Overview
Soko Vibe is a Tanzanian digital commerce and social platform connecting buyers and sellers with trust, simplicity and innovation.

## Brand Personality
- Trust
- Innovation
- Simplicity
- Speed
- Intelligence
- Security
- Convenience
- Professionalism
- African identity with global ambition

## Logo
Primary: `assets/brand/logos/app_icon_full.png`
Icon: `assets/brand/logos/app_icon.png`
Foreground: `assets/brand/icons/ic_foreground.png`
Monochrome: `assets/brand/icons/ic_monochrome.png`

## Colors (Centralized)
Primary: #00C853
Brand Accent (Dark/Light): #00C853 / #009624
Canvas: #000000 (dark) / #FFFFFF (light)
Surface Subtle: #121212 (dark) / #F7F7F7 (light)
Surface Raised: #181818 (dark) / #FFFFFF (light)
Content Primary: #FFFFFF (dark) / #000000 (light)
Content Secondary: #A7A7A7 (dark) / #6B6B6B (light)

See `lib/theme/app_colors.dart` and `lib/theme/design_tokens.dart`.

## Typography
- Font families: Inter, Space Grotesk, JetBrains Mono (as configured in pubspec.yaml)
- Scale defined in `lib/theme/app_typography.dart`

## Components
Use design system widgets via `Ds` tokens and `widgets/ds/` components.

## Usage
- Never hardcode hex colors outside token files
- Use semantic tokens from ColorScheme/AppColorScheme
- Maintain light/dark parity
- Follow existing architecture and don't duplicate widgets
- All business logic unchanged by branding updates
