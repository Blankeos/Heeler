import Foundation
import Observation

/// Local draft operations shared by the plain-text Composer now and future
/// Snippet, Skill, and Staged Image path insertion surfaces.
@MainActor
protocol ComposerDraftOperations: AnyObject {
    func replaceDraft(with text: String)
    func insertIntoDraft(_ text: String)
}

/// Owns Agent detail's local draft and delivery state. Draft edits do not
/// touch Transport. Send delivers through one `agent.prompt` RPC, except
/// when Agent Status is Blocked: then it inserts into the live Attach PTY
/// without Enter.
@MainActor
@Observable
final class AgentComposerStore: ComposerDraftOperations {
    struct Message: Identifiable, Equatable {
        let id: UUID
        let text: String
        fileprivate var agentWasWorkingAtSend: Bool
        fileprivate var statusRevisionAtSend: UInt64
        fileprivate var observedWorkingAfterSend: Bool
        /// Attach-inserted Blocked drafts are acked by the PTY write. They
        /// do not claim Working/Done from later status pushes.
        fileprivate var tracksAgentProgress: Bool
        fileprivate(set) var state: DeliveryState
    }

    enum DeliveryState: Equatable {
        case sending
        case delivered(AgentProgress)
        case failed(String)
    }

    enum AgentProgress: Equatable {
        case acknowledged
        case agentBusy
        case working
        case done
    }

    /// How Send finished. `.deliveredViaAttach` is the view's cue to present
    /// the tools keyboard so the user can Enter or Esc themselves.
    enum SendResult: Equatable {
        case ignored
        case deliveredViaPrompt
        case deliveredViaAttach
        case failed
    }

    private(set) var messages: [Message] = []
    private(set) var draft = ""
    /// UTF-16 caret/selection, matching the Composer text view.
    private(set) var draftSelection = NSRange(location: 0, length: 0)

    private let target: String
    private var agentStatus: AgentStatus
    private var statusRevision: UInt64 = 0
    private let statusUpdates: AsyncStream<ConsoleStore.AgentStatusUpdate>?
    private let prompt: @Sendable (AgentPromptParams) async throws -> Agent
    @ObservationIgnored private var hasOpened = false
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    /// The detail screen's live Attach writer. Weak: Composer outlives any
    /// one Attach pipeline (reconnect replacement), and a dead writer must
    /// fail the Blocked path rather than retain a stale session.
    @ObservationIgnored private weak var attachInput: TerminalInputController?
    /// ADR 0006 picker path. Weak through the bind so staging can keep the
    /// Composer as its draft owner without a retain cycle.
    @ObservationIgnored private weak var staging: ComposerStagingStore?
    /// Dropped images waiting for `ComposerStagingStore.begin(_:)`. Locations
    /// are UTF-16 slots: later text in the same drop lands after the slot, and
    /// the Host path replaces that slot rather than the live caret.
    @ObservationIgnored private var pendingDroppedImages: [PendingDroppedImage] = []
    /// Accept-loop inserts are never the async staging path.
    @ObservationIgnored private var isApplyingDrop = false

    private struct PendingDroppedImage {
        enum Status {
            case queued
            case staging
        }

        let data: Data
        var utf16Location: Int
        var status: Status
    }

    init(
        target: String,
        initialStatus: AgentStatus = .idle,
        statusUpdates: AsyncStream<ConsoleStore.AgentStatusUpdate>? = nil,
        prompt: @escaping @Sendable (AgentPromptParams) async throws -> Agent
    ) {
        self.target = target
        agentStatus = initialStatus
        self.statusUpdates = statusUpdates
        self.prompt = prompt
    }

    deinit {
        statusTask?.cancel()
    }

    var canSend: Bool {
        draft.contains(where: { !$0.isWhitespace })
    }

    func replaceDraft(with text: String) {
        remapDroppedImageSlots(from: draft, to: text)
        draft = text
        draftSelection = NSRange(location: (text as NSString).length, length: 0)
        clampDroppedImageSlots()
    }

    /// Inserts at the current caret, or replaces the current selection. This
    /// is the Snippet / Skill / staged-path insertion path: the draft changes
    /// and nothing is submitted. A Host path from an in-flight drop fills that
    /// drop's reserved slot instead of the live caret.
    func insertIntoDraft(_ text: String) {
        if !isApplyingDrop, fulfillDroppedImagePathIfNeeded(text) {
            // `ComposerStagingStore.finishSuccess` still has `isBusy` until
            // after this insert returns; start the next drop on the next turn.
            scheduleStartNextDroppedImage()
            return
        }
        let range = Self.clamped(draftSelection, to: draft)
        remapDroppedImageSlots(replacing: range, with: (text as NSString).length)
        draft = (draft as NSString).replacingCharacters(in: range, with: text)
        draftSelection = NSRange(
            location: range.location + (text as NSString).length,
            length: 0)
        clampDroppedImageSlots()
        scheduleStartNextDroppedImage()
    }

