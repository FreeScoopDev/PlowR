### Internal
- CI tests run on Xcode 27 (GitHub's `xcode-27` image), and Release Flow moves to Xcode 27.2 with them. Apple accepted 1.10.0's upload with a warning (ITMS-90725): from April 2027 an upload must be built with the iOS 27 SDK. CI and the release build move together so the tests keep checking what ships. The deployment target stays iOS 26.0.
