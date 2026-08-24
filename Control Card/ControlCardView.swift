import SwiftUI
import CoreData
import AVFoundation
import CoreNFC

// Enum for managing alerts.
enum ControlCardAlert: Identifiable {
    case submission(String)
    case confirmation

    var id: Int {
        switch self {
        case .submission(_):
            return 0
        case .confirmation:
            return 1
        }
    }
}

// The shape of the paper controlekaart, and of what the points system reads back
// from it: 30 numbered ORC rows of up to 4 columns. The server splits a
// submission on exactly these counts, so they are the one place the card's size
// is written down.
enum ControlCardLayout {
    static let orcRows = 30
    static let orcColumns = 4
}

// Model for each row of the control card.
struct ControlCardRow: Identifiable {
    let id: Int
    var col1: String = ""
    var col2: String = ""
    var col3: String = ""
    var col4: String = ""
    
    // Mark columns that were filled via QR and must not be edited
    var col1Locked: Bool = false
    var col2Locked: Bool = false
    var col3Locked: Bool = false
    var col4Locked: Bool = false
    
    var rowLocked: Bool = false

    /// The number of letter cells this row shows.
    var columnCount: Int { ControlCardLayout.orcColumns }

    func value(_ column: Int) -> String {
        switch column {
        case 1: return col1
        case 2: return col2
        case 3: return col3
        default: return col4
        }
    }

    mutating func setValue(_ value: String, column: Int) {
        switch column {
        case 1: col1 = value
        case 2: col2 = value
        case 3: col3 = value
        default: col4 = value
        }
    }

    func isLocked(_ column: Int) -> Bool {
        switch column {
        case 1: return col1Locked
        case 2: return col2Locked
        case 3: return col3Locked
        default: return col4Locked
        }
    }

    mutating func lock(_ column: Int) {
        switch column {
        case 1: col1Locked = true
        case 2: col2Locked = true
        case 3: col3Locked = true
        default: col4Locked = true
        }
    }
}

// Enum to represent each focusable field.
enum Field: Hashable {
    case field(row: Int, col: Int)
}

/// The two halves of the card: what the points system knows about this crew,
/// and the letters they type in.
enum ControlCardTab: Hashable {
    case rally
    case card
}

// Letters the user is not allowed to type (case-insensitive).
private let disallowedLetters: Set<Character> = ["C", "E", "F", "G", "H", "T", "V", "X", "Y"]

/// Strips any disallowed characters and returns at most 1 character.
private func sanitized(_ value: String) -> String {
    let filtered = value.uppercased().filter { !disallowedLetters.contains($0) }
    return String(filtered.prefix(1))
}

// MARK: - NFC Reader

/// Reads the first Well-Known Text record from an NDEF tag and returns its string value.
class NFCReader: NSObject, NFCNDEFReaderSessionDelegate, ObservableObject {
    var session: NFCNDEFReaderSession?
    var onResult: ((Result<String, Error>) -> Void)?

    enum NFCError: LocalizedError {
        case noRecords
        case notAvailable

        var errorDescription: String? {
            switch self {
            case .noRecords:    return "No readable text record found on the NFC tag."
            case .notAvailable: return "NFC is not available on this device."
            }
        }
    }

    func start(onResult: @escaping (Result<String, Error>) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            onResult(.failure(NFCError.notAvailable))
            return
        }
        self.onResult = onResult
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your iPhone near the NFC tag."
        session?.begin()
    }

    // MARK: NFCNDEFReaderSessionDelegate

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Code 200 = "first tag read, session auto-closed" — that's success, not an error.
        let nsErr = error as NSError
        if nsErr.code != 200 {
            DispatchQueue.main.async {
                self.onResult?(.failure(error))
                self.onResult = nil
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                // wellKnownTypeTextPayload decodes NDEF Well-Known Type "T" (text) records,
                // which is exactly what NFC Tools writes for a "Text" record.
                if let text = record.wellKnownTypeTextPayload().0 {
                    DispatchQueue.main.async {
                        self.onResult?(.success(text))
                        self.onResult = nil
                    }
                    return
                }
            }
        }
        DispatchQueue.main.async {
            self.onResult?(.failure(NFCError.noRecords))
            self.onResult = nil
        }
    }
}

