import SwiftUI
import CoreData
import AVFoundation

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
}

// Enum to represent each focusable field.
enum Field: Hashable {
    case field(row: Int, col: Int)
}

struct ControlCardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) var scenePhase

    // The Rally object for which we are creating the control card.
    @ObservedObject var rally: Rally
    @State private var rows: [ControlCardRow] = (1...40).map { ControlCardRow(id: $0) }
    
    // Use a single alert state to manage both confirmation and submission alerts.
    @State private var activeAlert: ControlCardAlert? = nil
    
    // Focus state to manage which text field is active.
    @FocusState private var focusedField: Field?
    
    @State private var isShowingScanner = false

    var body: some View {
        Form {
            Section(header: Text("Rally Info")) {
                Text("Rally Code: \(rally.rallyCode ?? "")")
                Text("Rally Name: \(rally.rallyName ?? "")")
                Text("EQ Number: \(rally.eqNumber)")
                if rally.isFinalized {
                    Text("Status: Finalized")
                        .foregroundColor(.green)
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
                                if newValue.count > 1 {
                                    row.col1 = String(newValue.prefix(1))
                                }
                                if newValue.count == 1 {
                                    // Move to the next column.
                                    focusedField = .field(row: row.id, col: 2)
                                }
                            }
                            .disabled(rally.isFinalized || row.col1Locked)
                        
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
                                if newValue.count > 1 {
                                    row.col2 = String(newValue.prefix(1))
                                }
                                if newValue.count == 1 {
                                    focusedField = .field(row: row.id, col: 3)
                                }
                            }
                            .disabled(rally.isFinalized || row.col2Locked)
                        
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
                                if newValue.count > 1 {
                                    row.col3 = String(newValue.prefix(1))
                                }
                                if newValue.count == 1 {
                                    focusedField = .field(row: row.id, col: 4)
                                }
                            }
                            .disabled(rally.isFinalized || row.col3Locked)
                        
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
                                if newValue.count > 1 {
                                    row.col4 = String(newValue.prefix(1))
                                }
                                if newValue.count == 1 {
                                    // If not on the last row, move focus to the first column of the next row.
                                    if let currentIndex = rows.firstIndex(where: { $0.id == row.id }),
                                       currentIndex < rows.count - 1 {
                                        let nextRow = rows[currentIndex + 1]
                                        focusedField = .field(row: nextRow.id, col: 1)
                                    } else {
                                        // Optionally, clear focus if it was the last row.
                                        focusedField = nil
                                    }
                                }
                            }
                            .disabled(rally.isFinalized || row.col4Locked)
                    }
                }
            }
            if !rally.isFinalized {
                Section {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                }
                
                Section {
                    Button("Finalize") {
                        // Show confirmation popup before finalizing.
                        activeAlert = .confirmation
                    }
                }
            }
        }
        .navigationTitle("Control Card")
        .onAppear(perform: loadControlCardData)
        .onDisappear(perform: saveControlCardData)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                saveControlCardData()
            }
        }
        // Present the alert based on the activeAlert state.
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
    
    // Header for the table columns.
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
        // Expect something like "15:G"
        let parts = code.split(separator: ":")

        guard parts.count == 2,
              let rowNumber = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let letter = parts[1].trimmingCharacters(in: .whitespaces).first else {
            activeAlert = .submission("Unexpected QR format: \(code). Expected e.g. 15:G")
            return
        }

        guard let index = rows.firstIndex(where: { $0.id == rowNumber }) else {
            activeAlert = .submission("Row \(rowNumber) is not in this control card.")
            return
        }

        var row = rows[index]
        let value = String(letter)

        // Put the letter in the first free, non-locked column
        if row.col1.isEmpty && !row.col1Locked {
            row.col1 = value
            row.col1Locked = true
        } else if row.col2.isEmpty && !row.col2Locked {
            row.col2 = value
            row.col2Locked = true
        } else if row.col3.isEmpty && !row.col3Locked {
            row.col3 = value
            row.col3Locked = true
        } else if row.col4.isEmpty && !row.col4Locked {
            row.col4 = value
            row.col4Locked = true
        } else {
            activeAlert = .submission("Row \(rowNumber) already has all 4 columns filled.")
            return
        }

        rows[index] = row
        
        saveControlCardData()
    }
    
    // Load any previously saved ControlCard data for this Rally.
    private func loadControlCardData() {
        let fetchRequest: NSFetchRequest<ControlCard> = ControlCard.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "rally == %@", rally)
        
        do {
            let existingCards = try viewContext.fetch(fetchRequest)
            // Map existing ControlCards by their row number.
            var cardDict = [Int16: ControlCard]()
            for card in existingCards {
                cardDict[card.row] = card
            }
            // Update the local rows array with saved data.
            for i in 0..<rows.count {
                let rowNumber = Int16(rows[i].id)
                if let card = cardDict[rowNumber] {
                    rows[i].col1 = card.col1 ?? ""
                    rows[i].col2 = card.col2 ?? ""
                    rows[i].col3 = card.col3 ?? ""
                    rows[i].col4 = card.col4 ?? ""
                    
                    // NEW: restore lock flags
                    rows[i].col1Locked = card.col1Locked
                    rows[i].col2Locked = card.col2Locked
                    rows[i].col3Locked = card.col3Locked
                    rows[i].col4Locked = card.col4Locked
                }
            }
        } catch {
            print("Failed to fetch control cards: \(error)")
        }
    }
    
    // Save the current table data to Core Data.
    private func saveControlCardData() {
        let fetchRequest: NSFetchRequest<ControlCard> = ControlCard.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "rally == %@", rally)
        var existingCards: [Int16: ControlCard] = [:]
        do {
            let cards = try viewContext.fetch(fetchRequest)
            for card in cards {
                existingCards[card.row] = card
            }
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
            
            // NEW: persist lock flags
            card.col1Locked = row.col1Locked
            card.col2Locked = row.col2Locked
            card.col3Locked = row.col3Locked
            card.col4Locked = row.col4Locked
            
            card.timestamp = Date()
            card.rally = rally
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving control card data: \(error.localizedDescription)")
        }
    }
    
    // Finalize the control card by sending the data to your webservice.
    private func finalizeControlCard() {
        let payload: [String: Any] = [
            "eqNumber": String(rally.eqNumber),
            "rallyCode": rally.rallyCode ?? "",
            "rows": rows.map { row in
                return [
                    "id": row.id,
                    "col1": row.col1,
                    "col2": row.col2,
                    "col3": row.col3,
                    "col4": row.col4
                ]
            }
        ]
        
//        guard let url = URL(string: "https://www.sarkonline.com/wp-json/sarkcv/v1/insert") else {
//            activeAlert = .submission("Invalid URL.")
//            return
//        }
        
        guard let url = URL(string: "https://webhook.site/1c31ed34-e29e-47d3-bf11-04d3573de1b6") else {
            activeAlert = .submission("Invalid URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            activeAlert = .submission("Error encoding JSON: \(error.localizedDescription)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                        // Mark the rally as finalized.
                        rally.isFinalized = true
                        do {
                            try viewContext.save()
                        } catch {
                            print("Error saving finalized rally: \(error.localizedDescription)")
                        }
                    } else {
                        activeAlert = .submission("Submission failed with status code: \(httpResponse.statusCode)")
                    }
                }
            }
        }
        task.resume()
    }
}

