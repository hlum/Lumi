import CoreML
import Foundation

/// A job a Core ML model does for the app. Each slot says which inputs and outputs the code feeds and reads, by role,
/// so a better model can be dropped in as long as it names those features (the entry maps roles to the model's own names).
enum ModelSlot: String, Codable, CaseIterable, Identifiable {
    case inpaint, upscale, colorize, hairSegmentation, personMatting, faceParsing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inpaint: "Object removal"
        case .upscale: "Enhance (upscale)"
        case .colorize: "Colorize"
        case .hairSegmentation: "Hair mask"
        case .personMatting: "Person cutout"
        case .faceParsing: "Face parts"
        }
    }
    var inputRoles: [String] {
        switch self {
        case .inpaint: ["image", "mask"]
        case .upscale, .colorize, .hairSegmentation, .personMatting, .faceParsing: ["input"]
        }
    }
    var outputRoles: [String] { ["output"] }
    /// What `side` and `scale` mean for this slot, shown in the import form.
    var hint: String {
        switch self {
        case .inpaint: "Square window the model runs on, in pixels (side). Image is BGRA, mask is 8-bit, 1 = remove."
        case .upscale: "Tile size in pixels (side) and the scale it adds (scale)."
        case .colorize: "Lightness plane size (side). Input is L, output is the a and b channels."
        case .hairSegmentation: "Input size (side). Output is a 0...1 hair mask."
        case .personMatting: "Input size (side). Output is a 0...1 person matte."
        case .faceParsing: "Input size (side). Output is a class map."
        }
    }
}

struct ModelEntry: Codable, Equatable, Identifiable {
    var id: String
    var slot: ModelSlot
    var title: String
    var version = "1"
    var author = ""
    var license = ""
    var source = ""
    var file: String                      // "LaMa.mlmodelc"
    var io: [String: String]              // role -> the model's own feature name
    var side: Int?
    var scale: Int?
    var classIndex: Int?                  // for class-map outputs: the value that means "this is it" (hair = 17 in face parsing)
    var normalize: String?                // "imagenet": model takes a normalised float array instead of an image
    var units: String?                    // "cpuAndGPU" when the model was converted for the GPU only
    var bundled = false

    /// Roles the slot needs that the entry does not map.
    var missingRoles: [String] { (slot.inputRoles + slot.outputRoles).filter { io[$0] == nil } }

    static let bundledDefaults: [ModelEntry] = [
        ModelEntry(id: "lama", slot: .inpaint, title: "LaMa", version: "1", author: "Suvorov et al.; Core ML by john-rocky", license: "Apache-2.0", source: "huggingface.co/mlboydaisuke/LaMa-CoreML", file: "LaMa.mlmodelc", io: ["image": "image", "mask": "mask", "output": "output"], side: 800, bundled: true),
        ModelEntry(id: "face-parsing", slot: .hairSegmentation, title: "Face parsing (BiSeNet)", author: "zllrunning; Core ML by john-rocky", license: "MIT", source: "huggingface.co/mlboydaisuke/Face-Parsing-CoreML", file: "FaceParsing.mlmodelc", io: ["input": "input", "output": "argmax_out"], side: 512, classIndex: 17, units: "cpuOnly", bundled: true),
        ModelEntry(id: "birefnet-lite", slot: .personMatting, title: "BiRefNet Lite", author: "Peng Zheng et al.; Core ML by metaclass", license: "MIT", source: "huggingface.co/metaclass/birefnet-lite-coreml", file: "BiRefNetLite.mlmodelc", io: ["input": "image", "output": "mask_logits"], side: 1024, normalize: "imagenet", units: "cpuOnly", bundled: true),
        ModelEntry(id: "realesrgan-x4", slot: .upscale, title: "Real-ESRGAN x4", author: "Xintao Wang et al.", license: "BSD-3-Clause", source: "huggingface.co/mlboydaisuke/Real-ESRGAN-x4-CoreML", file: "RealESRGAN_x4.mlmodelc", io: ["input": "input", "output": "activation_out"], side: 512, scale: 4, bundled: true),
        ModelEntry(id: "siggraph17", slot: .colorize, title: "SIGGRAPH 2017 colorizer", author: "Zhang et al.", license: "BSD-2-Clause", source: "huggingface.co/c2p-cmd/bw_colorizer_coreml", file: "SIGGraph17Colorizer.mlmodelc", io: ["input": "input1", "output": "var_518"], side: 512, bundled: true),
    ]
}

