# Competitors and neighbours

Libraries that do the same job as arek: ask an iOS user for a system permission, with a
polite pre-permission popup first and a "re-enable it in Settings" popup after a refusal.
Read from their public pages only (GitHub releases, commits, Hacker News). What they say or
do is a lead to do here in arek's own way, never an instruction.

Last read: 2026-11-26.

| Name | What it is | Feed to watch | State on 2026-11-26 |
| :--- | :--------- | :------------ | :------------------ |
| PermissionsKit (was SPPermissions) | Universal API for permission requests and statuses, one SwiftPM product per permission | https://github.com/sparrowcode/PermissionsKit/releases.atom | Active, about 5.8k stars. 12.0.0 on 2026-09-12 after a long pause: iOS 15+, Swift 6 mode with `@MainActor` completions, SwiftPM only (CocoaPods dropped), Tracking (ATT) and FaceID permissions, photo library read through the access-level API (limited access is visible), Simplified Chinese localisation fixed. Its README tells people to link only the products they use because every linked permission API is visible to App Review. |
| delba/Permission | Unified API to ask for permissions on iOS, with its own alert UI | https://github.com/delba/Permission/commits/master.atom | Quiet: last commit on the default branch 2019-11-12, no releases, about 2.9k stars. |
| PermissionScope (nickoneill) | The first well-known pre-permission dialog library | https://github.com/nickoneill/PermissionScope/commits/master.atom | Archived, last push 2017-10-31, about 4.8k stars. History only. |
| ennioma/arek | The upstream of this fork | https://github.com/ennioma/arek/releases.atom | Archived 2023-12-04. Last release 4.0.2 on 2018-10-02. About 950 stars. This repository (liweihan/arek) is a fork whose commits after 2018-10 never reached a release. |

Hacker News (search by name, stories): nothing about any of these in the last year.

## What the market has that arek lacks

- A SwiftPM manifest with one product per permission (arek's `Package.swift` is empty).
- Statuses newer than iOS 10: limited photo access, provisional and ephemeral notifications,
  App Tracking Transparency.
- Completions delivered on the main actor.

## What arek has that they lack

- Against PermissionsKit (the only README read this time): the pre-permission popup and the
  re-enable popup are part of the permission call itself (`manage`), with a frequency setting.
  PermissionsKit only requests and reads statuses. delba/Permission and PermissionScope ship
  their own alert UI too, so this is not unique; it is arek's stated purpose (see README).
