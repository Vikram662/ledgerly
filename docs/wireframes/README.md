# Thekedaar wireframes

A light, modern wireframe for every screen in the app. These files are copies of the design canvas:
https://claude.ai/artifact/Ju7oQNsVa58HSpZvXkDBW2

- `canvas.json` is the canvas index: board positions and titles.
- Each `*.dc.html` file is one phone screen (390 × 844). Links between screens use `href="Other.dc.html"`.
- The files load `./support.js` from the canvas runtime, so they do not render as plain HTML pages. Read them as layout and markup references, or open the canvas link to see them.

## Design tokens

| Token | Value | Use |
|---|---|---|
| Page | `#F4F5F7` | Screen background |
| Surface | `#FFFFFF`, border `#E3E6EA`, radius 16 | Cards, lists |
| Text | `#15181D`, muted `#5B6370` | Body, labels |
| Primary | `#0369A1` (tint `#E0F2FE`, `#F0F9FF`) | Main buttons, active tab, links |
| Accent | `#F59E0B` with dark text | Advance, Pro |
| Success | `#059669` fill, `#047857` text, `#ECFDF5` bg | Present, paid, received |
| Warning | `#F59E0B` fill, `#B45309` text, `#FFFBEB` bg | Half day, unpaid |
| Danger | `#E11D48` fill, `#BE123C` text, `#FFF1F2` bg | Absent, overdue |
| Font | Manrope 400–800, tabular numbers for amounts | All text |
| Touch | min 44 px, primary buttons 56 px, radius 14–16 | Buttons, inputs |

## Screens

| Group | Files |
|---|---|
| Bottom tabs | `Main` (Home), `Attendance`, `Billing`, `Khata`, `Workers` |
| Detail and entry | `WorkerDetail`, `AdvanceEntry`, `More` (replaces the side drawer) |
| Onboarding and lock | `Welcome`, `OnbType`, `OnbBusiness`, `PinCreate`, `Unlock` |
| Billing | `BillDetail`, `BillEditor`, `LineEditor`, `Measurement`, `PaymentEntry`, `ClientDetail`, `ClientForm` |
| Workers and khata | `WorkerForm`, `ChangeWage`, `PieceWork`, `Settlement`, `AttendanceMonth` |
| Expenses, suppliers, jobs | `Expenses`, `ExpenseEntry`, `Suppliers`, `SupplierDetail`, `Jobs`, `JobDetail`, `JobForm` |
| Tasks, calendar, reports | `Tasks`, `TaskForm`, `Calendar`, `Dues` |
| Settings | `Settings`, `BusinessProfile`, `Rules`, `Trades`, `AppLockSettings`, `Reminders`, `Backup`, `Restore`, `Subscription` |

## Flow changes from the current app

- Onboarding is split into steps: Welcome (language, restore) → user type → business and trades → create PIN → fingerprint prompt.
- The side drawer becomes a `More` screen, opened from the business avatar on Home.
- Billing uses underline tabs (Bills · Quotations · Clients · Payments) with filter chips and status pills.
- Amount entry (advance, payment, expense) uses one pattern: a big amount, mode chips and a numpad.
