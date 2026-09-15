# VELIXEO — Locked Auth & Admin Requirements

## Authentication

- Registration must include a required **Full name / نام و نام خانوادگی** field.
- Login must NOT ask for full name; it uses email/phone + password.
- Existing accounts remain compatible even if `fullName` is currently null.
- Google Sign-In is a required real authentication option. It must not be presented as live until Google OAuth credentials are configured and backend token verification is enabled.
- Apple Sign-In is planned for iOS when the iOS build is introduced.
- Telegram is not treated as a default native identity provider; it may be added later only with a secure supported login flow.

## Admin Panel

A responsive web admin panel is a required core part of VELIXEO. It must include:

- Dashboard: total users, today's registrations, admin count, total wallet balances.
- Users: search by name/email/phone, user detail, registration date, role and wallet balance.
- Wallet: manual credit/debit with reason and immutable ledger history; no silent balance edits.
- Exchange rates: AFN is the source-of-truth; admin can manage USD/TOMAN display rates.
- Payments: HesabPay transactions and verification status.
- Orders: all service orders, filters and status control.
- Providers/APIs: Social, Virtual Number, Mobile Top-up, Premium and future providers; API keys remain server-side only.
- Pricing: markup/margin and per-service overrides.
- Catalog: services, categories, countries, operators, products, banners and availability toggles.
- Notifications, coupons, refunds, support and audit logs.

## Execution order

1. Backend full-name support and admin APIs.
2. Admin Panel MVP: Dashboard, Users, Wallet, Rates.
3. Flutter registration UI adds Full name only in registration mode.
4. Google OAuth configuration + real Google Sign-In.
5. HesabPay live wallet top-up.
6. Provider/API modules and expanded admin sections.
