import FormatoCore
import ShellExport

/// Pin M1's records: one per room and export kind this package can name before the app fills them (X1): a Diffraction
/// figure, an EDS spectrum CSV, an Imaging PNG, an EBSD .ang and an EDS HyperSpy file. Every number is a literal; the file
/// names, sizes and fingerprints are made up (each fingerprint is the SHA-256 of "EMSuiteUI methods test: <file name>").
struct NamedRecord: Sendable {
    let name: String
    let record: MethodsRecord
}

enum MethodsTestRecords {
    static var all: [NamedRecord] { [diffraction, edsSpectrum, imaging, ebsd, edsHyperSpy] }

    static let studio = MethodsRecord.Software(name: "Electron Microscopy Studio", version: "2.4.0")

    static func software(_ name: String, _ version: String) -> MethodsRecord.Software {
        MethodsRecord.Software(name: name, version: version)
    }

    static func quantity(_ name: String, _ value: FormatoValue, _ units: String? = nil) -> MethodsRecord.Quantity {
        MethodsRecord.Quantity(name: name, value: value, units: units)
    }

    static func calibration(_ key: String, _ value: FormatoValue, _ units: String?, file: String, source: String,
                            rule: String) -> FormatoMetadataEntry {
        FormatoMetadataEntry(key: key, value: value, units: units, provenance: FormatoProvenance(file: file, source: source, rule: rule))
    }

    static let diffraction = NamedRecord(
        name: "diffraction-figure-pdf",
        record: MethodsRecord(
            app: studio, room: "diffraction", exportKind: "figure-pdf",
            kits: [
                software("DiffractoKit", "0.21.0"),
                software("FormatoKit", "0.19.0"),
            ],
            references: [
                software("py4DSTEM", "0.14.0"),
            ],
            sources: [
                MethodsRecord.Source(fileName: "frame_012.dm4", byteCount: 16_777_824,
                                     fingerprint: "8ee10af1b3bc9e91a77645ecfb1fab016abc62a3695c29de49685f5be3a1a4c9",
                                     kind: "diffraction pattern", shape: [2048, 2048], calibrations: [
                    calibration("axes.kx.scale", .number(0.01), "nm⁻¹",
                                file: "frame_012.dm4", source: "ImageList.2.ImageData.Calibrations.Dimension.0.Scale",
                                rule: "rsciio digitalmicrograph axes: scale"),
                    calibration("Acquisition_instrument.TEM.beam_energy", .number(200), "kV",
                                file: "frame_012.dm4", source: "ImageList.2.ImageTags.Microscope Info.Voltage",
                                rule: "rsciio digitalmicrograph mapping: value / 1000"),
                ]),
            ],
            phases: [
                MethodsRecord.Phase(name: "aluminium", spaceGroup: "Fm-3m", cell: MethodsRecord.Cell(cubic: 4.0495),
                                    source: "Materials Project mp-134", fetched: "2026-11-23", licence: "CC BY 4.0", latticeEdited: true),
            ],
            steps: [
                MethodsRecord.Step(name: "Indexing", method: "the kinematic model", reference: software("py4DSTEM", "0.14.0"), settings: [
                    quantity("excitation error", .number(0.02), "Å⁻¹"),
                    quantity("zone axis", .text("[001]")),
                ]),
            ],
            results: [
                quantity("The fitted scale's difference from the stored scale", .number(0.4), "%"),
            ],
            drawn: [
                "the pattern",
                "the spot overlay with hkl labels",
                "a scale bar",
            ],
            citations: [
                MethodsRecord.Citation(text: "Electron Microscopy Studio 2.4.0"),
                MethodsRecord.Citation(text: "Savitzky et al. (2021) Microsc. Microanal. 27, 712–743", doi: "10.1017/S1431927621000477"),
                MethodsRecord.Citation(text: "Jain et al. (2013) APL Mater. 1, 011002", doi: "10.1063/1.4812323"),
            ]))