    func setDraftSelection(_ range: NSRange) {
        let clamped = Self.clamped(range, to: draft)
        guard draftSelection != clamped else { return }
        draftSelection = clamped
    }

    /// Typing and selection changes from the Composer text view. Unlike
    /// ``replaceDraft(with:)``, this keeps the view's caret.
    func applyEditorDraft(_ text: String, selection: NSRange) {
        let clamped = Self.clamped(selection, to: text)
        guard draft != text || draftSelection != clamped else { return }
        remapDroppedImageSlots(from: draft, to: text)
        draft = text
        draftSelection = clamped
        clampDroppedImageSlots()
    }

    /// Forwards dropped images onto ``ComposerStagingStore.begin(_:)``, the
    /// same call the photo picker uses. One operation at a time; extras queue.
    func bindStaging(_ staging: ComposerStagingStore) {
        self.staging = staging
        startNextDroppedImageIfNeeded()
    }

    /// Maps a drop onto draft insertion and/or the ADR 0006 staging path.
    /// Empty and unsupported items are skipped without touching the draft or
    /// submitting it. Mixed payloads keep their insertion order: each image
    /// reserves a slot, later text lands after that slot, and the Host path
    /// fills the slot when staging completes.
    func acceptDrop(_ items: [ComposerDropItem]) {
        isApplyingDrop = true
        for item in items {
            switch item {
            case .text(let text):
                guard !text.isEmpty else { continue }
                insertIntoDraft(text)
            case .image(let data, _):
                guard !data.isEmpty else { continue }
                reserveDroppedImage(data)
            case .unsupported:
                continue
            }
        }
        isApplyingDrop = false
        startNextDroppedImageIfNeeded()
    }

    /// Completes an inline Skill suggestion: swaps the typed trigger token at
    /// the end of the draft for the full invocation. A draft that no longer
    /// ends with the token — edited under a stale suggestion — is left alone
    /// rather than mangled.
    func replaceTrailingToken(_ token: String, with text: String) {
        guard !token.isEmpty, draft.hasSuffix(token) else { return }
        let previous = draft
        draft.removeLast(token.count)
        draft.append(text)
        remapDroppedImageSlots(from: previous, to: draft)
        draftSelection = NSRange(location: (draft as NSString).length, length: 0)
        clampDroppedImageSlots()
    }

    /// Starts consuming Console's existing per-Agent status fan-out. This
    /// does not open a Transport event stream or perform an RPC.
    func open() {
        guard !hasOpened else { return }
        hasOpened = true
        guard let statusUpdates else { return }
        statusTask = Task { [weak self] in
            for await update in statusUpdates {
                guard !Task.isCancelled, let self else { return }
                if let status = update.status {
                    self.agentStatusDidChange(status)
                }
            }
        }
    }

    /// The already-open Attach PTY writer owned by Agent detail. Blocked
    /// Send uses the same pipe as the tools keyboard.
    func bindAttachInput(_ input: TerminalInputController?) {
        attachInput = input
    }

    @discardableResult
    func send() async -> SendResult {
        guard canSend else { return .ignored }
        let message = Message(
            id: UUID(), text: draft,
            agentWasWorkingAtSend: agentStatus == .working,
            statusRevisionAtSend: statusRevision,
            observedWorkingAfterSend: false,
            tracksAgentProgress: true,
            state: .sending)
        remapDroppedImageSlots(from: draft, to: "")
        draft = ""
        draftSelection = NSRange(location: 0, length: 0)
        clampDroppedImageSlots()
        messages.append(message)
        return await deliver(message.id)
    }

