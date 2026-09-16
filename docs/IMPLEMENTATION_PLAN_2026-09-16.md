# VELIXEO completion pass — 2026-09-16

This branch completes the live service foundation without replacing working authentication, wallet, payment, admin, or SMM behavior.

Scope:
- Multi-provider SMM hardening and clearer admin controls.
- Full virtual-number/SMS flow with a 5SIM-compatible adapter, smart-buy modes, live offers, SMS polling, cancel/refund, finish, and hidden provider identity.
- Flutter virtual-number panel.
- Flutter support/ticket UI.
- Real service search and banner CTA routing.
- Coupon application foundation for live checkout flows.
- Admin navigation/readiness improvements.
- Android artifact/version cleanup.

Production credentials remain server-side and are never embedded in the mobile client.