// MARK: - ControlCardView

struct ControlCardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) var scenePhase

    @ObservedObject var rally: Rally
    @State private var rows: [ControlCardRow] = (1...ControlCardLayout.orcRows).map { ControlCardRow(id: $0) }
    
    @State private var activeAlert: ControlCardAlert? = nil
    @FocusState private var focusedField: Field?
    @State private var isShowingScanner = false
    @State private var selectedTab: ControlCardTab = .card

    /// Keep the NFCReader alive for the lifetime of the view.
    @StateObject private var nfcReader = NFCReader()

    /// Room under the scrolling content so the floating tab bar never covers
    /// the last row or the finalize button.
    private let tabBarClearance: CGFloat = 84

    var body: some View {
        ZStack(alignment: .bottom) {
            GlassBackdrop()

            TabView(selection: $selectedTab) {
                rallyTab.tag(ControlCardTab.rally)
                cardTab.tag(ControlCardTab.card)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            GlassTabBar<ControlCardTab>(
                items: [
                    .init(selection: .rally, title: "Rally", systemImage: "flag.checkered"),
                    .init(selection: .card, title: "Control Card", systemImage: "tablecells")
                ],
                selection: $selectedTab
            )
            .padding(.bottom, 8)
        }
        .navigationTitle("Control Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !rally.isFinalized {
                    HStack(spacing: 16) {
                        Button {
                            startNFCScan()
                        } label: {
                            Image(systemName: "wave.3.right")
                        }
                        .accessibilityLabel("Scan NFC Tag")

                        Button {
                            isShowingScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                        .accessibilityLabel("Scan QR Code")
                    }
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear(perform: loadControlCardData)
        .onDisappear(perform: saveControlCardData)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                saveControlCardData()
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmation:
                return Alert(
                    title: Text("Warning"),
                    message: Text("After finalizing, you won't be able to edit any more values. Do you want to proceed?"),
                    primaryButton: .destructive(Text("Accept")) {
                        finalizeControlCard()
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            case .submission(let message):
                return Alert(
                    title: Text("Submission Status"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            QRCodeScannerView { result in
                isShowingScanner = false
                switch result {
                case .success(let code):
                    handleScanned(code: code)
                case .failure(let error):
                    activeAlert = .submission("Scanning failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Tabs

    /// What the points system knows about this card and its crew.
    private var rallyTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    infoRow("Rally", (rally.rallyName ?? rally.rallyCode ?? "").uppercased(), isFirst: true)
                    infoRow("Rally code", (rally.rallyCode ?? "").uppercased())
                    if let cardName = rally.cardName, !cardName.isEmpty {
                        infoRow("Kaart", cardName)
                    }
                    infoRow("Kaart nummer", "\(rally.cardNumber)")
                    infoRow("EQ nummer", "\(rally.eqNumber)")
                    if let crewName = rally.crewName, !crewName.isEmpty {
                        infoRow("Equipe", crewName)
                    }
                }
                .glassCard()

                statusCard

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Glass.padding)
            .padding(.top, Glass.padding)
            .padding(.bottom, tabBarClearance)
        }
    }

    /// The 30 ORC rows and the button that hands them in.
    private var cardTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    orcHeaderView
                        .padding(.bottom, 8)

                    ForEach(rows.indices, id: \.self) { index in
                        rowView(at: index)
                    }
                }
                .glassCard()

                if !rally.isFinalized {
                    scanCard
                }

                finalizeCard
            }
            .padding(.horizontal, Glass.padding)
            .padding(.top, Glass.padding)
            .padding(.bottom, tabBarClearance)
        }
    }

    // MARK: - Cards

    /// One line of the rally card. The rule sits above the line rather than
    /// below it, so the last line never trails off into a divider whichever of
    /// the optional lines the points system gave us.
    private func infoRow(_ label: String, _ value: String, isFirst: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !isFirst {
                Divider().opacity(0.4)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.headline)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: rally.isFinalized ? "checkmark.seal.fill" : "square.and.pencil")
                .font(.title2)
                .foregroundColor(rally.isFinalized ? .green : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(rally.isFinalized ? "Finalized" : "Open")
                    .font(.headline)
                Text(rally.isFinalized
                     ? "This card has been handed in and can no longer be edited."
                     : "Fill in the control card, then finalize it from the Control Card tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .glassCard()
    }

    private var scanCard: some View {
        HStack(spacing: 12) {
            Button {
                isShowingScanner = true
            } label: {
                Label("Scan QR", systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Glass.innerCornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)

            Button {
                startNFCScan()
            } label: {
                Label("Scan NFC", systemImage: "wave.3.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Glass.innerCornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
        }
        .glassCard(padding: 12)
    }

    @ViewBuilder
    private var finalizeCard: some View {
        if rally.isFinalized {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                Text("Card handed in")
                    .font(.headline)
            }
            .foregroundColor(.green)
            .frame(maxWidth: .infinity)
            .glassCard()
        } else {
            Button {
                activeAlert = .confirmation
            } label: {
                Label("Finalize Card", systemImage: "paperplane.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Glass.cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 14, x: 0, y: 8)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - NFC

    private func startNFCScan() {
        nfcReader.start { result in
            switch result {
            case .success(let payload):
                // NFC Tools "Text" record gives us the raw string, e.g. "T:11".
                // Route it through the same shared handler as QR codes.
                handleScanned(code: payload)
            case .failure(let error):
                activeAlert = .submission("NFC scan failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - The grid

    private var orcHeaderView: some View {
        HStack(spacing: 8) {
            Text("ORC")
                .frame(width: 30, alignment: .leading)
            ForEach(1...ControlCardLayout.orcColumns, id: \.self) { column in
                Text("Col\(column)")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
    }

    private func rowView(at index: Int) -> some View {
        let row = rows[index]
        return HStack(spacing: 8) {
            Text("\(row.id)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .center)

            ForEach(1...row.columnCount, id: \.self) { column in
                cellView(at: index, column: column)
            }
        }
        .padding(.vertical, 3)
        .opacity(row.rowLocked ? 0.5 : 1.0)
    }

    private func cellView(at index: Int, column: Int) -> some View {
        let row = rows[index]
        let locked = row.rowLocked || row.isLocked(column)
        let text = Binding(
            get: { self.rows[index].value(column) },
            set: { newValue in
                var updated = self.rows[index]
                guard !updated.rowLocked, !updated.isLocked(column) else { return }

                let clean = sanitized(newValue)
                if updated.value(column) != clean {
                    updated.setValue(clean, column: column)
                    self.rows[index] = updated
                }
                // A cell that is full hands the keyboard on, whether or not the
                // keystroke changed the letter that was already there.
                if clean.count == 1 { self.advanceFocus(from: index, column: column) }
            }
        )

        return TextField("", text: text)
            .focused($focusedField, equals: .field(row: row.id, col: column))
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: Glass.innerCornerRadius, style: .continuous)
                    .fill(locked ? Color.primary.opacity(0.10) : Color.white.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: Glass.innerCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    )
            )
            .disabled(rally.isFinalized || locked)
    }

    /// A filled cell hands the keyboard to the next one: the next column of the
    /// row, or the first column of the row below when the row is full.
    private func advanceFocus(from index: Int, column: Int) {
        if column < rows[index].columnCount {
            focusedField = .field(row: rows[index].id, col: column + 1)
        } else if index + 1 < rows.count {
            focusedField = .field(row: rows[index + 1].id, col: 1)
        } else {
            focusedField = nil
        }
    }
    
    // MARK: - Shared scan handler

    private func handleScanned(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        
        print("🔍 handleScanned: raw='\(code)' trimmed='\(trimmed)'")
        
        if upper.hasPrefix("LOCK:") {
            handleLockRows(from: trimmed)
        } else {
            handleSingleCellScan(from: trimmed)
        }
    }
    
    /// Handles both QR style ("11:T" — row first) and NFC style ("T:11" — letter first).
    private func handleSingleCellScan(from code: String) {
        let parts = code.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count == 2 else {
            activeAlert = .submission("Unexpected format: \(code). Expected e.g. 15:G or T:11")
            return
        }

        let rowNumber: Int?
        let letter: Character?

        if let r = Int(parts[0]), let l = parts[1].uppercased().first, l.isLetter {
            // QR style: "11:T"
            rowNumber = r
            letter = l
        } else if let l = parts[0].uppercased().first, l.isLetter, let r = Int(parts[1]) {
            // NFC style: "T:11"
            rowNumber = r
            letter = l
        } else {
            activeAlert = .submission("Unexpected format: \(code). Expected e.g. 15:G or T:11")
            return
        }

        guard let row = rowNumber, let char = letter else { return }

        guard let index = rows.firstIndex(where: { $0.id == row }) else {
            activeAlert = .submission("Row \(row) is not in this control card.")
            return
        }

        var rowData = rows[index]
        let value = String(char)

        if rowData.rowLocked {
            activeAlert = .submission("Row \(row) is locked and cannot be changed.")
            return
        }

        // Fill the first free column this row has.
        guard let column = (1...rowData.columnCount).first(where: {
            rowData.value($0).isEmpty && !rowData.isLocked($0)
        }) else {
            activeAlert = .submission(
                "Row \(row) already has all \(rowData.columnCount) column(s) filled."
            )
            return
        }

        rowData.setValue(value, column: column)
        rowData.lock(column)

        rows[index] = rowData
        saveControlCardData()
    }

    private func handleLockRows(from code: String) {
        let parts = code.split(separator: ":")
        guard parts.count == 2 else {
            activeAlert = .submission("Unexpected LOCK format: \(code). Expected e.g. LOCK:1-2-3")
            return
        }

        let tokens = parts[1].split(separator: "-")
        var lockedAny = false

        for token in tokens {
            let trimmedToken = token.trimmingCharacters(in: .whitespaces)
            guard let rowNumber = Int(trimmedToken),
                  let index = rows.firstIndex(where: { $0.id == rowNumber }) else { continue }

            var row = rows[index]
            row.rowLocked = true
            for column in 1...ControlCardLayout.orcColumns { row.lock(column) }
            rows[index] = row
            lockedAny = true
        }

        if lockedAny {
            saveControlCardData()
            activeAlert = .submission("Rows locked successfully.")
        } else {
            activeAlert = .submission("No matching rows found to lock in: \(code)")
        }
    }

    // MARK: - Core Data

    private func loadControlCardData() {
        let fetchRequest: NSFetchRequest<ControlCard> = ControlCard.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "rally == %@", rally)
        do {
            let existingCards = try viewContext.fetch(fetchRequest)
            var cardDict = [Int16: ControlCard]()
            for card in existingCards { cardDict[card.row] = card }
            for i in 0..<rows.count {
                let rowNumber = Int16(rows[i].id)
                if let card = cardDict[rowNumber] {
                    rows[i].col1 = card.col1 ?? ""
                    rows[i].col2 = card.col2 ?? ""
                    rows[i].col3 = card.col3 ?? ""
                    rows[i].col4 = card.col4 ?? ""
                    rows[i].col1Locked = card.col1Locked
                    rows[i].col2Locked = card.col2Locked
                    rows[i].col3Locked = card.col3Locked
                    rows[i].col4Locked = card.col4Locked
                    rows[i].rowLocked  = card.rowLocked
                }
            }

            // A card typed before the merk column was dropped still carries rows
            // past the 30th. They are no longer part of the card, so they go
            // rather than travel along on the next submission.
            let stale = existingCards.filter { $0.row > Int16(ControlCardLayout.orcRows) }
            if !stale.isEmpty {
                stale.forEach(viewContext.delete)
                try viewContext.save()
            }
        } catch {
            print("Failed to fetch control cards: \(error)")
        }
    }
    
    private func saveControlCardData() {
        let fetchRequest: NSFetchRequest<ControlCard> = ControlCard.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "rally == %@", rally)
        var existingCards: [Int16: ControlCard] = [:]
        do {
            let cards = try viewContext.fetch(fetchRequest)
            for card in cards { existingCards[card.row] = card }
        } catch {
            print("Failed to fetch control cards for saving: \(error)")
        }
        
        for row in rows {
            let rowNumber = Int16(row.id)
            let card = existingCards[rowNumber] ?? ControlCard(context: viewContext)
            card.row = rowNumber
            card.col1 = row.col1
            card.col2 = row.col2
            card.col3 = row.col3
            card.col4 = row.col4
            card.col1Locked = row.col1Locked
            card.col2Locked = row.col2Locked
            card.col3Locked = row.col3Locked
            card.col4Locked = row.col4Locked
            card.rowLocked  = row.rowLocked
            card.timestamp = Date()
            card.rally = rally
        }
        do {
            try viewContext.save()
        } catch {
            print("Error saving control card data: \(error.localizedDescription)")
        }
    }

    // MARK: - Finalize

    /// Hands the card in to the ORC points system. Only the letters travel: the
    /// server grades them against the stage's key and re-scores the crew's rally,
    /// exactly as when an official types the paper card.
    ///
    /// A card is handed in once. The code is spent on success, so a second
    /// attempt is refused until an official reopens it from the QR page — which
    /// is also why a refusal on that ground closes the card here.
    private func finalizeControlCard() {
        saveControlCardData()

        guard let rallyCode = rally.rallyCode, !rallyCode.isEmpty else {
            activeAlert = .submission("This card has no rally code. Add it again from its QR code.")
            return
        }

        let submission = CardSubmission(
            rallyCode: rallyCode,
            cardId: Int(rally.cardId),
            cardNumber: Int(rally.cardNumber),
            eqNumber: Int(rally.eqNumber),
            eqId: Int(rally.eqId),
            rows: rows.map { row in
                CardSubmission.Row(id: row.id, col1: row.col1, col2: row.col2,
                                   col3: row.col3, col4: row.col4)
            }
        )

        ORCPointsAPI.submit(submission) { result in
            switch result {
            case .success:
                markFinalized()
                activeAlert = .submission("Control card handed in.")

            case .failure(let error):
                // The server already holds this card, so the phone should say so
                // too rather than offering to send it again.
                if let refusal = error as? ORCPointsError, case .alreadySubmitted = refusal {
                    markFinalized()
                }
                activeAlert = .submission(error.localizedDescription)
            }
        }
    }

    private func markFinalized() {
        rally.isFinalized = true
        do {
            try viewContext.save()
        } catch {
            print("Error marking the control card as finalized: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

struct ControlCardView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let sampleRally = Rally(context: context)
        sampleRally.rallyCode = "SampleCode"
        sampleRally.rallyName = "Sample Rally"
        sampleRally.eqNumber = 100
        sampleRally.isFinalized = false
        return NavigationView {
            ControlCardView(rally: sampleRally)
                .environment(\.managedObjectContext, context)
        }
    }
}

// MARK: - QR Scanner

struct QRCodeScannerView: UIViewControllerRepresentable {
    enum ScanError: Error { case badInput, badOutput }
    var completion: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.completion = completion
        return vc
    }
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var completion: ((Result<String, Error>) -> Void)?
    private var didSendResult = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            completion?(.failure(QRCodeScannerView.ScanError.badInput)); return
        }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            completion?(.failure(QRCodeScannerView.ScanError.badInput)); return
        }
        guard captureSession.canAddInput(videoInput) else {
            completion?(.failure(QRCodeScannerView.ScanError.badInput)); return
        }
        captureSession.addInput(videoInput)
        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            completion?(.failure(QRCodeScannerView.ScanError.badOutput)); return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        captureSession.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true { captureSession.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didSendResult else { return }
        if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let str = obj.stringValue {
            didSendResult = true
            captureSession.stopRunning()
            completion?(.success(str))
        }
    }
}
