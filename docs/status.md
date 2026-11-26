# Status: EMSuiteUI 0.19.0 <!-- x-release-please-version -->

What is live. Both apps take EMSuiteUI by version range and build on it. Since 0.18.1 the manifest names the kits
at `github.com/EMSuite/...` (the old org address only redirected).

- The window shell (`ShellLayout`): rooms, toolbar, sidebar and inspector frames, the centre column, the centre's one or two
  panels (`WorkspaceCentre`: a remembered divider that a double click resets; `CentrePanel`: title, controls, readout), `LayoutPolicy`,
  `MenuActionRelay`, `ActivityLog` (each recorded event is also said to VoiceOver), `UITestingPlacement`; `InspectorSection` can start closed and draws a status glyph.
  The centre column's bottom area (`WorkspaceColumn`) shows its panes side by side with a toggle each (`ProcessAreaStyle.panes`, the
  default, 4DSTEM Studio) or as tabs, one at full width under a segmented header with one toggle for the area (`.tabs`, Electron
  Microscopy Studio; the selection is `PanelNavigation.selectedProcessPane`, `selectProcessPane` opens a shut area).
- The controls (`ShellControls`, `ShellInspector`): zoom and pan (the wheel zooms or pans by Settings, `ScrollWheelMode`; View > Pan Left, Right, Up, Down with ⌃⌘ and an arrow), `NumericField` (typing the shown text over a finer stored
  value sets it), `PaneFooter`, `ScaleBar`, colorbar, `HistogramChart`, `SegmentedControl` and `SegmentedPicker` (a segment can be
  disabled, with its reason), the inspector row kit.
- The Metal image view (`ShellMetal`): `MetalEngine`, `MetalImageView` (raw pixels at their own bit depth, a linear or log
  display transfer drawn in the shader; `sampling: .linear` draws a coarse simulated scan smooth, its values blended
  bilinearly in the shader, while recorded data stay `.nearest`, the default; RGBA and figure exports stay nearest), `MetalDisplayTransform`, the shared colormaps and their shader (compiled from source
  when the bundle has no metallib); `ImageViewport`, one zoomable container for every room picture.
- The spectroscopy room (`ShellSpectroscopy`): map tiles (with an overlay slot) and the fitted map grid, the colour mix, regions
  (draw, edit, list, a keyboard route; Esc returns to the arrow tool), spectrum and profile panes, the periodic table, the map display popover.
- The shared EDS room (`ShellEDXModel` and `EDXRoom` in `ShellSpectroscopy`, 0.4.0): the model and session (`EDXSession`, regions,
  pins, maps, exports) that both apps showed as copies; each app passes `EDXRoomHost`, `EDXRoomActions` and its Open panel
  extensions. Results name the kept region, carry the whole value and its sigma, and say no "unvalidated"; the typed-k and
  factors sheets read either decimal separator and keep their accessibility identifiers.
- The crystal view (`ShellCrystal`, `docs/crystal-view.md`): a phase's unit cell in 3D with RealityKit, seen down the beam in
  parallel projection, turned by drag, ⌥ drag, the arrow keys and VoiceOver actions; plain atoms, a cell and an orientation
  in, orientation changes out; its own element colours in one file; a still mode and an offscreen snapshot.
- Figures (`ShellExport`, since 0.14.0): a figure as one value, `FigureScene` (a picture at its own pixels, paths,
  markers in six shapes, one-line labels, a ruled table, a legend; 90, 140 or 190 mm wide, 7 pt Helvetica), drawn by
  `FigureRenderer` as PDF and SVG with live text and as PNG, each carrying its title, software line and methods record. Two shared
  layouts (`FigurePlot`): a spectrum as one path in a framed plot with round ticks, titles and labelled lines, and a map as its
  picture with a vector scale bar and a key (colour boxes or a ramp), and maps side by side as panels (`FigurePlot.panels`),
  which the EDS room writes as Maps PDF… and Maps SVG… beside Spectrum PDF… and Spectrum SVG…. Core
  Graphics and Core Text only, off the main actor. The methods record (`MethodsRecord`, schema `emsuite.methods/1`,
  `docs/schema/emsuite.methods-1.schema.json`): app, kit and reference versions, sources by file name, size and SHA-256 with
  their calibrations as FormatoCore's `FormatoMetadataEntry` and `FormatoProvenance`, phases with source and licence, steps
  with every setting, results, what was drawn, what to cite; canonical JSON (sorted keys, shortest round-trip numbers) that
  refuses a path, and `MethodsParagraph`, the paragraph for a paper. Pins M1 and M2: golden records and paragraphs.