struct ControlCardView_Previews: PreviewProvider {
    static var previews: some View {
        // Use your PersistenceController preview context
        let context = PersistenceController.preview.container.viewContext
        
        // Create a sample Rally managed object.
        let sampleRally = Rally(context: context)
        sampleRally.rallyCode = "SampleCode"
        sampleRally.rallyName = "Sample Rally"
        sampleRally.eqNumber = 100
        sampleRally.isFinalized = false  // Set to true to preview the finalized (read-only) view.
        
        return NavigationView {
            ControlCardView(rally: sampleRally)
                .environment(\.managedObjectContext, context)
        }
    }
}


struct QRCodeScannerView: UIViewControllerRepresentable {
    enum ScanError: Error {
        case badInput
        case badOutput
    }

    var completion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.completion = completion
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        // Nothing to update
    }
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
            completion?(.failure(QRCodeScannerView.ScanError.badInput))
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            completion?(.failure(QRCodeScannerView.ScanError.badInput))
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            completion?(.failure(QRCodeScannerView.ScanError.badInput))
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            completion?(.failure(QRCodeScannerView.ScanError.badOutput))
            return
        }

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
        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didSendResult else { return }

        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            didSendResult = true
            captureSession.stopRunning()
            completion?(.success(stringValue))
        }
    }
}
