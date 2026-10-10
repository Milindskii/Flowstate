/// Single source for facts that appear in more than one legal or consent surface.
///
/// Changing [kMinimumAge] is NOT a copy edit. It changes who may hold an account, so it needs the
/// review listed in docs/legal/age-13-review.md (parental consent, minor data handling, store policy)
/// and backend support first. Until then the Terms, Privacy Policy and sign-up checkbox all read it from here.
const int kMinimumAge = 18;

/// Shown on the Terms and the Privacy Policy. Update both documents together.
const String kLegalLastUpdated = 'October 2026';

/// Contact already published in the app before this pass (Legal Hub, Terms, Privacy Policy).
const String kLegalContactEmail = 'Milindkrishnan24@gmail.com';
