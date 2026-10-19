### Internal
- The route in progress re-checks itself only when its own database saves. It listened to every save in the process. In the app there's one database, but the tests make many, and a save in one test ran another test's check inside it on the main thread, which deadlocked against CoreData's queue. That's what hung about half of CI's test runs from 2026-10-18 (#190's first run, #193).
