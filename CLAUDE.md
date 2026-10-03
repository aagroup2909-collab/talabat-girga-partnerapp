# Talabat Girga — partner app (Flutter)

One mobile app for drivers and merchants of طلبات جرجا (delivery platform in Girga, Egypt). After login, `user.role` (`driver` or `vendor`) decides the screens. More than one developer works on this repo, each with their own Claude Code session: `git pull` before starting, commit and push only your own focused changes.

Read `README.md` (run commands, structure, polling). The API reference is `backend/docs/API.md` in the backend repo (`talabat-girga-backend`); if both repos are cloned side by side it is at `../../backend/docs/API.md`. Same architecture and style as the customer app (`talabat-girga-customerapp`).

## Rules for this codebase

- **Arabic-first, RTL.** Every user-facing string is Egyptian Arabic; numbers use Western digits.
- **All API calls go through `lib/data/repository.dart`**; errors arrive as `ApiException` (`lib/core/api.dart`) with Arabic messages, `fieldError(...)` for 422 and `code` for 403/409.
- Riverpod 3 without codegen; go_router; shared widgets in `lib/core/`.
- **No sign-up in this app.** The admin creates driver and merchant accounts and passwords. `needs_profile: true` → the "حسابك لسه مش جاهز" screen.
- `/auth/login` does not include the driver's `approval_status`, so the app calls `/me` right after login. Keep that.
- **No WebSockets** (shared hosting): new orders, offers and status changes are polled. Merchant new-order ringing and the driver's offer alert depend on that polling; keep intervals as they are unless the backend changes.
- Settlements: merchant ↔ platform requests need admin approval; merchant ↔ driver cash handovers are recorded by the merchant and confirmed by the driver.

## Run and test

- The app defaults to the production API `https://talabat.ahgroup.online/api/v1`. For local work: `adb reverse tcp:9123 tcp:9123` and `--dart-define=API_BASE_URL=http://127.0.0.1:9123/api/v1`.
- Local demo accounts: drivers 01200000001 / 01200000002, merchant 01111111111; password from `DemoSeeder` in the backend.
- Do not change real orders, stores or balances on production while testing; use the local backend.
- API smoke test against a local backend: `flutter test test/api_smoke_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:9123/api/v1 --dart-define=DEMO_PASSWORD=<DemoSeeder password>`.
- Before committing: `flutter analyze` (must be clean) and `flutter test`.
- Keystores, `key.properties` and Firebase files are never committed; ask the project owner.
