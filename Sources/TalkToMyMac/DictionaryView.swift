import AppKit
import SwiftUI
import TalkToMyMacCore
import UniformTypeIdentifiers

/// Settings tab for the custom dictionary: terms the speech model tends to mis-hear, passed
/// to the LLM formatting step so it can correct them. Adding a word asks Apple Intelligence
/// to fill in its details; clicking a word shows them for review and editing.
@available(macOS 26.0, *)
struct DictionaryView: View {
    let editor: DictionaryEditor
    @Bindable var settings: FormattingSettings
    let transcriber: TranscriptionRouter
    @State private var newWord = ""
    @State private var selection: UUID?
    /// Fuzzy filter over the word list; kept while a word's details are open.
    @State private var filter = ""
    /// Outcome of the last import or export, shown under the Storage buttons.
    @State private var transferMessage: String?

    var body: some View {
        if let selection, editor.item(selection) != nil {
            EntryDetailView(editor: editor, transcriber: transcriber, id: selection) { self.selection = nil }
                .id(selection)
        } else {
            listPage
        }
    }

    private var listPage: some View {
        Form {
            if !settings.resolvedInstructionsHavePlaceholder {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("The \(settings.preset.displayName) preset only gets a short version of "
                              + "the dictionary rules, which the on-device model follows poorly.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Button("Use Coding Dictation Preset") { settings.preset = .coding }
                    }
                }
            }

            Section {
                HStack {
                    TextField("Add a word or phrase, e.g. OTel", text: $newWord)
                        .labelsHidden()
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Dictionary")
            } footer: {
                Text("Words you use that transcription gets wrong. "
                     + (editor.canGenerate ? "Apple Intelligence fills in the details of each new word; " : "")
                     + "click a word to review them — especially “Heard as”, which works best with "
                     + "what transcription actually wrote (see the Transcriptions tab). The dictionary "
                     + "only applies when LLM formatting runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            storageSection

            wordsSection
        }
        // Grouped, like the other tabs: it scrolls, which a long word list needs (the default
        // columns style doesn't, and clips everything past the window's fixed height).
        .formStyle(.grouped)
        .frame(minWidth: 440)
        .onAppear {
            // Pick up edits made to the file elsewhere, e.g. on another Mac via iCloud.
            if let entries = settings.reloadDictionaryFile() {
                editor.replaceAll(entries)
            }
        }
    }

    // MARK: Words

    private var wordsSection: some View {
        let matches = DictionaryFilter.filter(editor.items, query: filter)
        let isFiltering = !filter.allSatisfy(\.isWhitespace)
        return Section {
            if editor.items.isEmpty {
                Text("No words yet.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter", text: $filter, prompt: Text("Filter words"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear filter")
                    }
                }
                if matches.isEmpty {
                    Text("No words match “\(filter.trimmingCharacters(in: .whitespaces))”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(matches) { item in
                    row(item)
                }
            }
        } header: {
            Text(isFiltering ? "Words (\(matches.count) of \(editor.items.count))" : "Words")
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        Section {
            LabeledContent("Folder") {
                if let folder = settings.dictionaryFolder {
                    Text((folder.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(DictionaryFile.url(in: folder).path)
                } else {
                    Text("None — stored in app preferences")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Choose Folder…", action: chooseFolder)
                if let folder = settings.dictionaryFolder {
                    Button("Show in Finder") {
                        let file = DictionaryFile.url(in: folder)
                        if FileManager.default.fileExists(atPath: file.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([file])
                        } else {
                            NSWorkspace.shared.open(folder)
                        }
                    }
                    Button("Stop Using Folder") {
                        editor.replaceAll(settings.useDictionaryFolder(nil))
                    }
                }
            }
            if let error = settings.dictionaryFileError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Button("Overwrite File with Current Dictionary") { settings.overwriteDictionaryFile() }
                }
            }
            HStack {
                Button("Import…", action: importFile)
                Button("Export…", action: exportFile)
            }
            if let transferMessage {
                Text(transferMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("With a folder chosen, the dictionary is kept in its dictionary.json and saved on "
                 + "every change — pick one in iCloud Drive to back it up or share it between Macs. "
                 + "Import takes an exported dictionary or a text file with one word per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where to keep dictionary.json. A dictionary already there is merged in."
        panel.directoryURL = settings.dictionaryFolder ?? Self.iCloudDriveURL
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        editor.replaceAll(settings.useDictionaryFolder(folder))
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let contents = try DictionaryFile.parseImport(String(contentsOf: url, encoding: .utf8))
            let result = editor.import(contents)
            var message = "Added \(Self.words(result.added))"
            if result.skipped > 0 {
                message += ", skipped \(result.skipped) already in the dictionary"
            }
            if result.added > 0, case .words = contents, editor.canGenerate {
                message += ". Filling in details one word at a time…"
            } else {
                message += "."
            }
            transferMessage = message
        } catch {
            transferMessage = "Couldn't import \(url.lastPathComponent): \(error)"
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = DictionaryFile.fileName
        panel.directoryURL = settings.dictionaryFolder ?? Self.iCloudDriveURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DictionaryFile.save(editor.entries, to: url)
            transferMessage = "Exported \(Self.words(editor.entries.count)) to \(url.lastPathComponent)."
        } catch {
            transferMessage = "Couldn't export: \(error.localizedDescription)"
        }
    }

    private static func words(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    private static var iCloudDriveURL: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func row(_ item: DictionaryEditor.Item) -> some View {
        HStack {
            Button {
                selection = item.id
            } label: {
                HStack {
                    Text(item.entry.written)
                    Text(item.entry.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusBadge(status: item.status)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editor.remove(item.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove “\(item.entry.written)”")
        }
    }

    private func addWord() {
        guard editor.add(newWord) != nil else { return }
        newWord = ""
    }
}

// MARK: - Entry details

/// Full-page editor for one entry, replacing the list until the user goes back (the back
/// button or Esc). Text fields keep their own drafts so typing (e.g. a trailing comma in
/// "Heard as") isn't reformatted mid-edit; every change is saved at once.
@available(macOS 26.0, *)
private struct EntryDetailView: View {
    let editor: DictionaryEditor
    let transcriber: TranscriptionRouter
    let id: UUID
    let onBack: () -> Void

    @State private var written = ""
    @State private var soundsLike = ""
    @State private var context = ""
    @State private var writtenIsInvalid = false
    @State private var isRecordingPronunciation = false

    var body: some View {
        if let item = editor.item(id) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    Label("Dictionary", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("[", modifiers: .command)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Text(item.entry.written)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                form(for: item)
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onExitCommand(perform: onBack)
            .onAppear { loadDrafts(from: item.entry) }
            .sheet(isPresented: $isRecordingPronunciation, onDismiss: {
                if let entry = editor.item(id)?.entry { loadDrafts(from: entry) }
            }) {
                PronunciationRecorderView(editor: editor, id: id, transcriber: transcriber)
            }
            .onChange(of: item.status) { old, new in
                // A suggestion just landed: show it in the text fields.
                if old == .generating, new == .ready, let entry = editor.item(id)?.entry {
                    loadDrafts(from: entry)
                }
            }
        }
    }

    private func form(for item: DictionaryEditor.Item) -> some View {
        Form {
            Section {
                TextField("Written", text: $written)
                    .onChange(of: written) { _, value in
                        writtenIsInvalid = !update { $0.written = value }
                    }
                if writtenIsInvalid {
                    Text("Must be non-empty and not already in the dictionary.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Type", selection: field(\.type, of: item)) {
                    ForEach(DictionaryEntry.EntryType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            Section {
                TextField("Heard as", text: $soundsLike, prompt: Text("e.g. hotel, oh tel"))
                    .onChange(of: soundsLike) { _, value in
                        update { $0.soundsLike = DictionaryEntry.parseList(value) }
                    }
                Button("Record Pronunciation…", systemImage: "mic") { isRecordingPronunciation = true }
                    .disabled(!transcriber.isReady)
            } footer: {
                Text("What transcription writes instead of this term, comma-separated. Check the "
                     + "Transcriptions tab for what it actually produced, or record yourself saying "
                     + "the term to add what transcription hears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Context", text: $context, prompt: Text("appears next to words like …"), axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: context) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        update { $0.context = trimmed.isEmpty ? nil : trimmed }
                    }
            } footer: {
                Text("Helps tell the term apart from ordinary words. Avoid repeating the term or its "
                     + "expansion here — the model may copy it into your text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.entry.type == .identifier || item.entry.type == .verb {
                Section {
                    if item.entry.type == .identifier {
                        Toggle("Format as code (backticks)", isOn: field(\.formatAsCode, of: item))
                    }
                    if item.entry.type == .verb {
                        Toggle("Inflect (dedupe → deduped)", isOn: field(\.inflect, of: item))
                    }
                }
            }

            Section {
                HStack {
                    StatusBadge(status: item.status, showsLabel: true)
                    Spacer()
                    if editor.canGenerate {
                        Button("Regenerate Details") { editor.regenerate(id) }
                            .disabled(item.status == .generating)
                    }
                    Button("Remove Word", role: .destructive) {
                        onBack()
                        editor.remove(id)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func loadDrafts(from entry: DictionaryEntry) {
        written = entry.written
        soundsLike = DictionaryEntry.formatList(entry.soundsLike)
        context = entry.context ?? ""
        writtenIsInvalid = false
    }

    /// Applies `change` to the current entry. Returns false if the editor rejected it.
    @discardableResult
    private func update(_ change: (inout DictionaryEntry) -> Void) -> Bool {
        guard var entry = editor.item(id)?.entry else { return false }
        let original = entry
        change(&entry)
        guard entry != original else { return true }
        return editor.update(id, to: entry)
    }

    private func field<T>(_ keyPath: WritableKeyPath<DictionaryEntry, T>, of item: DictionaryEditor.Item) -> Binding<T> {
        Binding(
            get: { editor.item(id)?.entry[keyPath: keyPath] ?? item.entry[keyPath: keyPath] },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }
}

// MARK: - Shared pieces

@available(macOS 26.0, *)
private struct StatusBadge: View {
    let status: DictionaryEditor.Status
    var showsLabel = false

    var body: some View {
        switch status {
        case .ready:
            EmptyView()
        case .generating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if showsLabel {
                    Text("Filling in details…").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .generationFailed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                if showsLabel {
                    Text("Couldn't fill in details — edit them here")
                }
            }
            .foregroundStyle(.orange)
            .font(.caption)
            .help("Apple Intelligence couldn't fill in this word's details")
        }
    }
}

extension DictionaryEntry.EntryType {
    var displayName: String {
        switch self {
        case .noun:       return "Noun"
        case .properNoun: return "Proper noun"
        case .verb:       return "Verb"
        case .adjective:  return "Adjective"
        case .identifier: return "Code identifier"
        case .acronym:    return "Acronym"
        }
    }
}
