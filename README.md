# Control Card

A rally control card app for iPhone and iPad, built with SwiftUI and Core Data.

## Build requirements

| | |
|---|---|
| Xcode | **26 or later** |
| iOS SDK | **26 or later** |
| Deployment target | iOS 17.6 |
| Swift language version | 5 |

Apple requires every app uploaded to App Store Connect to be built with the
iOS 26 SDK or later. An archive produced by an older Xcode is rejected at
upload with:

> SDK version issue. This app was built with the iOS 18.2 SDK. All iOS and
> iPadOS apps must be built with the iOS 26 SDK or later, included in Xcode 26
> or later, in order to be uploaded to App Store Connect or submitted for
> distribution.

The project does not pin an SDK — `SDKROOT` is set to `iphoneos`, which always
resolves to the newest iOS SDK in the Xcode that runs the build. The SDK the
archive records is therefore decided entirely by which Xcode you archive with,
so the fix is to install Xcode 26+ and re-archive. No project setting needs to
change.

Raising the SDK does not raise the deployment target: the app still runs on
iOS 17.6 and later.

## Selecting the toolchain

Check which Xcode the command line is pointed at:

```sh
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version    # must report 26.x or later
```

If an older Xcode is selected, point at the new one and confirm:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

When several Xcodes are installed, keep them under distinct names
(`Xcode-26.app`, `Xcode-16.app`) and pass the path explicitly above.

## Archiving for the App Store

Build the archive from the command line:

```sh
xcodebuild -project "Control Card.xcodeproj" \
           -scheme "Control Card" \
           -configuration Release \
           -destination "generic/platform=iOS" \
           -archivePath build/ControlCard.xcarchive \
           archive
```

Or in Xcode: select **Any iOS Device** as the run destination, then
**Product ▸ Archive**, and upload from the Organizer.

Verify the SDK recorded in the built app before uploading. Xcode stamps it
into the bundle's `Info.plist` as `DTSDKName`:

```sh
plutil -extract DTSDKName raw \
  "build/ControlCard.xcarchive/Products/Applications/Control Card.app/Info.plist"
```

Anything below `iphoneos26.0` will be rejected again.
