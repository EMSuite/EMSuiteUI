# The crystal view (`ShellCrystal`)

The phase in 3D beside its pattern: atoms, bonds, the unit cell and an a, b, c triad, seen down the beam with a parallel
projection, so the atom columns line up the way the pattern is indexed. Shared by the Simulation window, the Diffraction
room after Index and the Add Phase preview (plan 5.1, design 5.4). EMSuiteUI issue #193.

## What goes in and out

- `CrystalScene`: atoms in Å (Cartesian, crystal frame), bonds as pairs of those atoms, the cell. The target imports no
  kit. The app maps its structure into `CrystalSite`s and DiffractoKit's bonds (row K8: site, site, image) into
  `CrystalBondInput`s, and `CrystalScene.unitCell(cell:sites:bonds:repeats:)` lays out one cell the way VESTA draws it:
  a site on a face, edge or corner appears on each one it touches (diamond Si 18 atoms and 16 bonds, fcc Al 14), and a bond
  is drawn where both of its ends are drawn. The view computes no number a user reads.
- The orientation is a `simd_double3x3` in py4DSTEM's convention, the value DiffractoKit's `CrystalOrientation` holds:
  its columns are the view x, y and z axes written in the crystal frame, z from the sample towards the source, so the beam
  runs into the screen. A crystal vector v appears on screen at Mᵀv. The camera never moves; the crystal turns.
- Out comes `CrystalOrientationChange`: `isFinal == false` while a drag runs (view state, may drive the pattern each
  frame), `true` when the drag ends or for a key press or an action. Then the app writes it to its document, with undo.
  Snapping to a zone axis and naming the nearest one are the app's.

## Interaction

| Input | Turn |
|---|---|
| Drag | Tilts about the screen axes (right turns the near side right; 400 pt = 180°) |
| ⌥ drag | Rotates in the plane about the beam |
| ← → ↑ ↓ | Tilt by 1° |
| ⌥ ← ⌥ → | Rotate in the plane by 1° |
| VoiceOver | One element: the app's label (phase, zone axis, tilt), the view's value (atoms per element, bonds, cell); actions Tilt Left, Right, Up, Down, Rotate Clockwise, Counterclockwise, Return to Zone Axis |
| Context menu | Copy Image, Return to Zone Axis |

Hovering an atom shows a chip with its symbol and name; the legend in the top right names every element drawn. Both are
picked by the view's own projection (`CrystalProjection`), not RealityKit hit testing. Under Differentiate Without Color the
visible atoms carry their element symbol. An orientation set from outside (a typed zone axis, Return to Zone Axis, Index)
turns over 0.35 s, or crossfades under Reduce Motion; drags and key steps are set at once.

`CrystalInteraction.still` draws the same picture with no gestures and no focus (the Add Phase thumbnail).
`CrystalSnapshot.image` renders a picture with no window (Copy Image, tests).

## Look

Our own element colours (`CrystalPalette.swift`, one file, Paul 23 Nov 2026): familiar hues, each at 3:1 or better
against the stage, which stays dark in light and dark appearance. Ball radius 0.35 Å + 0.25 × the covalent radius (Cordero
2008); bonds as two halves in the colours of their atoms; the cell in thin unlit lines (heavier under Increase Contrast);
a key light from the upper left with a shadow and a fill from the lower right, both fixed to the camera.

## RealityKit facts (measured in the spike, #192)

- 621 atoms, 1024 bonds and the cell hold 120 Hz on the reference Mac (worst frame 9.3 ms).
- One `MeshInstancesComponent` silently draws nothing past about 2 to 4 million triangles: instances go out in batches of
  at most 1 million (`CrystalMesh.batches`).
- `generateSphere` has 8 064 triangles; atoms use an icosphere of 1 280.
- `simd_quatf()` is the zero quaternion, not the identity.
- `OrthographicCameraComponent.scale` is the half-height of the view volume.
- `RealityRenderer` has no default light; the view carries its own lights, so window and snapshot match.

Later: space filling,
polyhedra and perspective (MU4, 2.4); the slab and its box (2.5).
