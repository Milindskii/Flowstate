# Privacy and Terms: facts that could not be verified, and decisions needed

Written against the code on 2026-10-10. Nothing here was invented in the in-app policies; each item is either left out of the
policy or stated as a limitation.

## Needs a backend change (not done in this pass)

1. **Account deletion leaves the Supabase sign-in record.** `DELETE /api/v1/auth/me` deletes the app database user and cascades.
   Nothing calls Supabase's admin API, so the email and credentials in Supabase Auth remain. The Privacy Policy and the delete
   dialog now say so and ask users to email. Fix: call Supabase admin delete from the backend.
2. **The 24-hour AI replay purge never runs.** `purge_old_requests` exists in `backend/app/services/ai_gateway.py` but is not
   called anywhere. Replay bodies in `ai_requests.response_json` are therefore not cleared after 24 hours, and `plan_applications.response_json` and
   `ai_planning_requests.response_json` have no purge at all. All are kept until the account is deleted. The policy makes no 24-hour claim.
3. **Data export is partial.** `POST /api/v1/auth/export-data` returns account, preferences, tasks, flow profile and companion
   summary. It omits setup answers, performance/reflection history, routines, skip/miss history, shield ledger and usage records.
   The policy says it is a summary. Fix: widen the export, or decide to handle full requests by email.
4. **No per-account switch for AI processing**, so there is deliberately no toggle in the app. The only control is the pre-send
   notice (Cancel sends nothing; the basic planner and manual entry still work).
5. **Two onboarding answers are collected but unused and never sent**: `unpredictable_cue`, `schedule_disruptors`. Product
   decision: use them, or remove the questions in a later pass (question count was frozen for this one).

## Needs your decision or a fact only you have

1. **Retention periods** for server logs, backups and deactivated accounts. None are defined; the policy says so.
2. **Google's handling of Build My Day text.** Which Gemini API tier and terms are in use, and whether data is retained or used for
   model improvement. The old policy claimed "enterprise API ... not used to train"; that was unverifiable and was removed.
3. **Hosting provider and region** of the FastAPI server and database (the policy says "our hosting provider" and names Supabase
   only for sign-in and the database). Name them and the region once confirmed.
4. **Transport security.** HTTPS/TLS is not asserted anywhere. Confirm production settings, then add one sentence.
5. **How policy updates are communicated.** The policy says the date changes and a notice "may" be shown. Decide whether to build an
   in-app "policy updated" prompt and re-consent.
6. **Contact channel.** Only the existing personal email is published. Consider a dedicated address and a response time you can keep.
7. **Whether the in-app grievance form reaches you.** `POST /api/v1/auth/grievance` stores a record; nothing notifies anyone.
   Confirm someone reads that table.
8. **Refund Policy screen** still says "Should Flowstate introduce any optional premium ... subscription in the future" and
   promises a 14-day refund by email in 3-5 business days, while Pro subscriptions and Shield packs go through the store. Not edited
   in this pass (out of scope); it conflicts with the Terms' statement that store billing and refund rules apply.
9. **Cookie/Local Storage screen** has not been changed; its claims (no ad trackers, essential local storage) match the app today.
   The backend has config for rewarded ads (AdMob SSV) that is off by default; if ads ship, the Privacy Policy, Cookie screen and
   store disclosures must change first.
10. **Lawyer review.** Both documents say they have not been legally reviewed. Decide when that happens (before store submission).
11. **Splash text** "Your data stays yours" replaced "Private & Local", which was inaccurate. Replace with whatever you prefer.

## Store submission (not claimed anywhere in the app)

Play Data safety form, content rating and the account-deletion web URL are all still to do. The Legal Hub says a web deletion
page is not available yet.