    static let edsSpectrum = NamedRecord(
        name: "eds-spectrum-csv",
        record: MethodsRecord(
            app: studio, room: "eds", exportKind: "spectrum-csv",
            kits: [
                software("FormatoKit", "0.19.0"),
                software("SpectroKit", "0.13.0"),
            ],
            references: [
                software("exspy", "0.3.2"),
            ],
            sources: [
                MethodsRecord.Source(fileName: "particle_03.emd", byteCount: 2_431_552,
                                     fingerprint: "e22ca82909e0735d28b6da3e0660d7fbdf39f04e50e18b88e08d9d80aadbb013",
                                     kind: "spectrum", shape: [4096], calibrations: [
                    calibration("axes.energy.scale", .number(0.005), "keV",
                                file: "particle_03.emd", source: "Data/Spectrum/a3f1/Metadata[0].BinaryResult.Detector.Dispersion",
                                rule: "rsciio emd velox: value / 1000"),
                    calibration("Acquisition_instrument.TEM.beam_energy", .number(200), "kV",
                                file: "particle_03.emd", source: "Data/Spectrum/a3f1/Metadata[0].Optics.AccelerationVoltage",
                                rule: "rsciio emd velox: value / 1000"),
                ]),
            ],
            steps: [
                MethodsRecord.Step(name: "Background subtraction", method: "a power law", reference: software("exspy", "0.3.2"), settings: [
                    quantity("window start", .number(1.2), "keV"),
                    quantity("window end", .number(3.4), "keV"),
                ]),
                MethodsRecord.Step(name: "Quantification", method: "the Cliff–Lorimer method", reference: software("exspy", "0.3.2"), settings: [
                    quantity("elements", .texts(["Fe", "Cr", "Ni"])),
                    quantity("absorption correction", .flag(false)),
                ]),
            ],
            results: [
                quantity("The Fe content", .number(70.12), "wt%"),
                quantity("The Cr content", .number(18.5), "wt%"),
                quantity("The Ni content", .number(11.38), "wt%"),
            ],
            drawn: [
                "the spectrum",
                "the fitted background",
                "the element lines",
            ],
            citations: [
                MethodsRecord.Citation(text: "Cliff and Lorimer (1975) J. Microsc. 103, 203–207", doi: "10.1111/j.1365-2818.1975.tb03895.x"),
            ]))

    static let imaging = NamedRecord(
        name: "imaging-png",
        record: MethodsRecord(
            app: studio, room: "imaging", exportKind: "png",
            kits: [
                software("FormatoKit", "0.19.0"),
                software("ImagoKit", "0.8.0"),
            ],
            references: [
                software("scikit-image", "0.25.2"),
            ],
            sources: [
                MethodsRecord.Source(fileName: "grain_04.dm4", byteCount: 4_198_400,
                                     fingerprint: "746f3295b29d973cec189e6381ecde67a5478ef4d0b27df2ff77e3f168de2833",
                                     kind: "image", shape: [1024, 1024], calibrations: [
                    calibration("axes.x.scale", .number(0.25), "nm",
                                file: "grain_04.dm4", source: "ImageList.2.ImageData.Calibrations.Dimension.0.Scale",
                                rule: "rsciio digitalmicrograph axes: scale"),
                    calibration("Acquisition_instrument.TEM.beam_energy", .number(300), "kV",
                                file: "grain_04.dm4", source: "ImageList.2.ImageTags.Microscope Info.Voltage",
                                rule: "rsciio digitalmicrograph mapping: value / 1000"),
                ]),
            ],
            steps: [
                MethodsRecord.Step(name: "Filtering", method: "a Gaussian filter", reference: software("scikit-image", "0.25.2"), settings: [
                    quantity("sigma", .number(1.5), "px"),
                ]),
            ],
            drawn: [
                "the image",
                "a scale bar",
            ]))

