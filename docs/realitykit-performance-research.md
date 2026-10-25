# Neon Roadster — RealityKit performance research (iOS 26/27)

**Scope:** Xcode 27.0 (27A266a), iOS SDK 27.0, Swift 6.3, target iPhone. Everything below was checked against the iOS 27 SDK on this machine — API availability was determined by **compiling** snippets at `-target arm64-apple-ios18.0 / 26.0 / 27.0`, and triangle counts were **measured** by running the same `MeshResource` generators the project uses. Sources are Apple docs / WWDC transcripts; blog speculation is avoided.

**Repo state at time of reading** (it changed while I was reading it — the frame loop was already migrated off `TimelineView`): `GameView.swift:132` now uses `RealityView { }` + `content.subscribe(to: SceneEvents.Update.self)`, `GameSession.tick(dt:)`, and a 10 Hz HUD snapshot. That part is now correct. The remaining problems are **geometry and draw calls**, not the loop.

---

## 0. Headline findings (measured, not estimated)

### 0.1 `generateBox(cornerRadius:)` is a 1,089× triangle bomb

Measured with the iOS 27 SDK on this machine:

| Generator | Vertices | Triangles |
|---|---:|---:|
| `MeshResource.generateBox(size:)` | 24 | **12** |
| `MeshResource.generateBox(size:cornerRadius: 0.4)` | 6,936 | **13,068** |
| `generatePlane` | 4 | 2 |
| `generateSphere(radius: 900)` | 4,223 | 8,064 |
| `generateCylinder` | 260 | 256 |
| `generateCone` | 194 | 128 |

`cornerRadius` is not a "slightly rounded box" — it produces a tessellated rounded-edge extrusion. Same cost regardless of size.

**What that means for the current scene:**

| Content | Count | Tris each | Subtotal |
|---|---:|---:|---:|
| Building bodies (`cornerRadius: 0.4`) | 220 | 13,068 | **2,874,960** |
| Building crowns (plain box) | 220 | 12 | 2,640 |
| Antennas | ~110 | 12 | 1,320 |
| Ring torus + hole (both rounded) | 48 | 13,068 | **627,264** |
| Roadster rounded parts (body/cabin/nose/thruster) | 4 | 13,068 | 52,272 |
| Sky sphere | 1 | 8,064 | 8,064 |
| Streets/neon/ground/wheels | ~130 | 12–256 | ~3,000 |
| **Total** | | | **≈ 3.57 M triangles** |

And **≈ 660 draw calls** (every `ModelEntity` = 1 mesh = 1 draw; see §1.1).

Dropping `cornerRadius` and merging by material takes this to **≈ 8 draw calls and ≈ 8 k triangles**. That is the single highest-leverage change available, and it is ~30 lines of code (§2.2).

### 0.2 The loop is fixed; the frame budget is now the problem

Apple's own guidance: *"For the best user experience, keep both the main and render threads below about 12 ms on average"* — [Reducing CPU Utilization in Your RealityKit App](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app). At 120 Hz the whole budget is **8.33 ms**. 660 draws × ~15–25 µs encode ≈ 10–16 ms of pure CPU encode — i.e. the city alone can miss 120 Hz and half of 60 Hz before a single pixel is shaded.

---

## 1. RealityKit rendering model on iOS 26/27

### 1.1 Draw calls: one per mesh, full stop

Apple, verbatim:

> "Because RealityKit invokes a draw call for each mesh, having more meshes consumes more CPU time. To reduce render thread time, merge meshes that share a material when possible."
> — [Reducing CPU Utilization in Your RealityKit App](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app)

So the cost model is:

- **1 `ModelComponent` = 1 mesh = 1 draw call**, regardless of how many triangles.
- Sharing a `MeshResource` between entities does **not** merge draws — each entity is still its own draw (unless you use instancing, §1.2).
- Material changes on one mesh force a separate draw per material.
- RealityKit auto-merges *only* when you load a **USDZ/Reality file** as a `ModelEntity` (`Entity(named:)` / `ModelEntity(named:)`). Programmatically built entity trees are **not** auto-merged. Quote: *"RealityKit does this for you automatically to the extent that it can when you load an entity in a usdz file as a ModelEntity."*

**Consequence:** cloning `ModelEntity`s (or building 220 of them) is the worst case. `Entity.clone(recursive:)` (iOS 13+) shares the `MeshResource` *reference* but still creates one `ModelComponent` → one draw per clone.

### 1.2 Instancing (iOS 26+) — `MeshInstancesComponent`

New in iOS 26 (verified: `'MeshInstancesComponent' is only available in iOS 26.0 or newer`):