    @discardableResult
    func retry(_ id: Message.ID) async -> SendResult {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return .ignored }
        guard case .failed = messages[index].state else { return .ignored }
        messages[index].agentWasWorkingAtSend = agentStatus == .working
        messages[index].statusRevisionAtSend = statusRevision
        messages[index].observedWorkingAfterSend = false
        messages[index].tracksAgentProgress = true
        messages[index].state = .sending
        return await deliver(id)
    }

    /// Removes a failed echo and restores all of its text to the draft. If
    /// the user has already started another draft, both are kept in order.
    func withdrawToDraft(_ id: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard case .failed = messages[index].state else { return }
        let text = messages.remove(at: index).text
        let next = draft.isEmpty ? text : "\(text)\n\(draft)"
        remapDroppedImageSlots(from: draft, to: next)
        draft = next
        clampDroppedImageSlots()
    }

    func agentStatusDidChange(_ status: AgentStatus) {
        guard agentStatus != status else { return }
        agentStatus = status
        statusRevision &+= 1
        for index in messages.indices {
            guard messages[index].tracksAgentProgress else { continue }
            if status == .working,
                messages[index].statusRevisionAtSend != statusRevision
            {
                messages[index].observedWorkingAfterSend = true
            }
            guard case .delivered(let progress) = messages[index].state else { continue }
            switch status {
            case .working
                where progress != .done && messages[index].observedWorkingAfterSend:
                messages[index].state = .delivered(.working)
            case .done
                where messages[index].observedWorkingAfterSend
                    || !messages[index].agentWasWorkingAtSend:
                messages[index].state = .delivered(.done)
            case .idle where messages[index].observedWorkingAfterSend:
                messages[index].state = .delivered(.done)
            default:
                break
            }
        }
    }

    private func deliver(_ id: Message.ID) async -> SendResult {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return .ignored }
        let text = messages[index].text
        if agentStatus == .blocked {
            return deliverThroughAttach(id, text: text)
        }
        let input = attachInput
        let generation = input?.liveGeneration
        do {
            _ = try await prompt(AgentPromptParams(target: target, text: text))
            guard let acknowledgedIndex = messages.firstIndex(where: { $0.id == id }) else {
                return .ignored
            }
            messages[acknowledgedIndex].state = .delivered(
                progressAfterAcknowledgment(for: messages[acknowledgedIndex]))
            if let input, let generation {
                input.recordSubmitted(text, generation: generation)
            }
            return .deliveredViaPrompt
        } catch {
            if Self.isAgentBlocked(error) {
                return deliverThroughAttach(id, text: text)
            }
            return fail(id, message: Self.message(for: error))
        }
    }

    /// Types the draft into the live Attach PTY without submitting. Matches
    /// tools-keyboard writes: UTF-8 bytes, no bracketed paste, no Enter.
    /// Those bytes already cross `TerminalInputController`'s writer, which
    /// indexes them; do not also `record(submitted:)` here.
    private func deliverThroughAttach(_ id: Message.ID, text: String) -> SendResult {
        guard TerminalTextSafety.containsOnlySafeScalars(text) else {
            return fail(id, message: Self.unsafeTextMessage)
        }
        guard let attachInput, attachInput.insertComposerDraft(text) else {
            return fail(id, message: Self.missingAttachMessage)
        }
        guard let deliveredIndex = messages.firstIndex(where: { $0.id == id }) else {
            return .ignored
        }
        messages[deliveredIndex].tracksAgentProgress = false
        messages[deliveredIndex].state = .delivered(.acknowledged)
        return .deliveredViaAttach
    }

    @discardableResult
    private func fail(_ id: Message.ID, message: String) -> SendResult {
        guard let failedIndex = messages.firstIndex(where: { $0.id == id }) else {
            return .ignored
        }
        messages[failedIndex].state = .failed(message)
        return .failed
    }

    private static func isAgentBlocked(_ error: any Error) -> Bool {
        if let apiError = error as? HerdrAPIError {
            return apiError.code == "agent_blocked"
        }
        if let transportError = error as? TransportError,
            case .apiRejected(let code, _) = transportError
        {
            return code == "agent_blocked"
        }
        return false
    }

    private func progressAfterAcknowledgment(for message: Message) -> AgentProgress {
        if message.observedWorkingAfterSend {
            switch agentStatus {
            case .working:
                return .working
            case .done, .idle:
                return .done
            default:
                break
            }
        } else if !message.agentWasWorkingAtSend,
            message.statusRevisionAtSend != statusRevision,
            agentStatus == .done
        {
            // The status stream keeps only the newest event. A fast
            // working-to-done pair can therefore arrive as Done alone.
            return .done
        }
        return message.agentWasWorkingAtSend ? .agentBusy : .acknowledged
    }

    private static let missingAttachMessage =
        "The message could not be sent. Check the connection and retry."
    private static let unsafeTextMessage =
        "The message contains unsafe terminal control characters."

    private func reserveDroppedImage(_ data: Data) {
        let range = Self.clamped(draftSelection, to: draft)
        if range.length > 0 {
            remapDroppedImageSlots(replacing: range, with: 0)
            draft = (draft as NSString).replacingCharacters(in: range, with: "")
            draftSelection = NSRange(location: range.location, length: 0)
        }
        pendingDroppedImages.append(
            PendingDroppedImage(
                data: data,
                utf16Location: draftSelection.location,
                status: .queued))
    }

    @discardableResult
    private func fulfillDroppedImagePathIfNeeded(_ text: String) -> Bool {
        guard Self.isStagedPathInsertion(text),
            let index = pendingDroppedImages.firstIndex(where: { $0.status == .staging })
        else { return false }
        let location = min(
            max(pendingDroppedImages[index].utf16Location, 0),
            (draft as NSString).length)
        pendingDroppedImages.remove(at: index)
        let inserted = (text as NSString).length
        draft = (draft as NSString).replacingCharacters(
            in: NSRange(location: location, length: 0), with: text)
        for pendingIndex in pendingDroppedImages.indices
        where pendingDroppedImages[pendingIndex].utf16Location >= location {
            pendingDroppedImages[pendingIndex].utf16Location += inserted
        }
        if draftSelection.location >= location {
            draftSelection = NSRange(
                location: draftSelection.location + inserted,
                length: draftSelection.length)
        }
        clampDroppedImageSlots()
        return true
    }

    private func scheduleStartNextDroppedImage() {
        Task { [weak self] in
            self?.startNextDroppedImageIfNeeded()
        }
    }

    private func startNextDroppedImageIfNeeded() {
        guard let staging else { return }
        if let index = pendingDroppedImages.firstIndex(where: { $0.status == .staging }) {
            guard !staging.state.isBusy else { return }
            switch staging.state {
            case .failed, .backgroundInterrupted:
                return
            case .idle, .completed:
                pendingDroppedImages[index].status = .queued
            case .preparing, .uploading:
                return
            }
        }
        guard staging.canBegin,
            !pendingDroppedImages.contains(where: { $0.status == .staging }),
            let index = pendingDroppedImages.firstIndex(where: { $0.status == .queued })
        else { return }
        pendingDroppedImages[index].status = .staging
        staging.begin(.photo(DataImageSelection(data: pendingDroppedImages[index].data)))
    }

    private func remapDroppedImageSlots(from old: String, to new: String) {
        let edit = Self.utf16Edit(from: old, to: new)
        remapDroppedImageSlots(replacing: edit.range, with: edit.replacementLength)
    }

    private func remapDroppedImageSlots(replacing range: NSRange, with replacementLength: Int) {
        let delta = replacementLength - range.length
        for index in pendingDroppedImages.indices {
            let location = pendingDroppedImages[index].utf16Location
            if range.length == 0, location == range.location {
                continue
            }
            if location >= range.location + range.length {
                pendingDroppedImages[index].utf16Location = location + delta
            } else if location > range.location {
                pendingDroppedImages[index].utf16Location = range.location
            }
        }
    }

    private func clampDroppedImageSlots() {
        let length = (draft as NSString).length
        for index in pendingDroppedImages.indices {
            pendingDroppedImages[index].utf16Location = min(
                max(pendingDroppedImages[index].utf16Location, 0),
                length)
        }
    }

    private static func isStagedPathInsertion(_ text: String) -> Bool {
        guard text.hasSuffix(" "), text.hasPrefix("/") else { return false }
        let path = String(text.dropLast())
        return !path.isEmpty && !path.contains(where: { $0.isNewline })
    }

    private static func utf16Edit(
        from old: String,
        to new: String
    ) -> (range: NSRange, replacementLength: Int) {
        let oldNS = old as NSString
        let newNS = new as NSString
        let oldLength = oldNS.length
        let newLength = newNS.length
        var prefix = 0
        while prefix < oldLength, prefix < newLength,
            oldNS.character(at: prefix) == newNS.character(at: prefix)
        {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLength - prefix, suffix < newLength - prefix,
            oldNS.character(at: oldLength - 1 - suffix)
                == newNS.character(at: newLength - 1 - suffix)
        {
            suffix += 1
        }
        return (
            NSRange(location: prefix, length: oldLength - prefix - suffix),
            newLength - prefix - suffix)
    }

    private static func clamped(_ range: NSRange, to text: String) -> NSRange {
        let length = (text as NSString).length
        guard range.location != NSNotFound else {
            return NSRange(location: length, length: 0)
        }
        let location = min(max(range.location, 0), length)
        let remaining = length - location
        let clampedLength = min(max(range.length, 0), remaining)
        return NSRange(location: location, length: clampedLength)
    }

    static func message(for error: any Error) -> String {
        switch error {
        case TransportError.sshUnreachable:
            "The Host is not connected. Check the connection and retry."
        case TransportError.timedOut:
            "The Host did not answer. Check the connection and retry."
        case let error as HerdrAPIError:
            "herdr rejected the message: \(error.message)"
        case let error as TransportError:
            error.presentation.message
        default:
            missingAttachMessage
        }
    }
}
