# Getting Spectra onto your iPhone

An .ipa has to be compiled with Xcode and signed with an Apple certificate that includes your
iPhone, so it cannot be produced without a Mac/Xcode and your Apple ID. Pick one route:

## A. Xcode on a Mac (simplest, free Apple ID is enough)
1. `brew install xcodegen && xcodegen generate && open Spectra.xcodeproj`
2. Xcode > Spectra target > Signing & Capabilities > pick your Team (your Apple ID), and change
   the bundle identifier to something unique (e.g. com.yourname.spectra).
3. iPhone: Settings > Privacy & Security > Developer Mode > On (restarts the phone).
4. Plug in the iPhone, choose it as the run destination, press Run.
   Free Apple ID builds expire after 7 days; a paid developer account lasts a year.

## B. No Mac: build in the cloud, then sign and install
1. Put this folder in a GitHub repository (the workflow is in .github/workflows/build-ipa.yml).
2. Actions tab > "Build IPA" > Run workflow. It runs the unit tests, then uploads
   `Spectra-unsigned.ipa` as an artifact.
3. Sign and install the unsigned IPA with your Apple ID using Sideloadly or AltStore
   (Windows or macOS), with Developer Mode on as above.

## C. TestFlight (paid Apple Developer account)
Archive in Xcode > Distribute App > App Store Connect > install through TestFlight.