> "A component that performs GPU instancing on the model of the same entity." — [MeshInstancesComponent](https://developer.apple.com/documentation/realitykit/meshinstancescomponent)

From WWDC25 session 287 (*What's new in RealityKit*, chapter 12:26):

> "The MeshInstancesComponent allows you to draw a mesh multiple times with a single entity… Instead of sending multiple copies of the model and materials to the GPU when drawing duplicate meshes, the MeshInstancesComponent will only send that data once."
> "On iOS, iPadOS, macOS, and tvOS you can use a LowLevelBuffer to pass render data to your CustomMaterial to make each mesh instance look unique."

That last sentence is the **per-instance colour** answer: one instanced mesh + a `LowLevelBuffer` of per-instance colours + a `CustomMaterial`. For 5–8 palette colours you do **not** need this — 5–8 merged meshes is cheaper and simpler (§2).

```swift
// Verified compiling against iOS 26/27 SDK.
@available(iOS 26.0, *)
@MainActor
func makeInstancedBucket(mesh: MeshResource, transforms: [float4x4]) throws -> Entity {
    let entity = Entity()
    let data = try LowLevelInstanceData(instanceCount: transforms.count)
    data.withMutableTransforms { buffer in
        for i in transforms.indices { buffer[i] = transforms[i] }
    }
    entity.components.set(try MeshInstancesComponent(
        mesh: mesh,
        modelID: mesh.contents.models.first?.id,
        instances: data
    ))
    return entity
}
```

Notes:
- Instance transforms are in the **entity's local space** — move the group with the entity's transform (documented in the component overview).
- `LowLevelInstanceData.withMutableTransforms(_:)` takes `(UnsafeMutableBufferPointer<float4x4>) -> Void`.
- Older equivalent (iOS 15+): `MeshResource.Contents.instances` / `MeshResource.Instance(id:model:at:)` / `MeshInstanceCollection`. Baked into the mesh, so it's static — fine for a city, not for animated props.

### 1.3 ECS, `System`, `SceneEvents.Update` vs `TimelineView`

- `SceneEvents.Update` — *"An event invoked once per frame interval"*, with `event.deltaTime: TimeInterval` ([docs](https://developer.apple.com/documentation/realitykit/sceneevents/update)).
- Apple explicitly endorses this for games: *"If you want to run code every frame (to do animations or simulations), you can use a `System` or directly subscribe to the engine's `SceneEvents.Update`"* — [RealityView docs](https://developer.apple.com/documentation/realitykit/realityview), with a code sample.
- `System` (`update(context:)`, `SceneUpdateContext.deltaTime`) is for **multi-entity continuous behaviour** and is dependency-ordered (a DAG). Use a `System` when many entities share behaviour; use `content.subscribe` for a single game-world driver. Don't put game state in the `System` object (it isn't serialized/synced) — put it in components.
- **`TimelineView(.animation)` around `RealityView` is an anti-pattern**: it re-evaluates the SwiftUI `body` every frame, which re-runs the `update` closure, which (in the old code) mutated `@Observable` state, which invalidated the view again. It also produced the "one frame then frozen" behaviour if no observable property changed. The current `SceneEvents.Update` approach is correct; keep `RealityView`'s `update` closure only for *state-driven* changes (pause, menu, restart).
- **`@Observable` + per-frame writes is the second trap.** Even now, `publishHUD()` at 10 Hz writes 7 observable properties → 7 potential invalidations of `HUDView`. Better: one `struct HUDSnapshot` property written once per tick, so SwiftUI sees a single change. Keep the *simulation* state (`position`, `yaw`, `velocity`) in a plain non-`@Observable` class owned by `GameWorld`; nothing in SwiftUI needs it.
- Threading: RealityKit delivers `SceneEvents.Update` on the main thread, and `RealityViewContent`/`PerspectiveCamera` are `@MainActor`. Do not hop to a background actor inside the handler — compute, don't dispatch. Heavy procedural generation (city build) should happen **before** `content.add`, or in a `Task` that fills a buffer and swaps it in (§9).

### 1.4 Frame pacing

**There is no `preferredFramesPerSecond` / `maximumFramesPerSecond` anywhere in RealityKit or RealityFoundation in the iOS 27 SDK** (verified by grepping the SDK frameworks — zero hits). You cannot ask `RealityView` for 120 Hz. RealityKit drives its own display link; what you control is:

1. **Whether your frame fits** in 8.33 ms (120 Hz) / 16.67 ms (60 Hz).
2. **Present mode** — the Metal HUD reports *direct* vs *composited*. Composited (e.g. when the app is in a system-composited context) can cap or add latency. Check this before chasing phantom frame drops.
3. For SwiftUI-side animation (HUD, menus), `TimelineView(.animation(minimumInterval: 1.0/120.0))` is fine — it's cheap when it only redraws a few `Text`s, and it does not affect RealityKit's cadence.

Verify actual cadence with the Metal HUD's *frame interval* metric, not with assumptions.

---

## 2. Merging the city: the concrete plan

### 2.1 Decision matrix

| Approach | Draws (city) | Works on | Culling | Use when |
|---|---:|---|---|---|
| 220 `ModelEntity`s (today) | ~660 | iOS 13 | per building | never |
| `clone(recursive:)` ×220 | ~660 | iOS 13 | per building | never |
| **Merge per material** | **6–8** | iOS 15 | whole city | **this game** (geometry is tiny) |
| Merge per material **per 120 m chunk** | ~50–60 | iOS 15 | per chunk | when you add windows/greebles |
| `MeshInstancesComponent` per material | 6–8 | **iOS 26** | whole group | thousands of identical props |
| `LowLevelRenderer` + manual cull/sort | full control | **iOS 27** | manual frustum | last resort / custom renderer |

**Why global merge wins here:** 220 boxes = 2,640 triangles. Apple warns that merging hurts culling (*"it does render the entirety of any mesh that's even partially visible"*), but that warning is about heavy meshes. At 2.6 k triangles, vertex cost is noise; you are trading nothing for 650 fewer draw calls. Revisit chunking only when a building becomes 1–2 k triangles of detail.

### 2.2 Merged box builder (verified compiles, iOS 15+)

```swift
struct BoxBatch {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals:   [SIMD3<Float>] = []
    private(set) var indices:   [UInt32] = []

    mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>) {
        let h = size * 0.5
        // (normal, tangentU, tangentV) per face — outward winding, CCW
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            ([ 1, 0, 0], [0, 1, 0], [0, 0,  1]),
            ([-1, 0, 0], [0, 1, 0], [0, 0, -1]),
            ([0,  1, 0], [0, 0, 1], [ 1, 0, 0]),
            ([0, -1, 0], [0, 0,-1], [ 1, 0, 0]),
            ([0, 0,  1], [ 1, 0, 0], [0, 1, 0]),
            ([0, 0, -1], [-1, 0, 0], [0, 1, 0]),
        ]
        for (n, u, v) in faces {
            let base = UInt32(positions.count)
            let c = center + n * h, du = u * h, dv = v * h
            positions.append(contentsOf: [c - du - dv, c + du - dv, c + du + dv, c - du + dv])
            for _ in 0..<4 { normals.append(n) }
            indices.append(contentsOf: [base, base+1, base+2, base, base+2, base+3])
        }
    }

    func makeMesh(name: String) throws -> MeshResource {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals   = MeshBuffers.Normals(normals)
        d.primitives = .triangles(indices)          // UInt32 indices
        return try MeshResource.generate(from: [d])
    }
}
```

Usage: one `BoxBatch` per palette bucket → one `MeshResource` → one `ModelEntity` with one `UnlitMaterial`. Six buckets total (`dark body`, `street`, `ground`, 5 neon) ≈ **7 draws**.

### 2.3 Per-material vs per-vertex colour

- **`MeshDescriptor` has no vertex-colour semantic.** Its buffer semantics are `positions`, `normals`, `tangents`, `bitangents`, `textureCoordinates`/`uv2…uv7`, `jointInfluences`, `triangleIndices`, plus `MeshBuffers.custom(_:type:)`. There is no `.colors`. So "one mesh, per-vertex colour, built-in material" **does not exist** in RealityKit.
- `LowLevelMesh.VertexSemantic.color` **does** exist (iOS 18+), but built-in `UnlitMaterial`/`SimpleMaterial` won't read it — you'd need a `CustomMaterial` with a Metal surface shader. Real, but a lot of machinery for 5 colours.
- **Recommended:** 5–8 merged meshes, one `UnlitMaterial` each. Zero shader code, one draw per colour, and you can still vary *tone* by bucketing buildings into e.g. 3 dark materials.
- **If you truly want 1 draw:** bake a 1×8 **palette texture** and put the palette index in the UV.y of each face, then use `UnlitMaterial(texture:)`. Verified compiles:
  ```swift
  let tex = try TextureResource.generate(from: cgImage, withName: "palette",
                                         options: .init(semantic: .color))
  let mat = UnlitMaterial(texture: tex)
  ```
  For boxes this is easy (UV.v = palette row). It costs one 8×1 texture and gives one draw for the entire neon layer.

### 2.4 Rings

24 rings × 2 meshes = 48 draws and 627 k triangles (both parts use `cornerRadius`). Options, best first:

1. **Plain boxes, merged per ring** → 24 draws, 24×24 = 576 triangles. Simplest.
2. **One `MeshInstancesComponent`** with 24 instances → **1 draw**. Collected rings: zero the instance's scale in the transform buffer (per-instance culling for free). Verify that mutating `LowLevelInstanceData` after install re-uploads; if not, re-set the component (or use `replaceMutableTransforms`).
3. Keep the "dark core" hack but merge torus+hole into one mesh with `MeshDescriptor.materials` (`.all([...])` / per-primitive), so it's 1 draw per ring.

### 2.5 Sky

The 900 m sphere is 8,064 triangles and one full-screen fill. Two better options:

- **Cheapest:** `EnvironmentResource(equirectangular:withName:)` from a tiny generated `CGImage` (verified iOS 18+), then `content.environment = .skybox(env)`. Zero geometry, and it doubles as image-based lighting:
  ```swift
  let env = try EnvironmentResource(equirectangular: nightImage, withName: "night")
  content.environment = .skybox(env)
  ```
- **If you keep geometry:** a 12-triangle inverted box attached to the camera beats an 8,064-triangle sphere, and avoids parallax.

`RealityViewEnvironment` only offers `.default` and `.skybox(EnvironmentResource)` — there is no solid-colour API (the code comment in `GameView.swift:26` is correct).

---

## 3. Culling, LOD, shadows, collision

### 3.1 What is automatic

| Mechanism | Automatic? | Evidence |
|---|---|---|
| Frustum culling **per mesh** | **Yes** | *"while RealityKit avoids rendering off-screen meshes, it does render the entirety of any mesh that's even partially visible"* (CPU article) |
| Batching across entities | **No** | one draw per mesh (§1.1) |
| Auto-merge of USDZ hierarchies | **Yes** | same article |
| Mipmaps | **Yes** | GPU article |
| Occlusion culling (GPU) | **No public API** for `RealityView` | `ARView.Environment.SceneUnderstanding.Options.occlusion` is *AR* occlusion, unrelated |
| LOD | **No**, until iOS 27 | see 3.2 |

Because culling is per *mesh*, merging the whole city into 7 meshes means the whole city is always "partially visible" → always drawn. That's fine at 2.6 k tris. It is **not** fine once buildings have windows.

### 3.2 LOD — `LevelOfDetailComponent` (iOS 27, new)

Verified availability: `'LevelOfDetailComponent' is only available in iOS 27.0 or newer`. From WWDC26 session 279 (*Explore advances in RealityKit*, chapter 13:42) and the [docs](https://developer.apple.com/documentation/realitykit/levelofdetailcomponent):

```swift
// Verified compiles on iOS 27.
LevelOfDetailComponent.addByCameraDistance(to: parent, levels: [
    (entities: [near], maxDistance: 120),
    (entities: [far],  maxDistance: .infinity)     // last LOD must be .infinity
])

LevelOfDetailComponent.addByScreenArea(to: parent, levels: [
    (entities: [near], minArea: 0.15),              // fraction of screen
    (entities: [far],  minArea: 0.0)
])
```
Also available: `init(levels:switchingAt:)`, `addByResolutionMetric(to:levels:boundingBox:)`, `strategy`, `levelSelection` (`.automatic` / `.fixed(Int)` — the latter is great for benchmarking "LOD 0 only").

**Fallback for iOS 18–26:** manual distance culling in your update loop:
```swift
for chunk in chunks where chunk.entity.isEnabled != (distance(chunk.center) < 400) {
    chunk.entity.isEnabled.toggle()   // cheap; skips render + ECS work
}
```
`Entity.isEnabled` (iOS 13+) and `isEnabledInHierarchy` (read-only) are the right switches — cheaper than `removeFromParent`/`addChild`, and they don't invalidate anything.

### 3.3 Shadows

- **Point lights cannot cast shadows**: there is no `PointLightComponent.Shadow` in the SDK (compile + docs both confirm). Your car's `PointLight` is shadow-free by construction.
- Shadows are **their own component** attached to the light entity — there is *no* `SpotLightComponent.shadow` property (I verified this by compiling; the docs' "Shadow" is a standalone component):
  ```swift
  var sh = SpotLightComponent.Shadow()
  sh.quality   = .medium      // iOS 27 only
  sh.lightSize = 0.7          // iOS 27 only, metres → soft shadow (penumbra)
  entity.components.set(sh)
  ```
  WWDC26 279: `lightSize` defaults to `0` (hard shadow); `quality` **must** be `.medium` or `.high` for softness — `.low` forces hard shadows regardless of `lightSize`.
- `DirectionalLightComponent.Shadow.maximumDistance` is **deprecated in iOS 18** — the compiler says: *"Use `.shadowProjection = .automatic(maximumDistance:)`"*. Use:
  ```swift
  var dsh = DirectionalLightComponent.Shadow()
  dsh.shadowProjection = .automatic(maximumDistance: 60)
  ```
  Cascades exist (`DirectionalLightComponent.Shadow.Cascades`) — cost scales with cascade count.
- `GroundingShadowComponent(castsShadow:)` (iOS 18+) is a cheap contact shadow for **one** hero object (the car). Use it instead of a shadow-casting light for the city.

**Recommendation for this game:** no shadow-casting lights at all. A neon night city reads better with emissive geometry + a single dim directional "moon" (no shadow) + a fake contact shadow under the car. Apple: *"the more lights and shadows you have in the scene, the more work the fragment shader does… reduce the number of distinct lights."*

### 3.4 Collision / `CollisionComponent` cost

Apple: physics cost *"comes primarily from detecting collisions"*; minimise rigid bodies, isolate them spatially, and prefer simple shapes ([CPU article](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app)). Also: *"Use care when calling `generateCollisionShapes(recursive:)`"* — it's a common spike.

For an arcade flyer:
- **Don't** put `CollisionComponent` on 220 merged city meshes (and you can't meaningfully, post-merge).
- Do collision **analytically** against a coarse spatial hash of building AABBs (the generator already knows every box's centre/size). Sphere-vs-AABB and sphere-vs-ring are a few hundred float ops per frame.
- If you need RealityKit hit-testing for input, `CollisionComponent` without a `PhysicsBodyComponent` is a hit-test shape only and is much cheaper than simulation.
- Rings: distance test is already O(n) over 24 — fine; keep it in the fixed-step sim, not in the render callback.

---

## 4. Lighting and post-processing

### 4.1 What `RealityView` actually exposes (verified member list)

`RealityViewRenderingEffects` has exactly: **`antialiasing`, `cameraGrain`, `customPostProcessing`, `depthOfField`, `dynamicRange`, `motionBlur`** — there is **no `bloom` and no `toneMapping`** on the view. Don't write `content.renderingEffects.bloom`; it won't compile.

| Effect | API | Min iOS | Cost on iPhone | Verdict for neon city |
|---|---|---|---|---|
| Motion blur | `.motionBlur` | 18 | Apple: *"particularly expensive"* | **Off** (already) |
| Depth of field | `.depthOfField` | 18 | Apple: *"particularly expensive"* | **Off** (already) |
| Camera grain | `.cameraGrain` | 18 | cheap full-screen | optional, off |
| MSAA | `.antialiasing = .multisample4X / .none` | 18 | bandwidth ×4 | **`.none` at 120 Hz**, 4× at 60 Hz |
| HDR | `.dynamicRange = .default / .standard` | 18 | more bandwidth | `.standard` unless you want EDR neon |
| Custom post | `.customPostProcessing = .effect(_:)` | **26** | your shader | for a cheap fake bloom if < iOS 27 |
| Bloom | `BloomComponent(scope: .hierarchical/.unbounded)` | **27** | 1 blur chain | **on, `.hierarchical` around the neon root** |
| Bloom tuning | `BloomOptionsComponent()` | **27** | — | expose intensity/threshold |
| Tone mapping | `ToneMappingComponent()` | **27** | trivial | on; pair with `UnlitMaterial(color:applyPostProcessToneMap: false)` for pure neon |

`BloomComponent` semantics (docs): *"adds a luminous glow effect around bright objects… If scope is `.unbounded`, Bloom will be computed on the entire screen. If scope is `.hierarchical`, multiple Bloom components can be used to opt in only the regions around certain objects."* — that's exactly what you want: bloom the neon layer, not the whole frame.

```swift
// Verified compiles on iOS 27.
if #available(iOS 27.0, *) {
    neonRoot.components.set(BloomComponent(scope: .hierarchical))
    neonRoot.components.set(BloomOptionsComponent())
    root.components.set(ToneMappingComponent())
}
```

**Cheapest bloom of all (any iOS):** additive billboard quads / `UnlitMaterial` sprites behind the neon strips. No post pass, no bandwidth. For a stylised game this often looks better than real bloom.

### 4.2 Lighting rules for this scene

- `UnlitMaterial` for **all** neon, streets, ground, sky → no lighting math at all. This is the biggest fragment-shader saving and it's already partly done.
- `SimpleMaterial`/`PhysicallyBasedMaterial` only for the car body (4–5 meshes).
- **One** directional light, intensity low, no shadow. **One** point light max (the car's underglow) — and note point lights are per-fragment for every lit pixel in range.
- No `ImageBasedLightComponent` unless you want PBR reflections; `.skybox(env)` already provides IBL cheaply from the environment resource.
- Keep `farClipDistance` tight. `2,000` with a 900 m sky is fine, but if you drop the sky sphere you can go to ~600 and improve depth precision.

---

## 5. Camera and game loop

### 5.1 `look(at:from:relativeTo:)` — correct but limited

`PerspectiveCamera.look(at:from:relativeTo:)` (iOS 13+) builds an orientation from a world-up basis. It **cannot express roll**, and it snaps (no smoothing). For a chase cam you want both bank and damping, so drive `position`/`orientation` directly:

```swift
// Verified compiles (iOS 18+).
@MainActor
final class ChaseCamera {
    let camera = PerspectiveCamera()
    private var position = SIMD3<Float>(-9, 3.2, 0)
    private var orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

    func update(target: SIMD3<Float>, forward: SIMD3<Float>, dt: Float) {
        let desired = target - forward * 9 + SIMD3<Float>(0, 3.2, 0)
        let desiredOrientation = simd_quatf(from: [0, 0, -1], to: forward)

        position += (desired - position) * (1 - exp(-8 * dt))          // frame-rate independent
        orientation = simd_slerp(orientation, desiredOrientation, 1 - exp(-10 * dt))

        camera.position = position
        camera.orientation = orientation
    }
}
```

Why `1 - exp(-k·dt)`: the naive `lerp(a, b, 0.1)` is frame-rate dependent — at 120 Hz the camera is twice as stiff as at 60 Hz. This is the single most common "feels different on ProMotion" bug.

Keep the *simulation* (`yaw`/`pitch`/`roll`/`velocity`) at a **fixed** timestep and let the camera interpolate. Fixed step + variable render is what makes 60 and 120 Hz behave identically:

```swift
// Verified compiles (iOS 18+).
@MainActor
final class Loop {
    private var accumulator: Float = 0
    private let step: Float = 1.0 / 120.0
    private var subscription: EventSubscription?

    func attach(to content: RealityViewCameraContent, simulate: @escaping (Float) -> Void) {
        subscription = content.subscribe(to: SceneEvents.Update.self) { event in
            self.accumulator += min(Float(event.deltaTime), 0.25)   // clamp hitches
            var steps = 0
            while self.accumulator >= self.step && steps < 8 {      // spiral-of-death guard
                simulate(self.step)
                self.accumulator -= self.step
                steps += 1
            }
        }
    }
}
```

`SceneEvents.Update` gives `deltaTime` in seconds; `SceneUpdateContext.deltaTime` is the same value for `System`s. If you later add physics, `PhysicsSimulationComponent` exposes `clock` / `targetClock` (`CMClockOrTimebase`) so the sim can be driven by an explicit clock instead of wall time.

### 5.2 Per-frame hygiene in `GameWorld.update`

Current code does `roadster.children.first(where: { $0.name == "Plume" })` **every frame** — a linear name scan with string comparison. Cache the reference in `init`. Same for any other named lookup. At 120 Hz that's 120 string comparisons/second for something that never changes.

Ring loop: `length(ring.position - session.position) < 7` is fine (24 iterations), but it allocates a `[Entity]` removal each hit — acceptable. Do it in the fixed-step sim, not per render frame.

---

## 6. Audio and haptics

### 6.1 Engine sound: `AVAudioEngine` + `AVAudioSourceNode` (recommended)

- `AVAudioSourceNode` (iOS 13+, verified) is the documented way to synthesise procedurally. One render block, 512-frame buffers @ 48 kHz ≈ 10.7 ms latency — fine for engine tone.
- Model the engine as **1–2 oscillators + filtered noise** whose frequency/gain you set from the sim at ~30–60 Hz (not per render frame). Don't allocate in the render block; pre-allocate all buffers.
- Route: `source → mixer → mainMixerNode`. For spatialisation use `AVAudioEnvironmentNode` (HRTF) **only** if the engine is world-positioned; for a cockpit sound, plain stereo is cheaper and more controllable.
- RealityKit alternative: `SpatialAudioComponent` (iOS 18+, verified) on an entity + `AudioPlaybackController`. Convenient for one-shots attached to world objects (ring pickup), but it plays files, not procedural streams.
- **PHASE** (iOS 15+): `PHASEEngine`, `PHASEPushStreamNode` *can* feed procedural buffers, and it gives geometric acoustics/occlusion/reverb meshes. But WWDC26 279 is explicit that the custom reverb mesh experience is Vision Pro-centric (*"This can only truly be experienced on an Apple Vision Pro"*), and PHASE's acoustic simulation is real CPU. For a single flying car it's over-engineering — use it only if you want city-canyon reflections as a feature.

### 6.2 Haptics: `CoreHaptics`, tuned for battery

Verified API surface: `CHHapticEngine.capabilitiesForHardware().supportsHaptics`, `playsHapticsOnly`, `isAutoShutdownEnabled`, `stoppedHandler`, `resetHandler`, `makeAdvancedPlayer(with:)`.

Patterns that matter here:
- **Boost** = one `CHHapticAdvancedPatternPlayer` with a *continuous* event whose intensity/ sharpness you modulate with `sendParameters(_:atTime:)`. Do **not** build a new `CHHapticPattern` per frame.
- **Ring pickup** = cached transient pattern, `h.engine.makePlayer(with: pattern)` reused.
- Set `playsHapticsOnly = true` — avoids engaging the audio route for haptics-only playback (battery + fewer session interruptions).
- `isAutoShutdownEnabled = true` and restart on demand; always install `stoppedHandler` (audio-session interruption) and `resetHandler` (server reset → all players invalid).
- Prefer `UIImpactFeedbackGenerator` for UI taps (menu) — much cheaper than spinning up a `CHHapticEngine`.
- On devices without haptics (`supportsHaptics == false`), skip engine creation entirely.

### 6.3 Audio session

Use `.ambient` with `.mixWithOthers` if the game should not stop the user's music; `.playback` if you want to own the session. Category changes are a known cause of haptic-engine stoppages — set the category **once**, before starting the haptic engine, and handle `stoppedHandler` by restarting both.

---

## 7. Real-world examples worth reading

| Source | What to steal |
|---|---|
| **[Creating a Spaceship game](https://developer.apple.com/documentation/realitykit/creating-a-spaceship-game)** (Apple sample) | Closest Apple sample to a fly-around arcade game: entity composition, input, game-state structure |
| [Bringing your SceneKit projects to RealityKit](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit) | Mapping `SCNNode` habits → ECS; what not to port |
| [Creating a game with scene understanding](https://developer.apple.com/documentation/realitykit/creating-a-game-with-scene-understanding) | Game loop + `SceneEvents` patterns |
| [Swift Splash](https://developer.apple.com/documentation/visionos/swift-splash) / [BOT-anist](https://developer.apple.com/documentation/visionos/bot-anist) / [Happy Beam](https://developer.apple.com/documentation/visionos/happybeam) | Entity-component decomposition, `System`s, procedural content |
| [metal-by-example/metal-spatial-dynamic-mesh](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) (107★) | The canonical `LowLevelMesh` demo — vertex layout, double-buffered updates |
| [talkol/flappy-experience](https://github.com/talkol/flappy-experience) | Complete small RealityKit game: state machine, scoring, audio |
| WWDC26 **279** *Explore advances in RealityKit* | LOD, soft shadows, lightmaps, thermal-state mitigation, cloth, NavMesh |
| WWDC26 **388** *Find and fix performance issues in your Metal games* | The 2026 benchmarking workflow (§8) |
| WWDC25 **287** *What's new in RealityKit* | `MeshInstancesComponent` (12:26), `customPostProcessing` |
| WWDC24 **10103** *Discover RealityKit APIs for iOS, macOS, and visionOS* | `LowLevelMesh`/`LowLevelTexture` origins |
| WWDC24 **10150** *Better together: SwiftUI and RealityKit* | The correct `RealityView` make/update contract |

Patterns that recur across all of them: (1) one entity per *concept*, not per *visual primitive*; (2) geometry merged or instanced; (3) all per-frame work in `SceneEvents.Update`/`System`, never in SwiftUI state; (4) LOD or chunking before adding detail; (5) a thermal mitigation path.

---

## 8. Benchmarking on Xcode 27 / iOS 27

### 8.1 Tools, in order of usefulness

1. **Metal Performance HUD** — Settings → Developer → *Graphics HUD* on device, or the scheme's *Show Graphics Overview* runtime diagnostic, or env vars (`MTL_HUD_ENABLED`, `MTL_HUD_LOG_ENABLED`; insights via `MTL_HUD_INSIGHTS_ENABLED=1`). Shows device, **resolution**, **present mode (direct/composited)**, process + Metal memory, **Game Mode on/off**, avg **FPS**, **GPU time**, **frame interval** + 120-frame chart. Per-frame logging to console → CSV. ([docs](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance), [metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics))
2. **Instruments → Game Performance Overview** (new in Xcode 27, WWDC26 388): aggregated Metal metrics + Time Profiler in one long recording. Start here for a 5–10 minute play session.
3. **Metal System Trace**: per-frame CPU/GPU scheduling, encoder timeline, shader cost. Use once you know *which* frames are bad.
4. **Performance Trace look-back (iOS 27)**: Developer settings → *Enable Performance Trace* → *Lookback Collection*; add the Performance Trace button to Control Center. The system has *already been recording* Metal metrics, so you can capture the last N minutes/hours **after** a thermal-throttled session. This is the single best tool for your "low thermal" requirement.
5. **`metalperftrace` CLI (macOS 27)**: `metalperftrace collect /tmp --last 5h`, `metalperftrace overview Trace.atrc`, `--json` for CI regression gates. Sample output shape:
   ```
   59.7 FPS  17735 Frames  188 Skipped
   Frame Time  avg 16.74ms  max 125.00  stddev 3.70
   CPU Begin-to-Present avg 3.99ms
   On-GPU Time avg 13.39ms  max 37.57
   Next Drawable Wait avg 0.26ms  max 91.08
   Shader Compilation Time 0.000s (Cached: 18)
   ```
6. **`StateReporting`** (iOS 27, `SRStateReporter`): tag traces with domains/states (`level`, `graphics`, `thermal`) so a 20-minute trace is interpretable. Limit transitions to user-action cadence — the system throttles if you spam it.
7. **MetricKit** (iOS 27): daily in-process reports now include **Metal frame rate**, aggregated *per StateReporting state*. This is your post-ship early-warning system.
8. **Xcode Metal debugger / GPU trace**: only for shader-level work; overkill for draw-call reduction.

**Simulator:** usable for correctness and layout (including iPhone Duo aspect changes) but **not** for frame time or thermal. All numbers below must come from a device.

### 8.2 Metrics that matter, and thresholds to target

| Metric | Where | 120 Hz target | 60 Hz target | Why |
|---|---|---|---|---|
| On-GPU time | HUD / trace | **≤ 6 ms** | ≤ 12 ms | leaves headroom for compositor |
| CPU begin-to-present | trace | **≤ 3 ms** | ≤ 8 ms | encode + ECS |
| Frame interval **stddev** | trace | **< 1 ms** | < 2 ms | smoothness > average FPS |
| Skipped frames | trace | **0** over 5 min | 0 | |
| Next-drawable wait | trace | ≈ 0 | ≈ 0 | non-zero ⇒ GPU-bound |
| Present mode | HUD | `direct` | `direct` | `composited` caps/limits |
| Metal memory | HUD | < ~600 MB | | no textures here, so mesh + targets |
| Process memory | HUD | < ~1 GB | | `os_proc_available_memory()` |
| Thermal state | `ProcessInfo.thermalStateDidChangeNotification` | stays `.nominal/.fair` over 15 min | | |

**Draw-call target:** Apple publishes no number. For this scene the right target is **≤ 10 draws for the city, ≤ 60 for the whole frame**. You can hit it.

### 8.3 Thermal mitigation (this is a design requirement, not an optimisation)

WWDC26 279 recommends observing `ProcessInfo.thermalStateDidChangeNotification` and, on `.serious`/`.critical`, making LOD thresholds more aggressive and lowering shadow quality. For Neon Roadster add: drop `antialiasing` to `.none`, disable bloom, cut the city's far-draw distance, and (last resort) halve the render resolution.

Also:
- `com.apple.developer.sustained-execution` entitlement (iOS 17+): *"Instruct the system to limit burst performance… maintain a consistent performance state over your app's lifecycle"* — **use this for benchmarking**, otherwise your first 60 seconds lie about steady-state.
- `com.apple.developer.kernel.increased-memory-limit` (iOS 15+) if you ever exceed the default cap; pair with `os_proc_available_memory()`.
- Check `ProcessInfo.processInfo.isLowPowerModeEnabled` and degrade (Apple lists exactly this in *Improving your game's graphics performance and settings*).

### 8.4 iPhone Duo

No public RealityKit API is Duo-specific. Treat it as: (a) a **resize/aspect change** — `RealityView` resizes, but your `fieldOfViewInDegrees = 68` is vertical FOV, so a much taller/wider canvas changes what's visible; test both folded and unfolded and consider deriving FOV from aspect; (b) a **thermal/refresh** unknown — measure, don't assume 120 Hz; (c) a place where `TimelineView`-driven SwiftUI overlays can hitch during the fold transition — keep the HUD static and driven by the 10 Hz snapshot.

---

## 9. Prioritised checklist

### P0 — do first (expected: 660 → ~10 draws, 3.57 M → ~8 k tris)

1. **Remove `cornerRadius` from every `generateBox`** in `CityGenerator.swift` (lines 84, 149, 154) and `RoadsterEntity.swift` (17, 24, 31, 73). If you want bevels, model one beveled box once and instance it.
2. **Merge the city by material** with `BoxBatch` (§2.2): one mesh each for `bodyDark`, `street`, `ground`, and 5 neon buckets → 7 `ModelEntity`s under `City`.
3. **Merge each ring's torus+hole into one mesh** (or one `MeshInstancesComponent` for all 24) → 48 draws → 1–24.
4. **Replace the sky sphere** with `EnvironmentResource(equirectangular:)` + `.skybox` (or a 12-tri camera-attached box).
5. **Cache the `Plume` (and any other named) child reference** in `GameWorld.init` instead of `first(where:)` per frame.
6. **Collapse the HUD snapshot** into one `struct` property written once per 100 ms → one SwiftUI invalidation instead of seven.
7. **Baseline measurement**: Metal HUD on device, 5-minute run, record FPS / GPU time / frame interval / memory / present mode. Keep the CSV.

### P1 — next (frame pacing and feel)

8. **Fixed-timestep sim** at 120 Hz with accumulator + clamp (§5.1); keep the camera interpolating at render rate.
9. **Frame-rate-independent camera damping** (`1 - exp(-k·dt)`) and add bank/roll via `simd_slerp` instead of `look(at:)`.
10. **Turn off MSAA at 120 Hz** (`.none`), keep 4× at 60 Hz; keep motion blur/DoF off.
11. **Budget check**: on-GPU ≤ 6 ms, CPU ≤ 3 ms, stddev < 1 ms. If CPU is still high, the draw count is the reason — recheck §2.
12. **Thermal path**: observe `thermalStateDidChange`, degrade in this order — bloom off → MSAA off → far distance 400→250 m → resolution scale.
13. **Remove the shadow-casting intent** from the moon light (there is none today — keep it that way); add `GroundingShadowComponent` to the car only.

### P2 — polish, gated on iOS 26/27

14. **`BloomComponent(scope: .hierarchical)`** on the neon root + `BloomOptionsComponent` + `ToneMappingComponent` (iOS 27). On iOS 26: `customPostProcessing` with one MPS Gaussian. On iOS 18: additive billboards.
15. **`LevelOfDetailComponent.addByCameraDistance`** (iOS 27) with 2 LODs once buildings gain detail; manual `isEnabled` distance culling before that.
16. **`MeshInstancesComponent`** for repeated props (street lights, antennas, rings) — one draw each, per-instance transforms.
17. **`UnlitMaterial(color:applyPostProcessToneMap: false)`** for neon so tone mapping doesn't desaturate it.
18. **Procedural audio** via `AVAudioSourceNode`; **haptics** via one cached continuous player for boost + cached transients for rings; `playsHapticsOnly = true`.
19. **`StateReporting` domains** (`level`, `graphics`, `thermal`) so long traces are readable, and MetricKit frame-rate reports per state post-ship.
20. **CI gate**: `metalperftrace --json` on a scripted 60-second run; fail if on-GPU or skipped-frame count regresses.

---

## 10. Availability matrix (compiler-verified against iOS 27 SDK)

| API | iOS 18 | iOS 26 | iOS 27 |
|---|:--:|:--:|:--:|
| `MeshDescriptor`, `MeshResource.generate(from:)` | ✅ | ✅ | ✅ |
| `MeshResource.Instance` / `MeshInstanceCollection` | ✅ | ✅ | ✅ |
| `SceneEvents.Update`, `content.subscribe`, `deltaTime` | ✅ | ✅ | ✅ |
| `PerspectiveCamera.look(at:from:relativeTo:)` | ✅ | ✅ | ✅ |
| `Entity.isEnabled`, `clone(recursive:)` | ✅ | ✅ | ✅ |
| `UnlitMaterial(color:applyPostProcessToneMap:)` | ✅ | ✅ | ✅ |
| `renderingEffects` (antialiasing/motionBlur/DoF/dynamicRange) | ✅ | ✅ | ✅ |
| `EnvironmentResource(equirectangular:withName:)`, `.skybox` | ✅ | ✅ | ✅ |
| `SpotLightComponent.Shadow` as component | ✅ | ✅ | ✅ |
| `DirectionalLightComponent.Shadow` (`shadowProjection`) | ✅ | ✅ | ✅ |
| `GroundingShadowComponent` | ✅ | ✅ | ✅ |
| `SpatialAudioComponent` | ✅ | ✅ | ✅ |
| `renderingEffects.customPostProcessing` | ❌ | ✅ | ✅ |
| **`MeshInstancesComponent` / `LowLevelInstanceData`** | ❌ | ✅ | ✅ |
| **`LevelOfDetailComponent`** | ❌ | ❌ | ✅ |
| **`BloomComponent` / `BloomOptionsComponent` / `ToneMappingComponent`** | ❌ | ❌ | ✅ |
| **Shadow `quality` / `lightSize` (soft shadows)** | ❌ | ❌ | ✅ |
| `LowLevelRenderer` (manual draw/cull/sort) | ❌ | ❌ | ✅ |

Everything in the table was verified by `swiftc -typecheck -target arm64-apple-ios{18,26,27}.0` against the iPhoneOS 27.0 SDK, not inferred from docs.

---

## 11. Caveats / things I could not verify

- **120 Hz on `RealityView` is not API-controllable.** I verified the absence of any frame-rate property in RealityKit/RealityFoundation. Whether the layer actually runs at 120 must be confirmed with the Metal HUD *frame interval* + *present mode* on a ProMotion device.
- **`LowLevelInstanceData` live-update semantics** (does mutating the class after `components.set` re-upload, or must you re-set the component / call `replaceMutableTransforms`?) — not documented. Test with 24 animated rings before relying on it.
- **Draw-call encode cost (~15–25 µs/draw)** is a rule of thumb for Apple GPUs, not an Apple-published figure. Your 660-draw baseline measurement will give the real number.
- **iPhone Duo specifics** — no public RealityKit/Metal documentation found; treat as aspect/thermal variation.
- The repo was being edited while I read it (`GameSession.swift` grew from 97 to 150+ lines mid-session). Line references may drift; the findings about `CityGenerator` geometry and `GameView` structure are stable.

---

## 12. Primary sources

- [Improving the Performance of a RealityKit App](https://developer.apple.com/documentation/realitykit/improving-the-performance-of-a-realitykit-app)
- [Reducing CPU Utilization in Your RealityKit App](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app) — draw calls, merging, flattening, physics, audio
- [Reducing GPU Utilization in Your RealityKit App](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app) — textures, polygons, effects, transparency, lights
- [MeshInstancesComponent](https://developer.apple.com/documentation/realitykit/meshinstancescomponent) · [LevelOfDetailComponent](https://developer.apple.com/documentation/realitykit/levelofdetailcomponent) · [BloomComponent](https://developer.apple.com/documentation/realitykit/bloomcomponent) · [RealityViewRenderingEffects](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects)
- [RealityView](https://developer.apple.com/documentation/realitykit/realityview) · [System](https://developer.apple.com/documentation/realitykit/system) · [SceneEvents.Update](https://developer.apple.com/documentation/realitykit/sceneevents/update)
- WWDC26 279 *Explore advances in RealityKit* — https://developer.apple.com/videos/play/wwdc2026/279/
- WWDC26 388 *Find and fix performance issues in your Metal games* — https://developer.apple.com/videos/play/wwdc2026/388/
- WWDC25 287 *What's new in RealityKit* — https://developer.apple.com/videos/play/wwdc2025/287/
- [Improving your game's graphics performance and settings](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings)
- [Monitoring your Metal app's graphics performance](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) · [Understanding the Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
- [`com.apple.developer.sustained-execution`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.sustained-execution)
