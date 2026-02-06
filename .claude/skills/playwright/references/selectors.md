# Component Selectors

Project-specific CSS selectors for quick reference. Update this file as components change.

> **To populate**: Run `grep -rh "class=" src/components/ | grep -oP '[\w-]+' | sort -u` to discover classes,
> or inspect the running app with snap.ts and view the screenshots.

## Layout
| Component | Selector | Notes |
|---|---|---|
| Main nav | `nav`, `.main-nav` | |
| Footer | `footer`, `.site-footer` | |
| Sidebar | `.sidebar`, `aside` | |

## Pages

### Home
| Component | Selector | Notes |
|---|---|---|
| Hero section | `.hero`, `[data-testid="hero"]` | |
| | | |

### Auth
| Component | Selector | Notes |
|---|---|---|
| Login form | `form[action*="login"]`, `.login-form` | |
| Signup form | `form[action*="signup"]`, `.signup-form` | |

## Shared Components
| Component | Selector | Notes |
|---|---|---|
| Buttons (primary) | `.btn-primary`, `button[type="submit"]` | |
| Modal / Dialog | `[role="dialog"]`, `.modal` | |
| Toast / Notification | `[role="alert"]`, `.toast` | |
| Cards | `.card`, `.v-card` | |
| Chips / Tags | `.chip`, `.v-chip`, `.tag` | |

## Framework-Specific (Vuetify / MUI / etc.)
| Component | Selector | Notes |
|---|---|---|
| | | |

<!--
  Tips:
  - Prefer data-testid for stability: <div data-testid="word-stripe">
  - Prefer getByRole/getByLabel in scripts over CSS where possible
  - Keep this file under 100 lines — only high-value selectors
-->
