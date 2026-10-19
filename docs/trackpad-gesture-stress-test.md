# Trackpad gesture stress test

Use this on the `fix/trackpad-gesture-event-leak` branch. The change holds trackpad scrolls, page-swipes, and pinches until Loop either takes the stroke or lets it go. A few cases are still supposed to look a little odd. Those are called out below so a real bug is easier to separate from them.

Quit any other copy of Loop first. Two copies share a bundle ID, so macOS will keep the one that is already running. Build and run the **Loop** scheme as **Debug**, with this environment variable set on the scheme:

`LOOP_GESTURE_DEBUG_OVERLAY` = `1`

That draws the gesture overlay. The teal ring meeting the green ring is the first pinch threshold.

Before starting, write down System Settings → Trackpad for:

- Swipe between pages
- Swipe between full-screen apps
- Mission Control
- App Exposé
- Notification Center

In Loop → Gestures, turn **Trackpad gestures** on and use this set. Leave the default two-finger **Both** / **Title Bar Only** radial menu in place.

| Fingers | Kind | Zone | Action |
| --- | --- | --- | --- |
| 3 | Swipe Left | Anywhere | Left half |
| 3 | Swipe Right | Title Bar Only | Right half |
| 3 | Pinch | Anywhere | Center |
| 4 | Swipe Up | Anywhere | a cycle action, such as grow |
| 4 | Spread | Anywhere | Maximize |

Two-finger gestures are always title-bar only, even if the zone says Anywhere.

Four-finger spread is the same motion macOS uses for Show Desktop. Loop holds that system gesture for the whole pinch, in either direction, and selects Maximize once the teal ring reaches the green ring. Lifting while the teal ring is still outside that ring applies it. Pinching back inside the green ring clears the preview. Spreading past it again selects Maximize. If the window leaves the screen you are watching, check the display under the pointer.

Front apps for the passes: Safari on a long page, a page that scrolls sideways, Finder, one fullscreen app, and one app excluded in Loop.

## What should be true after this fix

- A bound swipe or pinch moves the window and does **not** also scroll, go back, or zoom the page.
- An unbound direction still does the system thing (Spaces, Mission Control, App Exposé) or the app thing (scroll, zoom), and Loop stays out of it.
- After every stroke, a normal two-finger scroll and a mouse-wheel scroll both work.

## Pass 1 — Double trigger

This is the bug the branch is aimed at.

1. In Safari, three-finger swipe left over the page, over a sideways scroller, and over the title bar. Repeat as a slow drag and as a flick.
2. Three-finger swipe right over the page body, then again starting on the title bar.
3. Three-finger pinch over a zoomable page, then four-finger spread over the same page.
4. Two-finger scroll through the page body. It should scroll and should not open the radial menu. Then two-finger swipe on the title bar. The radial menu should open and the page should not scroll.

Failure: the window moves and the page also scrolls, navigates, or zooms. Note whether it was the first few pixels only, or the whole stroke.

## Pass 2 — System gestures you did not bind

1. Three-finger swipe up and swipe down. Those are not bound. Spaces, Mission Control, or App Exposé should run, and the Dock should not stick mid-swipe.
2. Four-finger swipe left and right. Same check.
3. Open Mission Control, then repeat a bound three-finger swipe. The system gesture should keep working while Mission Control is open.
4. Swipe in from the edge for Notification Center, if that uses a finger count you also bound.

Failure: a half-finished Dock animation, or Loop taking a direction it does not bind.

## Pass 3 — Messy strokes

1. Three-finger swipe along a diagonal, then one that starts diagonal and straightens.
2. Swipe left past the point where the window changes, then reverse back through the start.
3. Move just far enough to see a preview, then return to the start without lifting.
4. Start with three fingers and add a fourth. Lift the fingers one at a time.
5. Flick-scroll the page, and before the coasting stops, do the three-finger swipe.

The diagonal can freeze the page until you lift, then the page may jump. That is expected: Loop still treats every angle as some direction, so the stroke is held until it is clearly not the bound one. A jump on an unbound diagonal, or scrolling that stays dead after every finger is up, is a bug.

## Pass 4 — Wrong window

1. Put the pointer on window A and gesture at window B.
2. Start a title-bar-only swipe just outside the title bar, then one that starts on the bar while a resize animation is still running.
3. Gesture a window on a second display.
4. Gesture a fullscreen window, then a normal one.
5. Gesture an excluded app, then a window of that app you still want Loop to manage, if you have one.

Title-bar detection uses the pointer, not the fingers. A gesture landing on the window under the pointer is expected. A title-bar gesture that falls through to Mission Control while Loop is busy animating is the 40ms lookup miss. Worth recording, especially if it is easy to repeat.

## Pass 5 — Recovery

1. Focus a password field, gesture, then leave the field and gesture again.
2. Sleep the Mac mid-gesture, wake it, and scroll.
3. If you have an external trackpad, unplug it with fingers still down, then scroll on the built-in pad.
4. After each of those, two-finger scroll and the mouse wheel should both still work.

Failure: the trackpad stays dead until Loop is restarted.

## Pass 6 — Spread, commit, and cancel

1. Four-finger spread over a window until the teal ring meets the green ring. A Maximize preview should appear. Lift while the teal ring is still outside the green ring. The window should maximize, and the page underneath should not zoom. Show Desktop should not run.
2. Spread again until the preview appears, then pinch until the teal ring comes back inside the green ring. The preview should clear. Lift. The window should stay where it was.
3. After that cancel, spread past the green ring again without lifting. Maximize should come back. Lift to apply it.

Failure: the preview never appears, lift outside the green ring does nothing, coming back inside the green ring leaves the preview up, or Show Desktop hides the windows.

## Still expected, not a regression

- One finger left down after a Loop swipe keeps eating scrolls until every finger lifts.
- A stroke Loop almost takes, then abandons, can replay as a short jump in the page.
- Smart zoom (two-finger double-tap) is not held. The page can still zoom on that.
- A Magic Mouse scroll is not part of this path. If it stutters while gestures are on, write that down separately.
- The first scroll sample can still leak if it arrives before Loop has seen the fingers. If Pass 1 only fails on a very fast flick, and only by a few pixels, that is this race.

## What to record

For each failure: this branch, finger count, direction, Anywhere or Title Bar Only, the front app, whether that app also reacted, and a short screen recording. The overlay is useful when the direction or the threshold looks wrong.

A useful note for the author, in Discord or a GitHub issue, is one paragraph per failure plus the recording. Include which pass, whether you lifted or pinched back, and whether clicks and typing still worked afterward. Passes that behaved as written can be a single line.
