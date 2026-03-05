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
}

// Enum to represent each focusable field.
enum Field: Hashable {
    case field(row: Int, col: Int)
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
    @State private var rows: [ControlCardRow] = (1...36).map { ControlCardRow(id: $0) }
    
    @State private var activeAlert: ControlCardAlert? = nil
    @FocusState private var focusedField: Field?
    @State private var isShowingScanner = false

    /// Keep the NFCReader alive for the lifetime of the view.
    @StateObject private var nfcReader = NFCReader()

    var body: some View {
        Form {
            Section(header: Text("Rally Info")) {
                Text("Rally code: \((rally.rallyCode ?? "").uppercased())")
                Text("Kaart nummer: \(rally.cardNumber)")
                Text("EQ nummer: \(rally.eqNumber)")
                if rally.isFinalized {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Status: Finalized")
                    }
                    .foregroundColor(.green)
                    .font(.headline)
                } else {
                    Button(action: {
                        activeAlert = .confirmation
                    }) {
                        HStack {
                            Spacer()
                            Text("Finalize Card")
                                .bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.vertical, 4)
                }
            }

            Section(header: tableHeaderView) {
                ForEach($rows) { $row in
                    HStack {
                        Text("\(row.id)")
                            .frame(width: 40, alignment: .center)
                        
                        // Column 1
                        TextField("", text: $row.col1)
                            .focused($focusedField, equals: .field(row: row.id, col: 1))
                            .font(.system(size: 24))
                            .padding(8)
                            .frame(width: 70, height: 70)
                            .multilineTextAlignment(.center)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .onChange(of: row.col1) { newValue in
                                if row.rowLocked || row.col1Locked { return }
                                let clean = sanitized(newValue)
                                if row.col1 != clean { row.col1 = clean }
                                if clean.count == 1 {
                                    focusedField = .field(row: row.id, col: 2)
                                }
                            }
                            .disabled(rally.isFinalized || row.col1Locked || row.rowLocked)
                        
                        // Column 2
                        TextField("", text: $row.col2)
                            .focused($focusedField, equals: .field(row: row.id, col: 2))
                            .font(.system(size: 24))
                            .padding(8)
                            .frame(width: 70, height: 70)
                            .multilineTextAlignment(.center)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .onChange(of: row.col2) { newValue in
                                if row.rowLocked || row.col2Locked { return }
                                let clean = sanitized(newValue)
                                if row.col2 != clean { row.col2 = clean }
                                if clean.count == 1 {
                                    focusedField = .field(row: row.id, col: 3)
                                }
                            }
                            .disabled(rally.isFinalized || row.col2Locked || row.rowLocked)
                        
                        // Column 3
                        TextField("", text: $row.col3)
                            .focused($focusedField, equals: .field(row: row.id, col: 3))
                            .font(.system(size: 24))
                            .padding(8)
                            .frame(width: 70, height: 70)
                            .multilineTextAlignment(.center)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .onChange(of: row.col3) { newValue in
                                if row.rowLocked || row.col3Locked { return }
                                let clean = sanitized(newValue)
                                if row.col3 != clean { row.col3 = clean }
                                if clean.count == 1 {
                                    focusedField = .field(row: row.id, col: 4)
                                }
                            }
                            .disabled(rally.isFinalized || row.col3Locked || row.rowLocked)
                        
                        // Column 4
                        TextField("", text: $row.col4)
                            .focused($focusedField, equals: .field(row: row.id, col: 4))
                            .font(.system(size: 24))
                            .padding(8)
                            .frame(width: 70, height: 70)
                            .multilineTextAlignment(.center)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .onChange(of: row.col4) { newValue in
                                if row.rowLocked || row.col4Locked { return }
                                let clean = sanitized(newValue)
                                if row.col4 != clean { row.col4 = clean }
                                if clean.count == 1 {
                                    if let currentIndex = rows.firstIndex(where: { $0.id == row.id }),
                                       currentIndex < rows.count - 1 {
                                        let nextRow = rows[currentIndex + 1]
                                        focusedField = .field(row: nextRow.id, col: 1)
                                    } else {
                                        focusedField = nil
                                    }
                                }
                            }
                            .disabled(rally.isFinalized || row.col4Locked || row.rowLocked)
                    }
                    .opacity(row.rowLocked ? 0.5 : 1.0)
                    .background(row.rowLocked ? Color.gray.opacity(0.15) : Color.clear)
                }
            }

            if !rally.isFinalized {
                Section {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }

                    Button {
                        startNFCScan()
                    } label: {
                        Label("Scan NFC Tag", systemImage: "wave.3.right")
                    }
                }
                
                Section {
                    Button("Finalize") {
                        activeAlert = .confirmation
                    }
                }
            }
        }
        .navigationTitle("Control Card")
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
        }
        .onAppear(perform: loadControlCardData)
        .onDisappear(perform: saveControlCardData)
        .onChange(of: scenePhase) { newPhase in
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

    // MARK: - Shared scan handler

    private var tableHeaderView: some View {
        HStack {
            Text("Row").frame(width: 40, alignment: .leading)
            Text("Col1").frame(width: 70)
            Text("Col2").frame(width: 70)
            Text("Col3").frame(width: 70)
            Text("Col4").frame(width: 70)
        }
    }
    
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

        if rowData.col1.isEmpty && !rowData.col1Locked {
            rowData.col1 = value; rowData.col1Locked = true
        } else if rowData.col2.isEmpty && !rowData.col2Locked {
            rowData.col2 = value; rowData.col2Locked = true
        } else if rowData.col3.isEmpty && !rowData.col3Locked {
            rowData.col3 = value; rowData.col3Locked = true
        } else if rowData.col4.isEmpty && !rowData.col4Locked {
            rowData.col4 = value; rowData.col4Locked = true
        } else {
            activeAlert = .submission("Row \(row) already has all 4 columns filled.")
            return
        }

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
            row.col1Locked = true
            row.col2Locked = true
            row.col3Locked = true
            row.col4Locked = true
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

    private func finalizeControlCard() {
        let payload: [String: Any] = [
            "eqNumber": rally.eqNumber,
            "rallyCode": rally.rallyCode ?? "",
            "eqId": rally.eqId,
            "cardId": rally.cardId,
            "cardNumber": rally.cardNumber,
            "rows": rows.map { row in
                ["id": row.id, "col1": row.col1, "col2": row.col2,
                 "col3": row.col3, "col4": row.col4]
            }
        ]
        
        do {
            let debugData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            if let debugJson = String(data: debugData, encoding: .utf8) {
                print("🚀 FinalizeControlCard payload:\n\(debugJson)")
            }
        } catch { print("❌ Failed to print debug JSON: \(error)") }
        
        guard let url = URL(string: "https://orc.sarkonline.com/umbraco/surface/controlekaart/saveAppEquipeKaart") else {
            activeAlert = .submission("Invalid URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            activeAlert = .submission("Error encoding JSON: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    activeAlert = .submission("Error sending data: \(error.localizedDescription)")
                }
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 200 {
                        activeAlert = .submission("Data submitted successfully!")
                        rally.isFinalized = true
                        try? viewContext.save()
                    } else {
                        activeAlert = .submission("Submission failed with status code: \(httpResponse.statusCode)")
                    }
                }
            }
        }.resume()
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
