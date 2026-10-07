# GPLv3 compliance for this fork

This is an engineering and release checklist, not legal advice. The controlling terms are the GNU General Public License version 3 in `LICENSE`.

## Repository requirements

- Keep the upstream `LICENSE` file unchanged and prominent.
- Retain upstream copyright, attribution, and third-party notices.
- Mark that this is a modified fork and record the date and nature of material changes in `NOTICE.md` and `MODIFICATIONS.md`.
- License the combined derivative work under GPLv3. Do not add terms that restrict recipients from exercising GPLv3 rights.
- Keep scripts, project files, dependency declarations, and other material needed to build and install the modified program in source control.
- Document any required non-source installation information when GPLv3 section 6 requires it for the distribution method or device.

## Binary distribution requirements

Before publishing a DMG, ZIP, Homebrew cask, update feed, or other executable form:

1. Create an immutable source tag for the exact binary revision.
2. Make the complete corresponding source for that tag available under GPLv3 through a durable, no-charge source location.
3. Include the GPLv3 license, fork notice, and third-party notices with the app or distribution package.
4. Link release notes to the exact source tag and state how recipients can obtain the source.
5. Include build and installation instructions, dependency resolution files, helper targets, and release scripts used for that binary.
6. Verify that signing, notarization, update, store, or download terms do not impose an additional restriction that conflicts with GPLv3.
7. If relying on a written source offer instead of accompanying source, have the release owner review GPLv3 section 6 and retain the offer for the required period. This project should prefer publishing corresponding source beside every binary.

## App bundle requirements

The Xcode project copies these files into the application resources:

- `LICENSE`
- `NOTICE.md`
- `THIRD_PARTY_LICENSES`

Release verification must inspect the built `.app` and confirm that all three files are present. A later About or Legal screen may link to these bundled copies, but the bundled files must not depend on that UI to exist.

## Release evidence

For each public release, retain:

- source tag and commit SHA
- binary checksum
- build command and Xcode version
- source archive URL
- release page URL
- verification that bundled legal files match the tagged source
- any signing and notarization records

## Branding and update channels

GPLv3 permits modification and redistribution, but it does not grant trademark rights. Before publishing a separately maintained binary, review the app name, icon, bundle identifiers, signing identity, update feed, website links, support links, and crash-report destinations. Do not allow a fork build to impersonate or overwrite the upstream release channel unintentionally.
