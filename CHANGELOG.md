# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). MacEMUI follows semantic versioning; before 1.0.0 a minor version may break the API, and its Migration paragraph says how.

## [0.19.0](https://github.com/EMSuite/EMSuiteUI/compare/0.18.1...0.19.0) (2026-11-26)


### Features

* the bottom area can show its panes as tabs, one at full width with one toggle ([#266](https://github.com/EMSuite/EMSuiteUI/issues/266)) ([0b0ad86](https://github.com/EMSuite/EMSuiteUI/commit/0b0ad86e496f6f45cd3c998d4d10ce6a5628bc0a))
* the image view can draw an image smooth, for coarse simulated scans ([#269](https://github.com/EMSuite/EMSuiteUI/issues/269)) ([e6a249f](https://github.com/EMSuite/EMSuiteUI/commit/e6a249ff8cae48ad1c3f519d2e3be95f547d6d38))


### Bug Fixes

* Add Phase lists formulas as the preview names them, and says the cell is a computed one ([#268](https://github.com/EMSuite/EMSuiteUI/issues/268)) ([536d320](https://github.com/EMSuite/EMSuiteUI/commit/536d3203ed39738fac7807d9018b32e65ebd8625))

## [0.18.1](https://github.com/EMSuite/EMSuiteUI/compare/0.18.0...0.18.1) (2026-11-26)


### Bug Fixes

* the package manifest names the kits at the EMSuite org ([#264](https://github.com/EMSuite/EMSuiteUI/issues/264)) ([91250ed](https://github.com/EMSuite/EMSuiteUI/commit/91250edf50b830976a46e050a411419a027b7d89))

## [0.18.0](https://github.com/EMSuite/EMSuiteUI/compare/0.17.0...0.18.0) (2026-11-25)


### Features

* a unit-cell picture in the Add Phase preview ([#245](https://github.com/EMSuite/EMSuiteUI/issues/245)) ([274c373](https://github.com/EMSuite/EMSuiteUI/commit/274c373dd9705191f5803cc3cb549ebd6d18abd2))
* agent door tools read and set how the EDS maps are drawn and show the maps figure ([#248](https://github.com/EMSuite/EMSuiteUI/issues/248)) ([3452406](https://github.com/EMSuite/EMSuiteUI/commit/3452406179af90af40e70d10eec693dc72b4129d))
* one shared centre with two panels for every room ([#262](https://github.com/EMSuite/EMSuiteUI/issues/262)) ([2b70c82](https://github.com/EMSuite/EMSuiteUI/commit/2b70c8200833faa4b82a9b78ed1855f41acea8cd))


### Bug Fixes

* a library phase still named by its Materials Project id takes its formula on load ([#259](https://github.com/EMSuite/EMSuiteUI/issues/259)) ([1e32fb0](https://github.com/EMSuite/EMSuiteUI/commit/1e32fb0fd460b0c71da92e708265ccafab9db619))
* a Materials Project search lists the exact match first, then fewer elements, then the most stable ([#252](https://github.com/EMSuite/EMSuiteUI/issues/252)) ([3186159](https://github.com/EMSuite/EMSuiteUI/commit/3186159cc4516679e69b60d0879f11f3f106b704))
* a refused set_eds call changes nothing ([#244](https://github.com/EMSuite/EMSuiteUI/issues/244)) ([f7a466f](https://github.com/EMSuite/EMSuiteUI/commit/f7a466fd9db425b4bfe59dc0c844dc2273c426e3))
* Add for an L-line near miss with no computed k adds it fit only ([#258](https://github.com/EMSuite/EMSuiteUI/issues/258)) ([13cd33d](https://github.com/EMSuite/EMSuiteUI/commit/13cd33da11bd9a5a2edd00e0e4fa9d07455b00e3))
* EDS Auto ID offers an L-line find such as Au under Also possible, not its weaker neighbour ([#255](https://github.com/EMSuite/EMSuiteUI/issues/255)) ([#256](https://github.com/EMSuite/EMSuiteUI/issues/256)) ([e54da4f](https://github.com/EMSuite/EMSuiteUI/commit/e54da4f22f0aea8cb346cc1eb3429d42acdb27d6))
* Materials Project phases are named by their reduced formula, with the space group only where two share it ([#250](https://github.com/EMSuite/EMSuiteUI/issues/250)) ([15d21c6](https://github.com/EMSuite/EMSuiteUI/commit/15d21c67df8893e646c0ed05e1416855d0af66b8))
* the EDS header says at% not computed, and why, instead of a Quantified check ([290f2c9](https://github.com/EMSuite/EMSuiteUI/commit/290f2c9b8e716f2502d7727ff347b622f439e1b9))
* the EDS open's status line names the file and leaves out a one-pixel grid ([290f2c9](https://github.com/EMSuite/EMSuiteUI/commit/290f2c9b8e716f2502d7727ff347b622f439e1b9))
* the toolbar's idle line drops its last facts whole where it does not fit, never cutting a word ([#260](https://github.com/EMSuite/EMSuiteUI/issues/260)) ([f73a061](https://github.com/EMSuite/EMSuiteUI/commit/f73a061ba880118e9019273a4456cb3c288a1e05))
* VoiceOver names the agent switches and the histogram's limit readouts ([290f2c9](https://github.com/EMSuite/EMSuiteUI/commit/290f2c9b8e716f2502d7727ff347b622f439e1b9))

## [0.17.0](https://github.com/EMSuite/EMSuiteUI/compare/0.16.0...0.17.0) (2026-11-24)


### Features

* ShellExport lays out a spectrum and a map as vector figures ([#238](https://github.com/EMSuite/EMSuiteUI/issues/238)) ([0d17c76](https://github.com/EMSuite/EMSuiteUI/commit/0d17c7667bb5731058d7f7ad8b394f5bdf4ddc89))
* the EDS room writes its spectrum and maps as PDF or SVG figures ([#241](https://github.com/EMSuite/EMSuiteUI/issues/241)) ([c643113](https://github.com/EMSuite/EMSuiteUI/commit/c6431131716cd268786326e15e8a0991f1f1cf3c))


### Bug Fixes

* crystal view keeps long slabs whole and draws a slab's outline ([#235](https://github.com/EMSuite/EMSuiteUI/issues/235)) ([2a8a15c](https://github.com/EMSuite/EMSuiteUI/commit/2a8a15c564c6171b068de28ceecfe638bc3cd581))
* set_eds keeps a named region in one call, feedback drafts keep a plus sign, and two diagnostic deliveries in a second keep every report ([#240](https://github.com/EMSuite/EMSuiteUI/issues/240)) ([b73360d](https://github.com/EMSuite/EMSuiteUI/commit/b73360d6a64137a17e81270c65d74898dbe72aac))

## [0.16.0](https://github.com/EMSuite/EMSuiteUI/compare/0.15.0...0.16.0) (2026-11-24)


### Features

* set_eds draws a polygon region, keeps a region and draws a line ([#228](https://github.com/EMSuite/EMSuiteUI/issues/228)) ([c0ee0ef](https://github.com/EMSuite/EMSuiteUI/commit/c0ee0ef4753b98b3d43722909ebed0d40ec07f64))
* ShellQuickLook, the Quick Look card with a scale bar ([#226](https://github.com/EMSuite/EMSuiteUI/issues/226)) ([8e66042](https://github.com/EMSuite/EMSuiteUI/commit/8e66042ce36cea5c706deafb042423e8d8d2c7b0)), closes [#225](https://github.com/EMSuite/EMSuiteUI/issues/225)
* the EDS room's exports pass through a finishing step the app can fill ([#224](https://github.com/EMSuite/EMSuiteUI/issues/224)) ([d1b77f6](https://github.com/EMSuite/EMSuiteUI/commit/d1b77f62643ff56d9a3ab4a0d2840a58faae7223))

## [0.15.0](https://github.com/EMSuite/EMSuiteUI/compare/0.14.0...0.15.0) (2026-11-24)


### Features

* Add Phase sheet (search, preview, Add, Open CIF) ([#221](https://github.com/EMSuite/EMSuiteUI/issues/221)) ([1f9f501](https://github.com/EMSuite/EMSuiteUI/commit/1f9f501238fd90c6c618f49d844cfdde58127722))
* crash and hang reports are kept on the Mac ([#217](https://github.com/EMSuite/EMSuiteUI/issues/217)) ([ce7e6c5](https://github.com/EMSuite/EMSuiteUI/commit/ce7e6c5c5e13788b66b7b617f24fd25b2f2f4462))
* Materials Project settings pane (key, Test, attribution) ([#222](https://github.com/EMSuite/EMSuiteUI/issues/222)) ([69f56f2](https://github.com/EMSuite/EMSuiteUI/commit/69f56f2cfe8b70928d8e5a325283a0089f6125be))
* phase library (record, store, key store, Materials Project client) ([#220](https://github.com/EMSuite/EMSuiteUI/issues/220)) ([575a65c](https://github.com/EMSuite/EMSuiteUI/commit/575a65c050c4b413c2837f8147178534efa2a29e))


### Fixtures and tests

* snapshot tests that also supply the PR pictures ([#205](https://github.com/EMSuite/EMSuiteUI/issues/205)) ([5018f08](https://github.com/EMSuite/EMSuiteUI/commit/5018f085287f09b7a33ce6f001792f51e338c516))

## [0.14.0](https://github.com/EMSuite/EMSuiteUI/compare/0.13.0...0.14.0) (2026-11-24)


### Features

* a figure cell can carry a colour bar under its picture ([#216](https://github.com/EMSuite/EMSuiteUI/issues/216)) ([8bf342e](https://github.com/EMSuite/EMSuiteUI/commit/8bf342e6b116e17f8f215b7966b01d1fd38d6dcd))
* crystal view (ball and stick, unit cell, axes, seen down the beam, drag to tilt) ([#206](https://github.com/EMSuite/EMSuiteUI/issues/206)) ([60e3ffb](https://github.com/EMSuite/EMSuiteUI/commit/60e3ffb957fe2d4ae3b81b4a181b93e3d4765f8b))
* crystal view hover, legend and keys ([#209](https://github.com/EMSuite/EMSuiteUI/issues/209)) ([af723fd](https://github.com/EMSuite/EMSuiteUI/commit/af723fd84c0c7f8f28c8f65658771ed419002004))
* help links, a diagnostics summary and a feedback composer ([#214](https://github.com/EMSuite/EMSuiteUI/issues/214)) ([86e2ede](https://github.com/EMSuite/EMSuiteUI/commit/86e2ede9987cff7e06f17cdb708aaebb609fc165))
* ShellExport draws a figure scene as PDF, SVG and PNG ([#210](https://github.com/EMSuite/EMSuiteUI/issues/210)) ([d49fbc4](https://github.com/EMSuite/EMSuiteUI/commit/d49fbc466a46679beb66da58da97757c890e9290))
* ShellExport holds the methods record and writes its paragraph ([#213](https://github.com/EMSuite/EMSuiteUI/issues/213)) ([c81d990](https://github.com/EMSuite/EMSuiteUI/commit/c81d9900b083df7aa7a1eda5c5d824a9bfccbbdd))
* the keyboard pans a zoomed picture and VoiceOver hears the status line's events ([#184](https://github.com/EMSuite/EMSuiteUI/issues/184)) ([a678811](https://github.com/EMSuite/EMSuiteUI/commit/a6788113e286dc833df6e3115012fcc80b09ab70))


### Bug Fixes

* a sidebar the window stepped aside comes back when the window widens again ([#204](https://github.com/EMSuite/EMSuiteUI/issues/204)) ([02c09c8](https://github.com/EMSuite/EMSuiteUI/commit/02c09c8f5c4c03b5d66b8d1667438bec6901c18d))
* map tiles, the periodic table, regions and the spectrum carry a second signal beside colour ([bdffb8d](https://github.com/EMSuite/EMSuiteUI/commit/bdffb8d5cea1139410d26b086a12eebbd29d0c81))
* status words and map tiles carry a second signal beside colour ([#207](https://github.com/EMSuite/EMSuiteUI/issues/207)) ([bdffb8d](https://github.com/EMSuite/EMSuiteUI/commit/bdffb8d5cea1139410d26b086a12eebbd29d0c81))

## [0.13.0](https://github.com/EMSuite/EMSuiteUI/compare/0.12.4...0.13.0) (2026-11-18)


### Features

* Auto ID offers its near misses as one-click Adds ([#143](https://github.com/EMSuite/EMSuiteUI/issues/143)) ([2cd4600](https://github.com/EMSuite/EMSuiteUI/commit/2cd46005474c446d39f9d5cfc334e656dd955cde))
* Auto ID offers its near misses as one-click Adds ([#181](https://github.com/EMSuite/EMSuiteUI/issues/181)) ([2cd4600](https://github.com/EMSuite/EMSuiteUI/commit/2cd46005474c446d39f9d5cfc334e656dd955cde))

## [0.12.4](https://github.com/EMSuite/EMSuiteUI/compare/0.12.3...0.12.4) (2026-11-18)


### Bug Fixes

* a map tile shows its keyboard focus, Space toggles it in the mix, and its scale bar is a button ([#176](https://github.com/EMSuite/EMSuiteUI/issues/176)) ([1ba7150](https://github.com/EMSuite/EMSuiteUI/commit/1ba715087214baba688fe7be1cd399d53888b28b))
* EDS Auto ID quantifies an element found by its L line on its Kα when the spectrum holds it well excited ([#169](https://github.com/EMSuite/EMSuiteUI/issues/169)) ([87bd976](https://github.com/EMSuite/EMSuiteUI/commit/87bd976725460f406a32e206e84afa80ff154b37))
* the EDS maps export draws each map as the room shows it, off the main actor, and lets the bytes go after saving ([#173](https://github.com/EMSuite/EMSuiteUI/issues/173)) ([56a0f76](https://github.com/EMSuite/EMSuiteUI/commit/56a0f7617165863ec40c0733f1ac97b12fe339b9))
* the EDS room drops stale pin sums, previews and map pictures, and lets its cache go on close ([#171](https://github.com/EMSuite/EMSuiteUI/issues/171)) ([94e265e](https://github.com/EMSuite/EMSuiteUI/commit/94e265e23e7979de88f707f453f1fec81aca2db6))
* the EDS spectrum zooms and pans from the keyboard and VoiceOver ([#177](https://github.com/EMSuite/EMSuiteUI/issues/177)) ([1944852](https://github.com/EMSuite/EMSuiteUI/commit/19448525c7a013c2bd7b21f624ec49c7a7635f04))
* the histogram's log switch sits in its footer, under the plot ([#175](https://github.com/EMSuite/EMSuiteUI/issues/175)) ([1355b90](https://github.com/EMSuite/EMSuiteUI/commit/1355b908744ef02a690006eef27af7c794650de1))
* the infobar's run bar follows its count instead of trailing it ([#179](https://github.com/EMSuite/EMSuiteUI/issues/179)) ([50d70a6](https://github.com/EMSuite/EMSuiteUI/commit/50d70a65ac8ebc95391f689a59ac44726a0deaa4))
* VoiceOver adjusts an adjustment row and reads a row's control by its label ([#174](https://github.com/EMSuite/EMSuiteUI/issues/174)) ([4553eb6](https://github.com/EMSuite/EMSuiteUI/commit/4553eb6f47b3f287b3f651247a2abcb6d1da9f7c))
* workspace rows in the sidebar are buttons to accessibility, and pressing one chooses the room ([#170](https://github.com/EMSuite/EMSuiteUI/issues/170)) ([7e21062](https://github.com/EMSuite/EMSuiteUI/commit/7e210627aa31cd2cd51b30396255ad6764a73f7b))


### Performance Improvements

* the EDS room sums the pointer's pixel spectrum off the main actor and makes line profiles only when they change ([#172](https://github.com/EMSuite/EMSuiteUI/issues/172)) ([1037f44](https://github.com/EMSuite/EMSuiteUI/commit/1037f44a727cd2a67d4039100bdf70633142478d))

## [0.12.3](https://github.com/macEMSuite/MacEMUI/compare/0.12.2...0.12.3) (2026-11-16)


### Bug Fixes

* the agent door registers an app whose name has a space as one word ([#165](https://github.com/macEMSuite/MacEMUI/issues/165)) ([75d4acf](https://github.com/macEMSuite/MacEMUI/commit/75d4acfde1306264bd3cb3f721edb001fa91ba9d))
* the agent door registers an app whose name has a space as one word ([#166](https://github.com/macEMSuite/MacEMUI/issues/166)) ([75d4acf](https://github.com/macEMSuite/MacEMUI/commit/75d4acfde1306264bd3cb3f721edb001fa91ba9d))

## [0.12.2](https://github.com/macEMSuite/MacEMUI/compare/0.12.1...0.12.2) (2026-11-16)


### Bug Fixes

* colour bar numbers stay on one line and the plate widens for a wide range ([#161](https://github.com/macEMSuite/MacEMUI/issues/161)) ([24363d2](https://github.com/macEMSuite/MacEMUI/commit/24363d234678c1610a3e2cf87e1d2901cd9b82a7))

## [0.12.1](https://github.com/macEMSuite/MacEMUI/compare/0.12.0...0.12.1) (2026-11-16)


### Bug Fixes

* a zoomed-out picture averages its pixels instead of aliasing, and resizes and contrast ticks redraw less ([#162](https://github.com/macEMSuite/MacEMUI/issues/162)) ([3b1345a](https://github.com/macEMSuite/MacEMUI/commit/3b1345a4859075398dcf2d985b4e07fa974f570a))

## [0.12.0](https://github.com/macEMSuite/MacEMUI/compare/0.11.0...0.12.0) (2026-11-16)


### Features

* Settings' Scroll wheel: Zoom · Pan for every zoomable picture ([#156](https://github.com/macEMSuite/MacEMUI/issues/156)) ([54804a4](https://github.com/macEMSuite/MacEMUI/commit/54804a4a36bf82e567a82b78610f063e07bf8357))


### Bug Fixes

* draw the hovered pixel's spectrum in a tone that reads in light mode ([#148](https://github.com/macEMSuite/MacEMUI/issues/148)) ([3102ed4](https://github.com/macEMSuite/MacEMUI/commit/3102ed48f182dbd2531fd810629c9e1b1f832b50))
* draw viridis, inferno and RdBu from matplotlib's own tables; map colours change slightly: these colormaps now match matplotlib's exactly, so a map drawn with them differs a little from 0.11.0 ([2e12b2f](https://github.com/macEMSuite/MacEMUI/commit/2e12b2fd21d3fd39b5c59af76724b1b9c4ac16dc))
* give the profile chart one accessibility element with its axes and units ([#149](https://github.com/macEMSuite/MacEMUI/issues/149)) ([eaf91a1](https://github.com/macEMSuite/MacEMUI/commit/eaf91a15d6bcb52d10a5c68035870b47913909b3))
* name every progress spinner for VoiceOver and show Cancel's key ([#150](https://github.com/macEMSuite/MacEMUI/issues/150)) ([e27e760](https://github.com/macEMSuite/MacEMUI/commit/e27e760317fb24a6e6da43e3c5e105ff8e7e3859))
* the EDS pins CSV reads back with Windows line ends and names that hold a line break ([#147](https://github.com/macEMSuite/MacEMUI/issues/147)) ([c2b53ba](https://github.com/macEMSuite/MacEMUI/commit/c2b53ba62d27ff75d8cd16cd4e82a881e7e0043a))
* the memory glance shows whole figures, then the chip alone, never a cut number ([#159](https://github.com/macEMSuite/MacEMUI/issues/159)) ([09ee052](https://github.com/macEMSuite/MacEMUI/commit/09ee0525740046988c870d50fe8a471653fd9e02))
* the Metal picture is tagged sRGB, so on a P3 display it shows the colours its swatch shows; map colours change slightly on a wide-gamut display, where 0.11.0 drew them more saturated ([977fd6e](https://github.com/macEMSuite/MacEMUI/commit/977fd6e0f8899409e0665b3501def0a0c1582e90))
* write EDS counts without a grouping separator ([#145](https://github.com/macEMSuite/MacEMUI/issues/145)) ([a48d240](https://github.com/macEMSuite/MacEMUI/commit/a48d240128d648c862286f76a7219c5e48e4d1c5)), closes [#89](https://github.com/macEMSuite/MacEMUI/issues/89)


### Performance Improvements

* build each colormap's 256-entry LUT once instead of on every redraw ([#152](https://github.com/macEMSuite/MacEMUI/issues/152)) ([c226c56](https://github.com/macEMSuite/MacEMUI/commit/c226c56d59730e6a000cb369eff4b40eeaed3c4a))
* map pictures window and gamma the whole map in Accelerate passes ([#157](https://github.com/macEMSuite/MacEMUI/issues/157)) ([088abc0](https://github.com/macEMSuite/MacEMUI/commit/088abc01bdfe7d9c5c310e769dd20855c89cd2ac))
* the map Display popover reads only the colour scheme, not the whole environment ([#154](https://github.com/macEMSuite/MacEMUI/issues/154)) ([dbd49d8](https://github.com/macEMSuite/MacEMUI/commit/dbd49d8b550b20a7917e4917900fe096dacde8d7))
* the profile chart thins a long line to each run's extremes; Output's Clear reads isEmpty ([#153](https://github.com/macEMSuite/MacEMUI/issues/153)) ([4ea3e86](https://github.com/macEMSuite/MacEMUI/commit/4ea3e86cb4cb05ad39fd8cd9bf22b6f478d80836))

## [0.11.0](https://github.com/macEMSuite/MacEMUI/compare/0.10.0...0.11.0) (2026-11-14)


### Features

* MetalImageView draws a log display transfer in the shader ([#137](https://github.com/macEMSuite/MacEMUI/issues/137)) ([e9949c0](https://github.com/macEMSuite/MacEMUI/commit/e9949c03ca562f83ad48e8b240a179f7eb8c7f8d))


### Bug Fixes

* a narrow infobar keeps the task words, drops run times first, and the glance keeps room for its icon ([#140](https://github.com/macEMSuite/MacEMUI/issues/140)) ([50afd2d](https://github.com/macEMSuite/MacEMUI/commit/50afd2dad3d4db68875e98cdc61f1f4e96436f3f))
* the infobar's pane toggles keep their place and size ([#135](https://github.com/macEMSuite/MacEMUI/issues/135)) ([bf4b546](https://github.com/macEMSuite/MacEMUI/commit/bf4b5469522c27dbb2dfa6a38318b654e4a16e10))

## [0.10.0](https://github.com/macEMSuite/MacEMUI/compare/0.9.1...0.10.0) (2026-11-13)


### Features

* Claude desktop extension for the agent door (macEM.mcpb, mac4DSTEM.mcpb) ([#95](https://github.com/macEMSuite/MacEMUI/issues/95)) ([119c03c](https://github.com/macEMSuite/MacEMUI/commit/119c03c870d4d5dde3ce6c46a5d476a4f8f08fe8))


### Bug Fixes

* say why an image pane is empty instead of trapping or staying blank ([#132](https://github.com/macEMSuite/MacEMUI/issues/132)) ([72f6f54](https://github.com/macEMSuite/MacEMUI/commit/72f6f54d8cb6d2939f355cc42c9a743ea47ccb3b))

## [0.9.1](https://github.com/mac4DSTEM/MacEMUI/compare/0.9.0...0.9.1) (2026-11-12)


### Bug Fixes

* the Auto ID button writes a status line ([#117](https://github.com/mac4DSTEM/MacEMUI/issues/117)) ([a644a1e](https://github.com/mac4DSTEM/MacEMUI/commit/a644a1eea1a477da4220c5eebd4b84984e3575a1))

## [0.9.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.8.0...0.9.0) (2026-11-12)


### Features

* agent door speaks MCP 2026-07-28 and 2025-11-25, with structured results ([#109](https://github.com/mac4DSTEM/MacEMUI/issues/109)) ([75c3d62](https://github.com/mac4DSTEM/MacEMUI/commit/75c3d62ecf90b08d2e932b7822413af6e140654a))
* agent door tools for the shared EDS room ([#110](https://github.com/mac4DSTEM/MacEMUI/issues/110)) ([816954b](https://github.com/mac4DSTEM/MacEMUI/commit/816954b6b95c1b2072fbbcb6e883c50fee939cb3))
* the image display draws images over 16384 px and can take raw pixels without a normalised copy; Spectrum as MSA proposes .msa; map tile names stay readable ([#107](https://github.com/mac4DSTEM/MacEMUI/issues/107)) ([4542444](https://github.com/mac4DSTEM/MacEMUI/commit/4542444e254e765365dd410088be38192ed8d169))


### Bug Fixes

* the Absorption switch is off and disabled for a file without detector geometry ([#113](https://github.com/mac4DSTEM/MacEMUI/issues/113)) ([5dae498](https://github.com/mac4DSTEM/MacEMUI/commit/5dae498eedf5d4581b688c85ea55e910a707e02d)), closes [#112](https://github.com/mac4DSTEM/MacEMUI/issues/112)
* the EDS spectrum's count axis has round ticks and labels that fit ([#115](https://github.com/mac4DSTEM/MacEMUI/issues/115)) ([34281dc](https://github.com/mac4DSTEM/MacEMUI/commit/34281dcad2db4b3f1e4f991dd995597baa7307dd)), closes [#114](https://github.com/mac4DSTEM/MacEMUI/issues/114)

## [0.8.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.7.0...0.8.0) (2026-11-12)


### Features

* the EDS room's Open button can hand the file to the app's one Open ([#102](https://github.com/mac4DSTEM/MacEMUI/issues/102)) ([5491549](https://github.com/mac4DSTEM/MacEMUI/commit/54915495e97fa607d39fd674df81cfa2e6099db2)), closes [#90](https://github.com/mac4DSTEM/MacEMUI/issues/90)

## [0.7.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.6.0...0.7.0) (2026-11-11)


### Features

* agent door tools that act, with typed inputs, behind a second switch ([#98](https://github.com/mac4DSTEM/MacEMUI/issues/98)) ([6abbc13](https://github.com/mac4DSTEM/MacEMUI/commit/6abbc138010f83146dc32bc3f9cebf7b6896f4f2))

## [0.6.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.5.2...0.6.0) (2026-11-11)


### Features

* shared agent door (ShellAgentDoor) for both apps ([f674402](https://github.com/mac4DSTEM/MacEMUI/commit/f6744025c4cc16e09a4ccca472d5aedf7c360191))
* the agent door is an MCP server over HTTP and keeps its token ([#93](https://github.com/mac4DSTEM/MacEMUI/issues/93)) ([991fecf](https://github.com/mac4DSTEM/MacEMUI/commit/991fecfe89ee1b29ef7218920c449e601b3d4e58))

## [0.5.2](https://github.com/mac4DSTEM/MacEMUI/compare/0.5.1...0.5.2) (2026-11-10)


### Bug Fixes

* Auto ID also searches each phase region's spectrum ([#83](https://github.com/mac4DSTEM/MacEMUI/issues/83)) ([60d81fa](https://github.com/mac4DSTEM/MacEMUI/commit/60d81fa0793cdbe914b89acc8135522180466170))

## [0.5.1](https://github.com/mac4DSTEM/MacEMUI/compare/0.5.0...0.5.1) (2026-11-05)


### Bug Fixes

* the EDS results header and exports name the kept region ([#69](https://github.com/mac4DSTEM/MacEMUI/issues/69)) ([1c7b9d0](https://github.com/mac4DSTEM/MacEMUI/commit/1c7b9d067c4a551f1388de8e7c2e65d15f18926e))
* the EDS typed-k and factors sheets read either decimal separator ([#72](https://github.com/mac4DSTEM/MacEMUI/issues/72)) ([02971a8](https://github.com/mac4DSTEM/MacEMUI/commit/02971a88fe0a80ecf65b919128a6f8cfe61b5dba))
* the typed-k and factors sheets keep their fields' and buttons' identifiers ([#74](https://github.com/mac4DSTEM/MacEMUI/issues/74)) ([03952bc](https://github.com/mac4DSTEM/MacEMUI/commit/03952bc8e09ccd72e2a5ca09818e60987a66a544))

## [0.5.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.4.0...0.5.0) (2026-11-01)


### ⚠ BREAKING CHANGES

* see the Migration paragraph of the pull request. A room that declared isAvailable keeps it as a plain property; pass the availability to WorkspaceRoomsSection(isAvailable:). Use ColorMix.toggle(_:among:) and ColorMix.selection(among:).
* EDXRoom(session:state:actions:) is now EDXRoom(session:state:actions:openExtensions:). The members made package are no longer visible to an app; see the Migration paragraph of the PR.
* delete the superseded map tile API; wire operationReadoutWidth ([#30](https://github.com/mac4DSTEM/MacEMUI/issues/30))

### Features

* a keyboard route to draw and move a region in the EDS room ([#40](https://github.com/mac4DSTEM/MacEMUI/issues/40)) ([a2e9e06](https://github.com/mac4DSTEM/MacEMUI/commit/a2e9e061859594deeda7c636e6894af00248d979))
* a SegmentedPicker segment can be disabled, with its reason ([#33](https://github.com/mac4DSTEM/MacEMUI/issues/33)) ([576ee05](https://github.com/mac4DSTEM/MacEMUI/commit/576ee051d6dfa3314eb32bd9bbc1fe1747ea4a7a))
* an overlay slot on MapTileView, and the map tiles sit in ImageViewport ([#57](https://github.com/mac4DSTEM/MacEMUI/issues/57)) ([29e4160](https://github.com/mac4DSTEM/MacEMUI/commit/29e4160a39833aca343f9eda7b1def20a879d952))
* delete the public API left unused after the map tile deletions ([#54](https://github.com/mac4DSTEM/MacEMUI/issues/54)) ([86f9e27](https://github.com/mac4DSTEM/MacEMUI/commit/86f9e2749aea106c1f208ed98b86389e13a2bca2))
* delete the superseded map tile API; wire operationReadoutWidth ([#30](https://github.com/mac4DSTEM/MacEMUI/issues/30)) ([a4f4683](https://github.com/mac4DSTEM/MacEMUI/commit/a4f4683ec68f62559d7872686e8b2b7e598326e8))
* Esc returns the EDS room to the arrow tool ([#36](https://github.com/mac4DSTEM/MacEMUI/issues/36)) ([9b8baec](https://github.com/mac4DSTEM/MacEMUI/commit/9b8baecd45150030e920dc64d883d293497b2199))
* ImageViewport, one zoomable container for every room picture ([#43](https://github.com/mac4DSTEM/MacEMUI/issues/43)) ([d701da6](https://github.com/mac4DSTEM/MacEMUI/commit/d701da67c0f491832289197bfac5160150fa5962))
* InspectorSection can start closed and draws a status glyph ([#32](https://github.com/mac4DSTEM/MacEMUI/issues/32)) ([83f96a7](https://github.com/mac4DSTEM/MacEMUI/commit/83f96a7bf54a3201dbfa1f231210bed8c2b38607))
* narrow the shared EDS room public API; the room takes its Open panel extensions ([#56](https://github.com/mac4DSTEM/MacEMUI/issues/56)) ([4d6371c](https://github.com/mac4DSTEM/MacEMUI/commit/4d6371cba8e5adc1157dedbeab0a152acd79f0d8))
* the EDS room no longer labels results as unvalidated ([#63](https://github.com/mac4DSTEM/MacEMUI/issues/63)) ([72455f6](https://github.com/mac4DSTEM/MacEMUI/commit/72455f6d747d339f06bfc99bce03de53d4ada3b3))
* the maps zoom by the panes' ZoomPan; ⌥-scroll pans; View &gt; Zoom acts on the maps ([8ab277f](https://github.com/mac4DSTEM/MacEMUI/commit/8ab277f5cf96e6fad72283c10f5fa31b7b00cfc2))
* the maps zoom by ZoomPan, option-scroll pans, View &gt; Zoom acts on the maps ([#34](https://github.com/mac4DSTEM/MacEMUI/issues/34)) ([8ab277f](https://github.com/mac4DSTEM/MacEMUI/commit/8ab277f5cf96e6fad72283c10f5fa31b7b00cfc2))


### Bug Fixes

* a double click on a map tile no longer also fires its single click ([#31](https://github.com/mac4DSTEM/MacEMUI/issues/31)) ([78c1852](https://github.com/mac4DSTEM/MacEMUI/commit/78c1852dce16207c8d8f9016da79fc445b95668d))
* a late progress update of a replaced EDS open no longer overwrites the newer open ([#55](https://github.com/mac4DSTEM/MacEMUI/issues/55)) ([b83da8e](https://github.com/mac4DSTEM/MacEMUI/commit/b83da8e32d24e9a50b2e2e1fec03dd9d5b776a63))
* a room row whose selection is disabled no longer keeps its highlight ([#50](https://github.com/mac4DSTEM/MacEMUI/issues/50)) ([d29581d](https://github.com/mac4DSTEM/MacEMUI/commit/d29581d49be8e6da81c32b0036279bcb4dfa0dd5))
* histogram captions read low and high while windowed ([#53](https://github.com/mac4DSTEM/MacEMUI/issues/53)) ([b1b0ffd](https://github.com/mac4DSTEM/MacEMUI/commit/b1b0ffda4a1b970fbdccc4fe13a03c14eb2cf31b))
* the busy line speaks the same elapsed time it draws ([#45](https://github.com/mac4DSTEM/MacEMUI/issues/45)) ([ea886b1](https://github.com/mac4DSTEM/MacEMUI/commit/ea886b1adf8a044bc2b09b9ebb492ba3002dcd45))
* the colourbar strip interpolates its LUT like the image does ([#47](https://github.com/mac4DSTEM/MacEMUI/issues/47)) ([afd24f5](https://github.com/mac4DSTEM/MacEMUI/commit/afd24f5f3547401b24ce75e243023ec89ee5035a))
* the EDS results columns hold the whole value and its sigma ([#58](https://github.com/mac4DSTEM/MacEMUI/issues/58)) ([eba6ac1](https://github.com/mac4DSTEM/MacEMUI/commit/eba6ac132f3e6e4a11b664ab6e75e62d1179b280))
* the EDS room reads a typed beam energy everywhere and refuses a Fit to below 0.2 keV in words ([#41](https://github.com/mac4DSTEM/MacEMUI/issues/41)) ([c6397eb](https://github.com/mac4DSTEM/MacEMUI/commit/c6397ebcb475b424cf54e1ddd26c6b1dd0b7013b))
* the maps PNG draws the pinned regions and lines as the colour mix does ([#60](https://github.com/mac4DSTEM/MacEMUI/issues/60)) ([34b2721](https://github.com/mac4DSTEM/MacEMUI/commit/34b2721f4ae080168a3ef715bf4f8ddad321f749))
* typing the shown text over a finer stored value sets it ([#46](https://github.com/mac4DSTEM/MacEMUI/issues/46)) ([8e5f497](https://github.com/mac4DSTEM/MacEMUI/commit/8e5f49773fd7500de37ad5242db2f1a9f9be3ea3))

## [0.4.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.3.2...0.4.0) (2026-10-29)


### Features

* the shared EDS room (ShellEDXModel, EDXRoom in ShellSpectroscopy) ([#24](https://github.com/mac4DSTEM/MacEMUI/issues/24)) ([ecd5266](https://github.com/mac4DSTEM/MacEMUI/commit/ecd5266291c2cfe3a61c2d8170bf0cc005532a94))


### Bug Fixes

* compile the colormap shaders from source when the bundle has no metallib ([#21](https://github.com/mac4DSTEM/MacEMUI/issues/21)) ([066cfab](https://github.com/mac4DSTEM/MacEMUI/commit/066cfab71e3ac96e9cc4df5516b6f5adfbf64b3d))

## 0.3.2 (2026-10-28)

MacEMUI deploys to macOS 26, so the apps can build and run their CI on the macos-26 runner (SDK 26.x).

### Changed
- `Package.swift`: platform `.macOS(.v26)` (was `.macOS("27.0")`). `ToolbarItem.highVisibilityPriority()` applies
  `visibilityPriority(.high)` only on macOS 26.1 or newer, where SwiftUI has it; on 26.0 the item keeps the default priority.
- Source and test comments no longer carry move history or pointers to material outside this repository.

### Added
- `NOTICE`, `CONTRIBUTING.md` and `SECURITY.md`.

### Migration
- None for consumers on macOS 27. An app may now lower its own deployment target to macOS 26.

## 0.3.1 (2026-10-27)

MacEMUI builds with Xcode 26.6 again, so both apps' CI can go green, and it has CI of its own.

### Fixed
- `ShellToolbar`: both `visibilityPriority(.high)` call sites (the verb and the document menu) go through one helper that
  applies it only with Swift 6.4 or newer (Xcode 27). 0.3.0 guarded one site at Swift 6.3, which the macos-26 runner's
  Xcode 26.6 (Swift 6.3.3) passes without having the member, and left the other unguarded. Nothing changes on Xcode 27.
- The Metal tests (`MTLTextureFloatTests`, `MetalEngineDisplayTests`) are skipped on a machine without a Metal device
  instead of failing or stopping the run.

### Added
- CI: `swift test -c release --parallel` on macos-26 (Xcode 26.6) and on xcode-27 for every push and pull request, a
  check that a tag equals the CHANGELOG's top version, and Dependabot for the workflow's actions.
- A README for the public: what MacEMUI is, its products, how to depend on it, the licence.

### Migration
None. An app re-pins `exact: "0.3.1"`; no call site changes.

## 0.3.0 (2026-10-22)

The corrected spectroscopy room (design 2026-10-22, approved after a drive on a real 1.7 GB file): the colour mix as the anchor tile where regions are drawn, maps fitted to the space they are given, one cursor, every
control in the inspector, the scale bar as the way into a map's colour, an element control with the role and line menu on the cell.

### Added
- `MapTileView` (the map's frame: name and line on one row, calibrated scale bar that opens the map's controls, the colour scale and the pointer's value while hovered, one cursor, a ring and a click for the colour mix, regions and tools on the anchor
  tile only), `MapTileRegions`, `MapColorbarSpec`, `MapColorbarView`; `AnchoredMapsBlock`, `FittedMapGrid`, `FittedTileLayout` (pure) and `HorizontalPaneSplit`: the anchor beside the fitted maps with a draggable divider, tiles keeping their identity across a resize.
- `PeriodicTable` with `PeriodicTableActions`, `PeriodicCellState`, `ElementRoleChoice`, `ElementLineFamily`: the periodic table moved from mac4DSTEM, session-free (click toggles Quantify and Off; right-click gives the role and, per family, the lines with their energies, and Default lines);
  `PeriodicTableGrid` holds the symbols and the shape.
- `MapMixControls`: which maps are in the colour mix. `MapColorControls` can open with its sliders expanded and without the mix switch (a one-map popover).
- `MapAppearance.reset(maps:)`: returns only the listed maps to their default colouring and adjustment, leaving other maps and the colour mix.
- `zoomPanWheel(_:box:)` and `ZoomPan.wheel(delta:isPrecise:at:in:)` (ShellControls): the wheel and a two-finger scroll zoom a pane about the pointer by `ScrollZoom.factor`, every event, through the pinch's clamp; opt-in beside `zoomPan`, through the bounded `onScrollWheel` (no application-wide monitor).
- `SegmentedControl` and `SegmentedPicker` (ShellControls): the inspector's one segmented control, always the full width it is given (`NSSegmentedControl` with `.fillEqually`, named as the one AppKit piece: SwiftUI's segmented `Picker` keeps its intrinsic width on macOS), titles or SF symbols per segment, a tooltip and an accessibility label each; a selection not among the items shows none.
- `MapDisplayPopover` and `MapHistogram` (pure bins and statistics): the display popover a tile's scale bar opens, the one both apps show (the Spectroscopy room's): an element map's colour, the reference image's colormap or the colour mix's members, then the map's histogram with its contrast-window handles, Reset Range and a gamma slider. Values and bindings in, no model.
- `MapTileView(filteredTag:)`: a small "filtered" tag beside the title while the picture is drawn through a display filter.
- `MapColoring` (black to one colour, or one of the shared colormaps), `MapAppearance` (the person's choice per map and the colour mix; Codable), `ColorMix`, `MapRaster` (`rgba` for one map, `mix` for the colour mix of several, pure) and `MapColorControls`, the Maps section's rows: a colour or colormap per map and the Colour mix with the maps in it. `ColormapKind` is Codable.
- `MapAdjustment` (a map's contrast window as fractions of its scale, and its gamma) kept in `MapAppearance.adjustments`, applied by `MapRaster.rgba(…adjustment:)` and each `MixLayer`, and set by a slider disclosure on every row of `MapColorControls`; an appearance saved before it still decodes.
- `RegionDrawingLayer(onDrag:)`: the geometry so far while a region is being drawn (`id` nil) or moved or resized (`id` set), nil when the drag ends, so a room can follow the pointer with its spectrum.

### Changed
- `MapTileView` draws nothing over a picture but the cursor: the hover value chip and the hover colour scale are gone (control placement standard, rule 7: the status line carries the value, the popover's histogram the scale). `colorbar:` and `valueText:` are still accepted and ignored so mac4DSTEM compiles; delete at 0.4.0. `MapColorbarView` stays public.

### Fixed
- `ShellToolbar`: the verb's `visibilityPriority(.high)` is compiled only with Swift 6.3 or newer (the Xcode 27 beta); the CI runners' Xcode 26 has no such member on `ToolbarItem`, which had both apps' CI red on main. The item itself is unchanged.
- The scroll wheel reaches a view under SwiftUI content: `onScrollWheel` uses a local event monitor bounded to its own window and view (call sites unchanged).
- The one-map colour popover: no toggle icon (the sliders are always shown), and Reset acts on that map only and leaves the colour mix untouched.

### Superseded
- `MapTileGrid`, `MapTileSize` and `MapTileSizePicker` (a size to choose): the fitted grid scales with the panes instead. They stay until 0.4.0 so mac4DSTEM can move; macTEM no longer uses them.


### Migration
`RegionTool` gained `.pointer` as its FIRST case: `allCases` starts with it and a stored tool decodes by its raw value (the strings are unchanged), so a room that indexed the cases by position re-reads them by case; the default tool of a room is its own choice (macTEM's rooms start on `.pointer`). `ColorMix.isShown` (members only) is gone: `isShown(among:)` takes the maps, so the default mix (every map in) counts. `MapDisplayPopover` takes a `MapDisplayHistogram` value, not a tuple. A tile no longer shows the pointer's value or a colour scale: a room puts the value in its status line (`onHover`) and opens `MapDisplayPopover` from the scale bar (`controls:`); `colorbar:` and `valueText:` are ignored until 0.4.0 removes them. A room that wants the corrected layout builds `AnchoredMapsBlock` of `MapTileView`s (macTEM's `EDXMapsBlock` is the reference wiring), puts the region tool, the maps' quantity and the lower pane's choices in its inspector instead of a strip above the maps, and answers
`PeriodicTable` from its model.

## 0.2.0 (2026-10-22)

The spectroscopy rooms' shared chrome (design 2026-10-22): a new product `ShellSpectroscopy`, built in macTEM's EDS and EELS rooms and offered to mac4DSTEM's Spectroscopy room. Nothing of 0.1.0 changed.

### Added
- `VerticalPaneSplit`: maps over spectrum with a stored, keyboard-nudgeable, VoiceOver-adjustable divider.
- `SpectralRegionSet`, `SpectralRegion`, `RegionGeometry` (rectangle, ellipse, polygon, line), `RegionColor`, `RegionPalette`: any number of regions with a name, colour and visible flag, Codable for the session; `RegionsList` (inspector list: select, rename, recolour, show/hide, delete) and `RegionOverlay` (outlines over a map tile). No pixel or number is computed here: the app turns a geometry into the kit's shape.
- `SpectrumLayer`, `SpectrumScale`, `SpectrumLayerPlot` (min-max thinning, peak, shape normalisation, `draw` into the room's Canvas) and `SpectrumLayerLegend`: one spectrum per region in its colour, plus a dashed temporary pixel layer.
- `SpectrumPane`, `SpectrumPaneTabs` (Spectrum, Profile, Table) and `ProfileSeries`, `ProfileChart` (Swift Charts, distance on x, one coloured line per series).
- `RegionTool` and `RegionDrawingLayer`: the drawing gestures over a map tile (drag a rectangle, ellipse or line, click a polygon's vertices) that hand back what was drawn in scan pixels and mark the pointer's pixel; `RegionDrawing` holds the pure geometry.
- `RegionEditing` and the layer's `onEdit`: the selected region shows handles (eight on a rectangle or ellipse, a vertex each on a polygon, the two ends of a line); a drag on a handle resizes, a drag inside moves; boxes snap to whole pixels. Editing a polygon works under every tool.
- `MapTileGrid`, `MapTileSize`, `MapTileSizePicker` (a segmented control that becomes a menu in a column too narrow for it): the maps block reflows to a chosen tile size and shows one tile alone on a double click; `hoverChip(_:)` puts the pointer's value on a tile.

### Migration
An app adds the product `ShellSpectroscopy` to its target and imports it where it uses a piece; no call site of 0.1.0 changes. The region model is plain values in scan pixels (the app maps its own regions to `SpectralRegionSet`, and a drawn `RegionGeometry` to the kit's shape).

## 0.1.0 (2026-10-22)

The shared window shell of mac4DSTEM and macTEM, cut from mac4DSTEM `8c4c06d` and macTEM `51c944c`, compiled and adopted by both apps
the same day. Four products: ShellMetal (the Metal image view, display transform, colormaps), ShellControls (zoom and pan, number
fields, scale bar, colorbar, histogram chart, pane footer), ShellInspector (the inspector row kit) and ShellLayout (layout policy, panel
navigation, menu relay, activity log, system monitor, window skeleton, toolbar, sidebar and inspector frames, the infobar and process area,
Output). The histogram footer prints 4 significant digits with Reset Range on its own line.

### Migration
Both apps add the package (local path `../MacEMUI` in development, exact tag `0.1.0` at closeout), import the modules they use
(`MemberImportVisibility` is on), delete their copies and their provenance headers. An app's own room enum conforms to `WorkspaceRoom`
(`nonisolated`), holds a `PanelNavigation` as `panels`, and takes `ShellWindow`, `WorkspaceColumn`, `WorkspaceSidebarFrame` and
`WorkspaceInspectorFrame` for its chrome.
