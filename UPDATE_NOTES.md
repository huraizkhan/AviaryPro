# Aviary Pro 1.4.13+22 — Interaction & experimental layout customization

- Rebuilt Create Pair selection as tappable Male/Female bird-card grids instead of dropdowns.
- Automatically preselects the only valid opposite-gender same-species pair in a cage.
- Pair creation remains available from the global floating Add menu; removed duplicate Create Pair buttons from Breeding and Cage Details.
- Removed visible Pair IDs from breeding-card titles; cage + species remain the primary identification.
- Fixed All Birds automatic-count chips so tapping the selected chip again clears that filter.
- Added No mutation as a real selectable Mutation filter.
- Long-pressing a bird card now opens Edit Bird directly; bulk Select mode still supports multi-selection.
- Moved Hatch to a direct action on each pending egg card; the overflow menu is reduced to Foster Egg and Change Status.
- Added compact Change Egg Status sheet for Fertile, Infertile, Dead Embryo, Cracked, Missing, etc.
- Unified Dashboard, Birds, Breeding and Finance top-card surfaces to the selected theme color.
- Added Settings → Experimental Layout: reorder/hide main summary cards like tiles and choose which data fields appear on All Birds cards.
- Experimental card preferences persist locally and can be reset per screen.
- No destructive database migration or data reset.

# Aviary Pro 1.4.12+21 — Dark-theme UI repair

- Fixed unreadable pale card backgrounds and low-contrast text in Dark mode.
- Birds, cages, breeding pairs, clutch/egg/chick cards, finance transactions, search, history, backup, sale/value and related management cards now use theme-aware surfaces.
- Bird list cards no longer turn pink merely because a bird is paired; gender remains communicated through blue/pink bird text and compact status chips.
- Added a shared adaptive semantic-card surface so future screens can keep status colors without breaking Dark mode contrast.
- Added a consistent theme-aware avatar/icon surface and a clearer Dark-mode chip style.
- No database, sync, finance, breeding or other business-logic changes.

# Aviary Pro 1.4.11+20 — Workflow redesign foundation

- Added Sale Workspace with For Sale, Taken, Sold and Returned counts.
- Added sale outings with reusable/removable locations, today-default editable dates, sell/return handling, and outing history.
- Added factor-based sale pricing (Species / Mutation / Age Group), live zero-balance validation, group counts, bird drill-down and optional per-bird overrides.
- Added Bird Value Calculator with saved single-price estimates by species, mutation and age group.
- Added pair stage strip and one-tap provisional breeding observations: Suspected Egg, Chick Heard, Breeding Interest, No Interest and Problem.
- Added eye-color and chick-down fields for birds.
- Added scrollable + typeable Day / Month / Year date selector throughout the app; calendar popup is no longer used.
- Added feed purchase quantity (kg) and feed purchase trend analytics.
- Added Settings tab with System / Light / Dark modes and Classic, Olive, Ocean and Plum themes.
- Added faster automatic edit-sync retry and silent Google session restoration; backup scheduling remains separate.
- Made All Birds cards more scannable with compact species, mutation, age, cage, pair and eye-color badges.
- Added Today at a Glance dashboard summary.
- Database migration advances safely to v15 without wiping existing data.

# Aviary Pro 1.4.10+19 — Management, history, rings and finance update

- Added More → Ring Management with species-specific allowed ranges, allotted/available status, and gender-colored allotted rings.
- Add/Edit Bird now asks Source first, then uses managed ring, mutation, and bird-name dropdowns.
- Purchased birds create Ledger expenses automatically; bred/gifted/other sources stay separate from purchase accounting.
- Added Mutation Management and Bird Name Management under More.
- Sold/removed birds keep their ring unless the physical ring is confirmed removed; released ring numbers become reusable while Ring Removed remains in history.
- Young chicks keep temporary IDs in the nest and must receive an available permanent species ring when moved to a youngster cage.
- Bred/hatched youngsters default to the For Sale list until manually marked Not for Sale.
- Added separate compact Bird History with date grouping, meaningful lifecycle/breeding events, same-date aggregation, and Previous Birds count/list; Ledger finance events remain separate.
- Multi-bird purchase/sale supports one total amount and stores the divided per-bird share while Ledger stores one total transaction.
- Added All Birds and All Chicks remembered counting pills (Species, Mutation, Name, Gender); All Chicks shows and groups by parents.
- Combined hatch attention notification now covers only due-today/overdue eggs, alerts audibly once per day, avoids repeat heads-up alerts on resume, restores silently after dismissal, and stays hidden from midnight through 07:59.
- Fixed Add Bird estimated-age/unit overflow and hardened Back/cancel during egg hatching.
- Previous pairs remain historical only and are excluded from current Breeding lists/counts; pair-card spacing was tightened.

