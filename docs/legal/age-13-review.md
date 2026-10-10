# Moving from 18+ to 13+: what must be reviewed first

Status (October 2026): Flowstate is **18+** everywhere. The minimum age lives in one constant,
`kMinimumAge` in `lib/screens/legal/legal_constants.dart`. The sign-up checkbox, Terms and Privacy Policy read it.
Changing the number alone would make the copy say 13 while nothing else supports it. Do not do that.

## Every place that needs review

| Where | What it says / does today |
|---|---|
| `lib/screens/legal/legal_constants.dart` | `kMinimumAge = 18` |
| `lib/screens/auth_screen.dart` | sign-up checkbox "confirm I am 18 or older" and its error text |
| `lib/screens/legal/terms_of_service_screen.dart` §2 | eligibility and closing under-age accounts |
| `lib/screens/legal/privacy_policy_screen.dart` §1 (agreement record) and §8 (Age) | age confirmation stored; adult-only statement |
| Backend `users.age_confirmed` and `POST /api/v1/auth/consent` | a single boolean; no age or date of birth, no parent link |
| Backend `Dockerfile`/config | nothing age-specific, but the consent route has no parental branch |
| Store listings and questionnaires (not in the repo) | target audience, content rating, data safety, families/children policies |
| `test/privacy_policy_polish_test.dart` | asserts 18 and no "13", "16" or "parental" in the documents; update it with the change |

## What changes legally and technically (summary, not legal advice)

1. **Under-18 data handling.** Today Flowstate states it does not knowingly process minors' data. Supporting 13-17 means it will.
   Under India's DPDP Act 2023 a child is anyone under 18, and processing a child's data needs verifiable parental consent,
   and tracking, behavioural monitoring and targeted advertising aimed at children are restricted. Flowstate builds a behavioural
   profile (focus, energy, skip history) to personalize plans, so this needs specific advice. Other regions use different thresholds
   (for example 13 under US COPPA, 13-16 under GDPR depending on the country).
2. **Parental consent.** Needs a real mechanism: collecting a parent's contact, verifying the parent, recording consent, letting
   the parent review and withdraw. A checkbox saying "a parent agreed" does not meet this and must not be added.
3. **Backend work.** Date of birth or age band, a consent record per child, a parent contact, withdrawal and deletion flows, and
   gating features by age. None of it exists, so it needs backend changes.
4. **AI processing.** Build My Day sends free text to an external AI service. For minors that disclosure, and whether to allow it at all,
   needs review. A way to switch AI processing off per account does not exist (no backend support).
5. **App-store policy.** An app aimed at or appealing to under-18s (and especially under-13s) falls under the stores' family/children
   rules, which restrict SDKs, ads, analytics and data collection and require specific disclosures. Pro subscriptions and Shield
   purchases and rewarded ads would need review for minors.
6. **Copy.** Terms and Privacy Policy need minor-specific sections (what is collected, parent rights, contact for parents).

Recommendation: keep 18+ for launch. Revisit 13+ with a lawyer once there is a parental-consent design and backend support.
