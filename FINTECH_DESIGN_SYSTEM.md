# Premium FinTech Design System

## Overview

A complete premium fintech mobile app interface designed following modern design principles inspired by Revolut, N26, Nubank, Apple Wallet, and CashApp.

## Design System

### Color Palette

**Primary Scheme: Midnight Blue + Cyan**
- Primary: `#0A1628` (Midnight Blue)
- Accent: `#00D9FF` (Cyan)
- Gold Accents: `#FFD700` (for premium sections)

**Alternative Schemes Available:**
- Black + Electric Blue
- White + Navy

### Typography

- **Display (XL)**: 48px, 40px, 32px - Bold
- **Headings (L)**: 28px, 24px, 20px - Semi-bold
- **Body (M)**: 18px, 16px, 14px - Regular
- **Labels (S)**: 16px, 14px, 12px - Semi-bold

### Spacing System

8-point grid system:
- 4px, 8px, 12px, 16px, 20px, 24px, 32px, 40px, 48px, 64px

### Border Radius

- Small: 12px
- Medium: 16px
- Large: 20px
- XLarge: 24px
- Round: 999px

### Shadows

- Small: Subtle elevation
- Medium: Card elevation
- Large: Modal elevation
- XLarge: Maximum elevation

## Screen Structure

### Onboarding Flow

1. **Welcome Screen** (`lib/screens/onboarding/welcome_screen.dart`)
   - Premium hero image with gradient
   - Get Started button
   - Continue as Guest option
   - Sign Up / Login links

2. **Language Selection** (`lib/screens/onboarding/language_screen.dart`)
   - List of available languages
   - Visual selection with checkmarks

3. **Country Selection** (`lib/screens/onboarding/country_screen.dart`)
   - Searchable country list
   - Flag emojis for visual identification

### Main Navigation (4 Tabs)

1. **Home Dashboard** (`lib/screens/home_dashboard/`)
   - Total balance card (with visibility toggle)
   - Quick actions (Add Money, Withdraw, Transfer, Invest)
   - Wallet balances
   - Investments overview
   - Spending highlights

2. **Wallet** (`lib/screens/wallet/`)
   - Multi-currency wallet list
   - Exchange, Deposit, Withdraw actions
   - Currency cards with flags

3. **Activity** (`lib/screens/activity/`)
   - Transaction list
   - Filter chips (All, Income, Expense, Transfer, Investment)
   - Search functionality
   - Transaction details

4. **Profile** (`lib/screens/profile/`)
   - Profile header with avatar
   - Security settings (PIN, Biometric, 2FA)
   - Preferences (Dark Mode, Language, Linked Accounts)
   - Support (Help, About)
   - Logout

## Widgets

### Premium Components

- `PremiumButton`: Animated button with scale effect
- `BalanceCard`: Gradient card for displaying balance
- `QuickActionButton`: Circular icon button for quick actions
- `InfoCard`: Information card with icon and value
- `CurrencyCard`: Currency display with flag
- `TransactionItem`: Transaction list item
- `FilterChip`: Custom filter chip
- `ProfileHeader`: Profile header with gradient
- `SettingsItem`: Settings list item

## Localization

All strings are localized in:
- `lib/localization/en/fintech_strings.dart` (English)
- `lib/localization/ar/fintech_strings.dart` (Arabic)

## Usage

### To Use the New Design System:

1. Import the theme:
```dart
import 'theme/fintech_theme.dart';
```

2. Use colors:
```dart
Container(
  color: FintechTheme.primary,
  child: Text('Hello', style: FintechTheme.heading1),
)
```

3. Navigate to onboarding:
```dart
Navigator.pushNamed(context, '/onboarding/welcome');
```

4. Use the main tab scaffold:
```dart
Navigator.pushReplacementNamed(context, '/home');
// This will show FintechMainTabScaffold with 4 tabs
```

## File Structure

```
lib/
├── theme/
│   └── fintech_theme.dart          # Design system
├── localization/
│   ├── en/
│   │   └── fintech_strings.dart    # English strings
│   └── ar/
│       └── fintech_strings.dart    # Arabic strings
├── screens/
│   ├── onboarding/
│   │   ├── welcome_screen.dart
│   │   ├── language_screen.dart
│   │   ├── country_screen.dart
│   │   └── widgets/
│   │       └── premium_button.dart
│   ├── home_dashboard/
│   │   ├── home_dashboard_screen.dart
│   │   └── widgets/
│   │       ├── balance_card.dart
│   │       ├── quick_action_button.dart
│   │       └── info_card.dart
│   ├── wallet/
│   │   ├── wallet_screen.dart
│   │   └── widgets/
│   │       ├── currency_card.dart
│   │       └── action_button.dart
│   ├── activity/
│   │   ├── activity_screen.dart
│   │   └── widgets/
│   │       ├── transaction_item.dart
│   │       └── filter_chip.dart
│   ├── profile/
│   │   ├── profile_screen.dart
│   │   └── widgets/
│   │       ├── profile_header.dart
│   │       └── settings_item.dart
│   └── fintech_main_tab_scaffold.dart
```

## Next Steps

1. Wire up navigation routes in `main.dart`
2. Connect to actual data sources
3. Implement language selection persistence
4. Add animations and transitions
5. Implement dark mode
6. Connect authentication flow