# Aviary Pro 1.3.2 — Testing-round fixes

- Cage Details → Add Bird → Move Existing Bird now lists active birds from other cages and unassigned birds, while excluding birds already in the destination cage.
- Paired birds retain the safe Move Whole Pair or Unpair & Move This Bird choices.
- Dashboard now shows only Eggs and Chicks; each active clutch contributes the larger of its current egg count or temporary Expected Eggs target to the Eggs total.
- Rebuilt the All Birds filter as a self-contained stateful bottom sheet to prevent the Flutter `_dependents.isEmpty` crash.
- Replaced the combined Filter & Count bar with equal Filter and read-only Count buttons; Select remains separate.
- Rebuilt cage-delete confirmation with its own controller lifecycle and delayed the second route close so cage deletion no longer disposes dependent widgets in the same frame.
- Added blue male and pink female text to both active Parent Pair options and the Previous Pairs dialog.

# Aviary Pro 1.3.1 — Dashboard, pair details and bird-filter refinement

- Merged Dashboard Eggs, Expected and Chicks into one summary box while keeping all three counts separate.
- Increased Dashboard summary text and count sizes.
- Made active clutches the priority in Pair Details and expanded every active clutch by default.
- Moved Offspring and Completed Clutches into separate dedicated windows without showing their counts on the main Pair Details window.
- Rebuilt All Birds Filter & Count as a press-to-open menu for Species, Name, Gender, Mutation and Age Group, with a live matching count.
- Kept manual bird selection and natural ring/ID sorting.
- Removed the unused age-group constant that caused the analyzer warning; chick records and chick age calculation remain unchanged.

# Aviary Pro 1.3.0 — Breeding, age, cage and list update

- Added temporary Expected Eggs targets to active clutches. Targets clear automatically when reached and can be closed manually without creating egg records.
- Breeding pair cards now show Eggs, Expected and Chicks, plus the number of active clutches when greater than one.
- New pairs begin Inactive, activate on their first egg, and can be activated manually.
- Added progressive estimated-age calculation from every acquisition/source date when hatch date is unknown.
- Added active-first and Previous Pairs selection for bred-bird parentage.
- Added natural bird sorting, combined Filter & Count, and manual bird selection.
- Reworked physical-cage deletion to be transactional, occupancy-blocked and safe for bird records.
- Removed cage-move history; cage assignment now represents only the current position.
- Removed cage links from removed birds and previous pair sessions.
- Added gender labels to cage birds and pair rows.
- Added History search, larger Dashboard summary text, separate Eggs and Chicks counts, and Expected Eggs reporting.
- Updated the Add menu and Cage Details Add Bird flow.
- Preserved silent Google Drive session restoration and background sync behavior.

# Aviary Pro beta update 1.2.0+3

## Data-safety warning before installation

This build upgrades the local database from schema version **10 to 11** and adds permanent cloud-sync metadata. It also changes cage-portion merge behavior.

1. Open the currently installed app.
2. Go to **More → Backup & Restore**.
3. Create a **manual Google Drive backup** and confirm it appears in the backup list with the correct date and a non-zero file size.
4. Keep the existing app installed. Do **not** clear app data or uninstall it.
5. Run this update over the existing installation.

The migration adds new tables and identifiers without deleting existing birds, cages, pairs, clutches, eggs, finance entries, or history.

## Cloud sync

