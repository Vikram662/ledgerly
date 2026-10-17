# Redesign: remaining work

Wireframes: `docs/wireframes/*.dc.html`. All 45 screens have been restyled
on `feature/new-design` and merged into `main` (Analyze and Test pass on CI).
What is listed here is left for later.

## 1. Gaps against the wireframes

No known screen gaps remain against the current wireframes.

Done since the merge: job cards show Billed / Expense / Profit, supplier rows
show "Last purchase {date}" or "Paid {date}", and both calculations now have
repository tests. These screens have not yet been checked on a phone.

## 2. Ledgerly rename: still on the old name

The user-visible name, the launcher label and the CI artifact names (`ledgerly-*`) are now Ledgerly. These still say "thekedaar" on purpose:

- Android package id `com.thekedaar` and `--project-name thekedaar` in `.github/workflows/build.yml`. Changing it makes a new app on the phone, so the old install will not update.
- Database file `thekedaar.sqlite` (`lib/core/db/database.dart`). Do **not** rename without a migration, or existing data will not be found.
- Google Drive folder `Thekedaar Backups` (`lib/core/backup/drive_store.dart`). Do **not** rename, or existing backups will not be found.
- Subscription API URL `thekedaar-subscription-api` (README). It is the deployed Worker's name.
- Dart class names (`ThekedaarApp`) and the pubspec `name: thekedaar`. Internal only.

## 3. Seed data

- Shop: starter rate-list lines (delivery, packing, alteration, installation) and two more expense categories. Real products differ per shop, so the owner adds their own.
- Personal: added Maid / House Help, Society Maintenance, Water and Insurance.
- Seed names (categories, roles, items) are not translated to Hindi anywhere. Decide if they should be.

## 4. Testing

- Nothing has been run on a phone yet. CI only shows that the code compiles and the tests pass.
- Install the CI debug APK and open every screen, in both English and Hindi, for each user type (contractor, shopkeeper, personal).
- Check the onboarding, lock and backup/restore flows end to end.
