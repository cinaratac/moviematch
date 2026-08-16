# App Privacy answers

These answers reflect the current code: local game progress plus Google Mobile Ads and App Tracking Transparency. Re-check them against the current Google Mobile Ads disclosure immediately before submission.

## Does this app collect data?

Select **Yes** because the included advertising SDK may collect data.

## Data types to declare for Google Mobile Ads

- Location → Coarse Location
- Identifiers → Device ID
- Usage Data → Advertising Data
- Usage Data → Product Interaction
- Diagnostics → Crash Data
- Diagnostics → Performance Data

For each data type, select the purposes that match the options shown by App Store Connect and Google's current disclosure. Typical purposes include Third-Party Advertising, Analytics, and App Functionality. Device ID and advertising data may be used for tracking when the user grants ATT permission.

## Data not collected by the app itself

- Name, email, phone number, or physical address
- User account or login credentials
- Payment or financial information
- Contacts, photos, audio recordings, or precise location
- Health, fitness, or sensitive information

## Local-only data

Level progress, earned coins, and selected/owned arrow styles are stored on the device with SharedPreferences and are not sent to the developer's server.

## Required URLs

- Privacy Policy URL: https://cinematchsocial.web.app/meteors-vs-planets-privacy-policy
- User Privacy Choices URL: optional; add one if you provide a web-based opt-out page

Important: AdMob consent messages for the EEA/UK/Switzerland and applicable U.S. states must be configured in the AdMob Privacy & messaging console before worldwide release.
