import SwiftUI
import TalkToMyMacCore

/// Settings tab for the custom dictionary: terms the speech model tends to mis-hear, passed
/// to the LLM formatting step so it can correct them. Adding a word asks Apple Intelligence
/// to fill in its details; clicking a word shows them for review and editing.
@available(macOS 26.0, *)
struct DictionaryView: View {
    let editor: DictionaryEditor
    @Bindable var settings: FormattingSettings
    @State private var newWord = ""
    @State private var selection: UUID?

    var body: some View {
        if let selection, editor.item(selection) != nil {
            EntryDetailView(editor: editor, id: selection) { self.selection = nil }
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

            Section("Words") {
                if editor.items.isEmpty {
                    Text("No words yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(editor.items) { item in
                        row(item)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 440)
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
    let id: UUID
    let onBack: () -> Void

    @State private var written = ""
    @State private var soundsLike = ""
    @State private var context = ""
    @State private var writtenIsInvalid = false

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
            } footer: {
                Text("What transcription writes instead of this term, comma-separated. Check the "
                     + "Transcriptions tab for what it actually produced.")
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
