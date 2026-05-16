Looking to report an issue/bug or make a feature request? Please refer to the [README file](https://github.com/sjoygsh/Mohyeong#issues-feature-requests-and-contributing).

---

Thanks for your interest in contributing to Mohyeong!

Mohyeong is a fork of [Mihon](https://github.com/mihonapp/mihon), itself a continuation of Tachiyomi. Contributions are welcome but please keep in mind that this fork is primarily maintained by a single developer with AI assistance (Claude / Anthropic).


# Code contributions

Pull requests are welcome!

If you're interested in taking on [an open issue](https://github.com/sjoygsh/Mohyeong/issues), please comment on it so others are aware.
You do not need to ask for permission nor an assignment.

## Prerequisites

Before you start, please note that the ability to use the following technologies is **required** and that existing contributors will not actively teach them to you.

- Basic [Android development](https://developer.android.com/)
- [Kotlin](https://kotlinlang.org/)

### Tools

- [Android Studio](https://developer.android.com/studio)
- Emulator or phone with developer options enabled to test changes.


# Forks

Forks are allowed so long as they abide by [the project's LICENSE](https://github.com/sjoygsh/Mohyeong/blob/main/LICENSE).

When creating a fork, remember to:

- To avoid confusion with this project:
    - Change the app name
    - Change the app icon
    - Change or disable the [app update checker](https://github.com/sjoygsh/Mohyeong/blob/main/app/src/main/java/eu/kanade/tachiyomi/data/updater/AppUpdateChecker.kt)
- To avoid installation conflicts:
    - Change the `applicationId` in [`build.gradle.kts`](https://github.com/sjoygsh/Mohyeong/blob/main/app/build.gradle.kts)