enum ModelStoreError: Error, Equatable {
    case notFound(String)
    case incompatible(missing: [String])        // features the model does not have
    case unmappedRoles([String])
    case badFile
}

/// Finds, installs and chooses models. Bundled models ship in the app; installed ones live in Application Support and win when chosen.
/// Services ask for a slot's active model and rebuild when `revision` changes, so swapping needs no code change.
final class ModelStore {
    nonisolated(unsafe) static let shared = ModelStore()

    private let bundle: Bundle
    private let directory: URL
    private let defaults: [ModelEntry]
    private let fm = FileManager.default
    private let lock = NSLock()
    private(set) var revision = 0
    private var installed: [ModelEntry]
    private var selection: [String: String]

    init(bundle: Bundle = .main, directory: URL? = nil, defaults: [ModelEntry] = ModelEntry.bundledDefaults) {
        self.bundle = bundle; self.defaults = defaults
        let dir = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Models", isDirectory: true))
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        installed = (try? JSONDecoder().decode([ModelEntry].self, from: Data(contentsOf: dir.appendingPathComponent("installed.json")))) ?? []
        selection = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: dir.appendingPathComponent("selection.json")))) ?? [:]
    }

    // MARK: lookup

    func url(for e: ModelEntry) -> URL? {
        if e.bundled {
            let name = (e.file as NSString).deletingPathExtension, ext = (e.file as NSString).pathExtension
            return bundle.url(forResource: name, withExtension: ext)
        }
        let u = directory.appendingPathComponent(e.file)
        return fm.fileExists(atPath: u.path) ? u : nil
    }

    /// Every model for the slot whose files are actually there: bundled first, then installed.
    func entries(_ slot: ModelSlot) -> [ModelEntry] {
        lock.lock(); defer { lock.unlock() }
        return (defaults + installed).filter { $0.slot == slot && url(for: $0) != nil }
    }

    /// The chosen model if it is still there, else the first bundled one, else the first installed one.
    func active(_ slot: ModelSlot) -> ModelEntry? {
        let all = entries(slot)
        lock.lock(); let chosen = selection[slot.rawValue]; lock.unlock()
        return all.first { $0.id == chosen } ?? all.first { $0.bundled } ?? all.first
    }

    func isAvailable(_ slot: ModelSlot) -> Bool { active(slot) != nil }

    private var loaded: [ModelSlot: (id: String, revision: Int, model: MLModel)] = [:]

    /// Drops the models kept in memory (they load again on next use). The big fill model asks for this first.
    func unloadCached() { lock.lock(); loaded.removeAll(); lock.unlock() }

    /// Loads the slot's active model. Loading a big model takes seconds, so it is kept until a swap changes `revision`.
    func load(_ slot: ModelSlot, computeUnits: MLComputeUnits? = nil) throws -> (model: MLModel, entry: ModelEntry) {
        guard let e = active(slot), let u = url(for: e) else { throw ModelStoreError.notFound(slot.rawValue) }
        let units = computeUnits ?? (e.units == "cpuAndGPU" ? .cpuAndGPU : e.units == "cpuOnly" ? .cpuOnly : .all)
        lock.lock()
        if computeUnits == nil, let c = loaded[slot], c.id == e.id, c.revision == revision { lock.unlock(); return (c.model, e) }
        let rev = revision
        lock.unlock()
        let cfg = MLModelConfiguration(); cfg.computeUnits = units
        let m = try MLModel(contentsOf: u, configuration: cfg)
        if computeUnits == nil { lock.lock(); loaded[slot] = (e.id, rev, m); lock.unlock() }
        return (m, e)
    }

    // MARK: changes

    func select(_ id: String, for slot: ModelSlot) throws {
        guard entries(slot).contains(where: { $0.id == id }) else { throw ModelStoreError.notFound(id) }
        lock.lock(); selection[slot.rawValue] = id; lock.unlock()
        persist()
    }

    /// Back to the bundled model.
    func reset(_ slot: ModelSlot) {
        lock.lock(); selection[slot.rawValue] = nil; lock.unlock()
        persist()
    }

    func remove(_ id: String) throws {
        lock.lock()
        guard let i = installed.firstIndex(where: { $0.id == id }) else { lock.unlock(); throw ModelStoreError.notFound(id) }
        let e = installed.remove(at: i)
        for (k, v) in selection where v == id { selection[k] = nil }
        lock.unlock()
        try? fm.removeItem(at: directory.appendingPathComponent(e.file))
        persist()
    }

    /// Features a model must have for an entry, compared with what the model actually offers.
    static func missingFeatures(entry: ModelEntry, inputs: Set<String>, outputs: Set<String>) -> [String] {
        entry.slot.inputRoles.compactMap { entry.io[$0] }.filter { !inputs.contains($0) } + entry.slot.outputRoles.compactMap { entry.io[$0] }.filter { !outputs.contains($0) }
    }

    /// Adds a model from a `.mlmodelc`, `.mlpackage` or `.mlmodel` file. It is compiled if needed, checked against the entry's feature names,
    /// copied into the app's folder and chosen for its slot.
    func install(from source: URL, as entry: ModelEntry) async throws {
        var e = entry; e.bundled = false
        guard e.missingRoles.isEmpty else { throw ModelStoreError.unmappedRoles(e.missingRoles) }
        let ext = source.pathExtension.lowercased()
        let compiled: URL
        switch ext {
        case "mlmodelc": compiled = source
        case "mlpackage", "mlmodel": compiled = try await MLModel.compileModel(at: source)
        default: throw ModelStoreError.badFile
        }
        let probe = try MLModel(contentsOf: compiled)
        let miss = Self.missingFeatures(entry: e, inputs: Set(probe.modelDescription.inputDescriptionsByName.keys), outputs: Set(probe.modelDescription.outputDescriptionsByName.keys))
        guard miss.isEmpty else { throw ModelStoreError.incompatible(missing: miss) }

        e.file = "\(e.id)-\(e.version).mlmodelc"
        let dest = directory.appendingPathComponent(e.file)
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: compiled, to: dest)
        adopt(e)
    }

    /// Records an entry whose compiled model is already in the folder, and chooses it for its slot.
    func adopt(_ entry: ModelEntry) {
        lock.lock()
        installed.removeAll { $0.id == entry.id }; installed.append(entry); selection[entry.slot.rawValue] = entry.id
        lock.unlock()
        persist()
    }

    /// Tells the services a model appeared or went away.
    func noteChanged() { lock.lock(); revision += 1; lock.unlock(); NotificationCenter.default.post(name: .lumiModelsChanged, object: nil) }

    /// The folder installed models are copied into (tests and the import screen use it).
    var installedDirectory: URL { directory }

    /// What a model file offers, so the import form can map roles to its feature names. Compiles a package if needed.
    func inspect(_ source: URL) async throws -> (inputs: [String], outputs: [String]) {
        let compiled: URL
        switch source.pathExtension.lowercased() {
        case "mlmodelc": compiled = source
        case "mlpackage", "mlmodel": compiled = try await MLModel.compileModel(at: source)
        default: throw ModelStoreError.badFile
        }
        let m = try MLModel(contentsOf: compiled)
        return (m.modelDescription.inputDescriptionsByName.keys.sorted(), m.modelDescription.outputDescriptionsByName.keys.sorted())
    }

    private func persist() {
        lock.lock()
        let inst = installed, sel = selection
        revision += 1
        lock.unlock()
        try? JSONEncoder().encode(inst).write(to: directory.appendingPathComponent("installed.json"), options: .atomic)
        try? JSONEncoder().encode(sel).write(to: directory.appendingPathComponent("selection.json"), options: .atomic)
        NotificationCenter.default.post(name: .lumiModelsChanged, object: nil)
    }
}

extension Notification.Name { static let lumiModelsChanged = Notification.Name("lumiModelsChanged") }