- Backup and Sync are now separate features under **More → Backup & Sync**.
- Change-based synchronization uses permanent record IDs and synchronizes user-created changes across devices.
- Offline changes remain queued until a connection is available. While the app is active, sync checks once per minute and also checks whenever the app resumes. It skips full uploads/downloads when neither local nor cloud state changed.
- Add, edit, move, pair/unpair, merge/unmerge, sale, removal, finance, and confirmed deletion changes are synchronized.
- Derived values such as age groups, dashboard totals, alerts, hatch urgency, colors, and compact cage display numbers are recalculated locally instead of being synchronized as separate edits.
- A fresh empty installation with an existing signed-in Google session can download existing cloud data automatically. On a new device without a previous app sign-in, connect the same Google account once from Backup & Sync; the first sync then downloads the cloud records.
- A non-empty local database is never silently replaced. When both local and cloud records exist, the app asks before merging them.
- Deletions use tombstones so deleted records do not reappear from an older device copy.
- Sync uses last-write-wins versioning with device IDs for deterministic tie handling.
- Restoring a backup pauses sync and resets local sync state. Enabling sync again requires a safe local/cloud merge decision.

## Backup scheduling and retention

- Automatic backup frequency can be set to **Off, Daily, Weekly, or Monthly**.
- Daily backups use a selected time.
- Weekly backups use a selected day and time.
- Monthly backups use a selected date and time.
- Automatic backup no longer runs every time the app opens. It runs only after the configured occurrence is due and only when user data changed since the last successful automatic backup.
- Empty automatic backups are blocked.
- The latest **3 successful automatic backups** are retained.
- The latest **3 successful manual or safety backups** are retained separately.
- Failed/incomplete backups do not count toward retention.
- Older retained files are removed only after the new backup upload succeeds.
- Restore creates a safety backup first when local data exists and stops if that safety backup fails.

## Cage portions and grouped merging

- A numbered portion can merge only with portions belonging to the same physical/whole cage.
- Occupied portions may be merged. The confirmation shows the affected birds and pairs.
- Birds, active pairs, and active breeding placement move to the kept visible portion.
- The hidden portions drop out of the compact numbered series; later display numbers close the gap.
- Permanent internal cage IDs preserve every relationship and history entry while display numbers change.
- Assigned merge groups are shown contextually in the selection screen. For example, from Cage1 in the Cage1+Cage2 group, the list can show Cage1, Cage2, Cage3+Cage4, Cage5.
- Groups may contain two, three, or more portions.
- Cage Details shows **Mergeable with:** only when an assignment exists.
- A currently merged cage shows its hidden portions with **Unmerge** actions.
- Unmerging restores the selected hidden portion and expands the numbered series. Occupants remain in the kept cage until moved manually.
- A whole cage with only one active portion does not show a Merge action.

## Other fixes retained in this build

- Fixed the Cages-screen `setState()` runtime error.
- Swipe left/right between main sections while keeping bottom navigation synchronized.
- Google sign-in is initiated from Backup & Sync rather than forcing a popup at startup.
- Paired-bird cage moves offer Move Whole Pair or Unpair & Move This Bird.
- Re-pairing the same birds reuses their pair history and starts another pairing period.
- Late-entered bred offspring attach to the selected parents and matching historical clutch when safely identifiable.
- Pair history includes Current Offspring and All Offspring views with present, removed/sold, and deceased statuses.
- Empty cages stay in the Cages section but remain hidden from the Birds-section cage summary.
- Edit Cage, Sell Cage, sale-income creation, and small bottom Delete Record controls remain included.

## Local verification commands

Run from the project folder:

```powershell
flutter pub get
flutter analyze
flutter run
```

Do not proceed with a release build if `flutter analyze` reports errors.

## Package validation

The source package was checked for balanced Dart syntax, missing relative imports, unresolved `DatabaseHelper` method calls, SQL migration/trigger behavior, deterministic legacy sync IDs, tombstone/version ordering, cage-group selection, occupied merge/unmerge behavior, dynamic numbering, and separate backup scheduling/retention pools.

The build environment used to prepare this ZIP does not contain the Flutter SDK, so run `flutter analyze` and `flutter run` locally before treating this beta as validated on Android.