- The agent door (`ShellAgentDoor`, since 0.6.0): a local API, off until the person turns it on in Settings, through which
  an agent on this Mac looks at the app's open windows; each app registers its own tools. The app is the MCP server itself,
  over HTTP at `/mcp`; Claude desktop connects through the extension in `DesktopExtension/` (`docs/agent-door.md`). Since
  0.7.0: typed inputs and tools that act (`AgentParameter`, `AgentTool(acts:)`), behind a second switch, "Let agents run
  analyses" (`runsAllowed`). The EDS room's tools are written once for both apps (`ShellEDXAgent`): `get_eds`, `set_eds`,
  `run_eds`, and `EDXDisplayAgentTools` for how the maps are drawn: `get_eds_display` (each map's colour, window, gamma,
  histogram and percentiles, the colour mix), `set_eds_display` (named colours, a colour-blind-safe set, colormap, window,
  percentile clip, gamma, Reset Range, the mix, the figure's switches) and `get_eds_figure` (the maps as Maps as PNG… draws them,
  all or a chosen few side by side).
- Snapshot tests (`ShellSnapshotTesting`, test support for this package and the apps): a view drawn in light and dark and
  compared with its committed PNG on CI's macos-26 leg; new and changed pictures are attached to the pull request.
- The Help menu (`ShellHelp`, since 0.14.0; the crash and hang reports since 0.15.0): `HelpCommands` puts the support page, the documentation and Report a Problem… in place of the
  missing help book; `FeedbackWindow` shows the person's report with a diagnostics summary (version, channel, macOS, Mac model,
  memory) and opens it as an email or a GitHub issue draft in their own apps; `DiagnosticReportCollector` keeps the system's
  crash and hang reports in the app's own folder, which the window shows. The app sends nothing.
- Quick Look (`ShellQuickLook`, unreleased): 4DSTEM Studio's thumbnail pixels and preview card moved here for both apps'
  extensions, the card now with a scale bar from the file's pixel size (the detector step for a pattern) times the frame's
  decimation, through ImagoKit's `ScaleBarMath`. 4DSTEM Studio still builds its own copy until it switches.
- The phase library (`ShellPhaseLibrary`, since 0.15.0): a `Phase` (name, notes, source, the structure as DiffractoKit's
  snapshot and the fingerprint it came with, so an edit shows), kept one folder per phase in Application Support with the
  downloaded file beside it; `MaterialsProjectClient` searches and downloads politely (one search at a time, a pause while
  typing, a day's cache in memory, short timeouts, offline fails at once) with or without the person's own key, which
  `APIKeyStore` keeps in the login keychain.
  The Add Phase sheet (`ShellPhaseViews`, first slice): search as you type (element symbols or a formula, always on
  the open service), the exact match first (the elements alone, such as Si for "Si"), then fewer elements, then the most stable, each match's formula written as the preview names it (GaAs, not the
  service's AsGa), a preview of the chosen entry with a still picture of its unit cell
  (the crystal view's still mode, with the kit's bonds and a spoken description), a note that its cell is the Materials
  Project's computed one, its id and CC BY 4.0, Add, and
  Open CIF… (the sheet closes before the app's file dialog); each empty, offline or failed state says what to do next.
  The Materials Project settings pane (`MaterialsProjectSettingsPane`): an optional key pasted, tested with one request
  and removed, one sentence on what is sent, and the citation the Materials Project asks for.

Since 0.3.2: 0.4.0 (2026-10-29) brought the shared EDS room; 0.5.0 (2026-11-01) `ImageViewport`, the keyboard and zoom routes,
the narrowed EDS room API and the deletion of the superseded map tile API; 0.5.1 (2026-11-05) the EDS sheet and header fixes.
Details and the migration notes: `CHANGELOG.md`.

Builds with Xcode 26.6 (macOS 26, what the apps' CI builds it with) and Xcode 27.1; CI runs `swift test -c release --parallel`
on both on every push (the Metal tests skip on a runner without a Metal device). What is open: the GitHub issues.