    static let ebsd = NamedRecord(
        name: "ebsd-ang",
        record: MethodsRecord(
            app: studio, room: "maps", exportKind: "ang",
            kits: [
                software("DiffractoKit", "0.21.0"),
                software("FormatoKit", "0.19.0"),
            ],
            references: [
                software("PyEBSDIndex", "0.3.8"),
                software("kikuchipy", "0.11.2"),
            ],
            sources: [
                MethodsRecord.Source(fileName: "steel_map.h5", byteCount: 1_200_096_256,
                                     fingerprint: "f7f34d53f6a97e253429f550af98c7b6ba4a2eea3c9410ca13acac56598bcdc7",
                                     kind: "EBSD scan", shape: [200, 150, 60, 60], calibrations: [
                    calibration("axes.x.scale", .number(0.5), "µm",
                                file: "steel_map.h5", source: "Scan 1/EBSD/Header/Step X",
                                rule: "kikuchipy h5ebsd: as stored"),
                ]),
            ],
            phases: [
                MethodsRecord.Phase(name: "austenite", spaceGroup: "Fm-3m", cell: MethodsRecord.Cell(cubic: 3.595),
                                    source: "COD 9008469", licence: "CC0"),
                MethodsRecord.Phase(name: "ferrite", spaceGroup: "Im-3m", cell: MethodsRecord.Cell(cubic: 2.8665),
                                    source: "Materials Project mp-13", fetched: "2026-11-02", licence: "CC BY 4.0"),
                MethodsRecord.Phase(name: "α-titanium", spaceGroup: "P6_3/mmc",
                                    cell: MethodsRecord.Cell(a: 2.9508, b: 2.9508, c: 4.6855, alpha: 90, beta: 90, gamma: 120),
                                    source: "Ti_alpha.cif", licence: ""),
            ],
            steps: [
                MethodsRecord.Step(name: "Indexing", method: "Hough indexing", reference: software("PyEBSDIndex", "0.3.8"), settings: [
                    quantity("band count", .number(9)),
                    quantity("pattern binning", .number(2)),
                ]),
                MethodsRecord.Step(name: "Refinement", method: "orientation refinement", reference: software("kikuchipy", "0.11.2"), settings: [
                    quantity("method", .text("Nelder-Mead")),
                    quantity("tolerance", .number(0.001)),
                ]),
            ],
            results: [
                quantity("The mean confidence index", .number(0.82)),
            ],
            drawn: [
                "the orientations",
                "the phase of each point",
                "the confidence index",
            ],
            citations: [
                MethodsRecord.Citation(text: "Rowenhorst et al. (2015) Modelling Simul. Mater. Sci. Eng. 23, 083501",
                                       doi: "10.1088/0965-0393/23/8/083501"),
            ]))

    static let edsHyperSpy = NamedRecord(
        name: "eds-hspy",
        record: MethodsRecord(
            app: studio, room: "eds", exportKind: "hspy",
            kits: [
                software("FormatoKit", "0.19.0"),
                software("SpectroKit", "0.13.0"),
            ],
            references: [
                software("HyperSpy", "2.5.0"),
            ],
            sources: [
                MethodsRecord.Source(fileName: "map_07.emd", byteCount: 1_073_742_848,
                                     fingerprint: "308407cdbe84af14445e7bfd4de74fb346f4b0292ee34d2e7df2d26c353f19d1",
                                     kind: "spectrum image", shape: [64, 64, 2048], calibrations: [
                    calibration("axes.energy.scale", .number(0.01), "keV",
                                file: "map_07.emd", source: "Data/SpectrumImage/7c20/Metadata[0].BinaryResult.Detector.Dispersion",
                                rule: "rsciio emd velox: value / 1000"),
                ]),
                MethodsRecord.Source(fileName: "survey_07.dm4", byteCount: 1_049_088,
                                     fingerprint: "c6a63d5ae582e2f698ba6a282753549f188ec63a84ad23559827fd65b89cbc61",
                                     kind: "survey image", shape: [512, 512]),
            ],
            steps: [
                MethodsRecord.Step(name: "Binning", method: "sum binning", settings: [
                    quantity("factor", .number(2)),
                ]),
            ],
            citations: [
                MethodsRecord.Citation(text: "HyperSpy 2.5.0", doi: "10.5281/zenodo.592838"),
            ]))
}
