# Research notes — Neon Roadster (iOS)

Date: 2026-10-24

## Inspiration

- X post: cyberpunk city + flying cars, Opus + Three.js ([buildwithsid](https://x.com/buildwithsid/status/2114004943996846516))
- Viral Roadster games after Tesla unveil: Roadster City, Tesla Run, Roadster Unbound (browser / Three.js, thrusters, neon city, mobile sticks)

## Framework matrix (Apple 2025–2026)

| Tech | Status | Fit |
| --- | --- | --- |
| RealityKit + RealityView | Active, expanding (tvOS too) | **Best for new native 3D** |
| SceneKit | Soft-deprecated WWDC25 | Skip for new apps |
| SpriteKit | Active | 2D only |
| Metal | Active (Metal 4 / MetalFX) | Custom renderer later |
| GameplayKit | Stable | AI / state later |
| GameController | Active | Controllers Phase 1.5 |
| GameKit | Active | Leaderboards Phase 2 |
| Unity | Third-party | Cross-platform later |

## RealityView gotchas found while building

1. `content.camera = .virtual` required for non-AR; add an explicit `PerspectiveCamera`.
2. `RealityViewEnvironment` only exposes `.default` and `.skybox(_:)` — **no** `.background = .color`. Use an inverted sphere for a night sky.
3. `RealityView.update` is not a game loop by itself — wrap with `TimelineView(.animation)` or subscribe to `SceneEvents.Update`.
4. Prefer procedural meshes for Day-1; Reality Composer Pro USDZ for Phase 3 fidelity.

## Same-day distribution

1. Xcode → device (immediate)
2. Archive → App Store Connect → Internal TestFlight (hours)
3. App Store public (review — usually not same day)

## Branding

Do not ship Tesla / SpaceX marks. Fantasy “neon roadster” only.
