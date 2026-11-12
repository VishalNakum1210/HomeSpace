# Login and registration frontend — 0.8.0

The Android entry point now opens Login, with Registration accessible through
Create account. The pages follow the approved two-screen design: bundled Nunito,
existing native house logo, white background, navy headings, rounded outlined
fields, green tactile buttons, and the exact approved garden illustrations.

`assets/illustrations/auth-layout-approved.png` is the original approved design
image. `AuthPage` displays only its illustration regions, with proportional
clipping; the form, text, buttons and logo are native Flutter widgets. The
illustrations are raster artwork, not SVGs. The rest of the existing vector
artwork system remains available. Reference dimensions are 1296 × 1213.

Login validates email and a nonempty password. Registration additionally
validates name, an eight-character password minimum, and matching confirmation.
Password visibility, keyboard Next/Done, scrolling on small screens, large
text, and Back from Registration to Login are supported. Switching forms clears
passwords and resets scrolling.

This remains a frontend preview. Valid submissions explicitly explain that no
account is created and offer Continue to preview. Password recovery explains
that no email is sent. No credentials or account tokens are stored. A backend
must replace this preview handoff before real authentication is available.

Profile has a Log out button. Logout clears the in-memory preview session,
removes the library navigation stack and returns to a fresh Login page without
deleting the saved library. Opening the app again starts on Login. The saved
library theme is restored when entering the library; authentication screens use
the approved light design.

The Android entry point supplies a `FrontendSession`. Tests and standalone
library previews can omit it to render the library directly.

Validation: `test/auth_flows_test.dart` covers form errors, matching passwords,
visibility, Back, credential clearing, preview entry/logout, and 320px-wide
large-text keyboard navigation. Capture with `HOMESPACE_CAPTURE=true` writes
`output/previews/auth-login.png` and `auth-registration.png`.

Verification completed: Flutter analysis reports no issues and the full suite
passes all 103 tests (including the three authentication flow tests). The two
rendered pages were visually reviewed against the approved image.

Android release APK build succeeded. The development-signed preview is archived
at `output/releases/homespace-android-0.8.0+15-preview.apk`. It has not been
installed on the phone during this change.
