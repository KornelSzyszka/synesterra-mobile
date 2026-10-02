# iOS signing options

**Status:** proposed for Founder decision
**Issue:** Refs #44
**Decision gates:** business and release
**Sources checked:** 2026-10-02

## Decision

Enroll the Founder as an **individual** in the Apple Developer Program and, after explicit business and release approval, use an on-demand GitHub-hosted macOS signing job protected by a GitHub Environment. This is the smallest repeatable route to an installable development build without buying or owning a Mac.

An organization enrollment is not recommended unless the Founder already has a legal entity and wants the App Store seller name to be that entity. Apple requires an organization applicant to have legal authority, a legal entity, a D-U-N-S number, organization-domain email, and a working organization website; an individual account instead requires a two-factor-authenticated Apple Account, legal name, and email, phone, and street address. [Apple enrollment requirements](https://developer.apple.com/programs/enroll/) (checked 2026-10-02).

## Apple Developer Program: required account

The Apple Developer Program costs **USD 99 per membership year** (or local-currency price where offered; the Polish checkout price has not been verified). Apple verifies enrollment, then requires accepting the program license and paying the membership; membership provides Certificates, Identifiers & Profiles for signing. [Apple membership details](https://developer.apple.com/programs/whats-included/) and [enrollment](https://developer.apple.com/programs/enroll/) (both checked 2026-10-02).

The Founder must create or use a personally controlled Apple Account with two-factor authentication and enroll with their legal identity. The account should remain the Founder’s; after enrollment, the Founder can invite a technical team member with only the role needed for certificates, profiles, and device registration. No Apple Account password, certificate private key, profile, or recovery code belongs in this repository.

Apple's free Personal Team is not an alternative for a durable development-install path: it still needs Xcode on a Mac, permits at most three devices and three apps per device, and its device-install provisioning profiles expire after seven days. [Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account) (checked 2026-10-02).

## Options

### A. On-demand GitHub-hosted macOS signing job — recommended

Use the existing manual macOS CI route as the base, but only after the gate: create a separate signing job or environment, import a development certificate and provisioning profile into a temporary keychain, produce a development IPA, and make the artifact available only to authorized project members. The current workflow is explicitly unsigned (`flutter build ios --debug --no-codesign`), so it cannot install on the Founder’s iPhone; that is repository evidence, not a completed implementation.

- **Cost:** Apple membership: USD 99/year above. For a private repository, GitHub-hosted standard macOS jobs consume the account allowance and then cost **USD 0.062 per minute**; a ten-minute billable run is USD 0.62. Actual charge can be lower while included minutes remain, and depends on the account plan; storage beyond the included allowance costs USD 0.25/GB-month. [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) (checked 2026-10-02).
- **Risk:** The certificate's private key is a high-value signing secret. GitHub warns that anyone with repository write access can read configured secrets at workflow runtime, and redaction is not a security boundary against a determined workflow author. Limit the signing job to an Environment with required Founder review, manually dispatched trusted refs, least-privilege token permissions, pinned actions, and no PR-triggered secret access. [GitHub secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use) and [compromised runners guidance](https://docs.github.com/en/actions/concepts/security/compromised-runners) (checked 2026-10-02).
- **Needs from the Founder:** approve Apple enrollment and GitHub Actions spend; enroll and retain control of the Apple account; register/authorize the iPhone; approve the protected Environment’s secret use; provide or authorize generation of a development certificate, its export password, and profile through Apple’s portal. The secrets must be stored only as GitHub Environment secrets, never committed.
- **Reversibility:** remove the job/environment and artifacts, revoke the certificate/profile in Apple Developer, delete the GitHub secrets, and stop dispatching macOS jobs. The annual Apple fee already paid is not assumed refundable because no refund policy was verified here.

### B. Rented or cloud Mac

Rent a remote Mac for the signing session and use Xcode/Flutter there. This enables direct inspection of Xcode signing and USB/device work only if the provider or the borrowed local-device arrangement supports it; remote access alone does not prove that the Founder’s iPhone can be installed or debugged.

- **Cost:** one published example, MacinCloud, starts at **USD 4/day** and **USD 25/month** for its managed-server plan; MacStadium lists a dedicated M2 Mac mini at **USD 109/month**. These are vendor starting prices, checked 2026-10-02, exclude any tax, currency conversion, add-ons, and Apple membership. [MacinCloud pricing](https://checkout.macincloud.com/select) and [MacStadium pricing](https://macstadium.com/pricing?c=VGS2&p=sm1b).
- **Risk:** Apple credentials, certificate private keys, source code, and generated IPA exist on a third-party machine. Device attachment, USB debugging, availability, region, and account-session policies are provider-specific and have not been verified for any vendor.
- **Needs from the Founder:** approve the vendor and spend; retain control of the Apple Account; approve temporary access to the repository and signing material; confirm how the iPhone is registered and receives the IPA. Do not give a vendor the Apple Account password; sign in personally and remove the session afterwards.
- **Reversibility:** cancel the rental, delete the remote workspace/keychain, revoke any certificate/profile created there, and remove access tokens. The paid rental period is a sunk cost once started.

### C. Borrowed Mac

Use a trusted person’s Mac for a short, supervised signing session. It can create the same development IPA and is the least operationally complex one-off route, but it is not repeatable CI and requires physical coordination.

- **Cost:** no vendor price is applicable if the machine is genuinely borrowed; Apple membership is still USD 99/year for the durable Program path. Any compensation to the lender is a private arrangement and has not been priced or verified.
- **Risk:** the lender’s computer receives project source and potentially a signing private key; availability and handover are manual. A free Personal Team can demonstrate installation but needs rebuilding/reinstallation after seven days and is not an acceptable replacement for the chosen path.
- **Needs from the Founder:** provide a trusted Mac owner, arrange a supervised session, sign into the Founder-controlled Apple Account in Xcode, connect/approve the iPhone, and remove credentials afterwards.
- **Reversibility:** remove the Apple account from Xcode, delete the temporary keychain/profile/build, and revoke the certificate/profile if it was created. The physical coordination cost cannot be recovered.

### D. Flutter tooling alone — not a standalone option

Flutter can drive the build (`flutter build ipa`) but does not provide macOS, Xcode, an Apple account, or signing credentials. Flutter's official iOS release guidance says Xcode is required and that the procedure must run on a macOS device; it documents `flutter build ipa` as producing the archive/IPA after signing is configured. [Flutter iOS deployment guide](https://docs.flutter.dev/deployment/ios) (checked 2026-10-02).

- **Cost and reversibility:** no additional Flutter product cost was verified; it inherits the cost and reversibility of A, B, or C.
- **Needs from the Founder:** none beyond the selected host and Apple-account option.

## Recommendation

Choose **A** after the Founder approves the USD 99/year membership and GitHub Actions spending. It keeps the private key out of local personal computers, gives a repeatable audit trail, reuses the repository’s already-on-demand macOS runner, and has the lowest recurring operational burden; the protected Environment is essential because a signing credential is exposed to the code that runs in its job.

Use **C** only if a one-off, supervised device proof is needed before committing to CI. Use **B** only if a real Mac desktop is needed for Xcode investigation or a provider can meet the device-access requirement; it is otherwise a higher-cost duplicate of the CI capability. Do not choose D by itself.

## Evidence

- [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) has an on-demand `macos-15` job that builds with `--no-codesign`; it is a compile check, not an installable IPA.
- [GitHub Actions secret types](https://docs.github.com/en/code-security/reference/secret-security/secret-types) documents repository, environment, and organization secret scopes; Environment secrets can be protected by required reviewers. Checked 2026-10-02.
- [Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account) documents Personal Team’s seven-day limitations. Checked 2026-10-02.

## If undecided: what waits

No account, certificate, provisioning profile, signing workflow, `ios/` configuration, or secret is created by this proposal. The iOS device stages **C3** and **S3** named by issue #44 remain blocked until a signed development IPA installs on the Founder’s registered iPhone and the Founder shows device evidence.

[ADR 0002](0002-audio-backend.md) records the same condition: C3 and S3 are `not run` because there is no Mac and no Apple Developer account, and iOS device work waits for this REL signed-install path. It also says that, until then, there is no iOS device evidence or iOS distribution; this package does not change that status.
