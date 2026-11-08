# CORE 10 — Executive Ocean owner-only design architecture

Version 1 — November 9, 2026

## Design contract

**Owner portal only**: `owner.html` includes `core10-owner.css` after the original ERP stylesheet. Islamia's `index.html`, `manifest.json`, `app.css`, `logo.webp`, `mark.svg` and `icon.svg` are untouched. This is not a separate fork of the ERP application, just a self-contained design layer.

**Style**: Midnight Navy (#0D2133), Ocean Teal (#087F8C), Soft Mint (#D7F3EF), Cloud White (#F2F6FA). Mature executive aesthetic; low-noise navigation, distinct operational areas, clear cards.

**Desktop**: a fixed deep-navy application sidebar at 1024px+, generous main content width, separate dashboard summary and operational cards. Existing click actions, role logic, search, location navigation and page routes remain intact.

**Mobile**: keep current drawer-based navigation and the existing responsive pages. Tone, spacing, card borders and forms are adjusted in owner-only CSS.

**Theme change later**: edit tokens at the top of `core10-owner.css`, not the Islamia CSS. Owner keeps its independent `core10_owner_theme` preference. The existing theme menu works with the owner visual palette.

## Non-negotiable boundaries

1. Islamia Misty Ghar retains its complete current UI and branding.
2. CORE 10 may open a business but must not overwrite the business profile or brand.
3. Only the authenticated owner uses this CORE 10 interface. Non-owners must never receive consolidated data.
4. Security is enforced by Supabase RLS/RPC and business scope; UI styling never substitutes for backend access checks.
5. Avoid demo revenue figures, empty states that suggest real data, and changes to inventory or accounting.

## Changes

- `owner.html`, `v2/owner.html`: link one new isolated CSS, owner browser theme color.
- `core10-owner.css`, `v2/core10-owner.css`: new owner-only tokens, navigation, dashboard, business portfolio, mobile/desktop CSS.
- `core10-owner.webmanifest`, `core10-owner-icon.svg` and their v2 variants: owner PWA colors only.
- `sw.js`, `v2/sw.js`: cache-bust and precache the new stylesheet.

## Acceptance

- Verify both portals independently on Android and desktop.
- Confirm Islamia HTML/CSS/icon/manifest file SHAs are identical before/after.
- Confirm CORE 10 dark sidebar, cloud workspace and teal actions render in owner portal only.
- Verify real owner session and staff sessions, especially when navigating from a deep link.
- Backend multi-business tenant isolation is **not certified** by this visual update.
