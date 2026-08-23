import SwiftUI
import CoreData
import AVFoundation

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Rally.eqNumber, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Rally>
    
    @State private var showingAddRally = false

    var body: some View {
        NavigationView {
            VStack {
                Image("SARKLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 100)
                    .padding(.vertical)
                
                if items.isEmpty {
                    Text("Add a control card to get started")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(items) { item in
                            NavigationLink {
                                ControlCardView(rally: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.rallyName ?? item.rallyCode ?? "") - KAART: \(item.cardNumber) - EQ: \(item.eqNumber)")
                                        .textCase(.uppercase)

                                    // What the points system knows about the card
                                    // and the crew, when the entry list holds it.
                                    if let subtitle = subtitle(for: item) {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingAddRally = true }) {
                        Label("Add Rally", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddRally) {
                AddRallyView()
                    .environment(\.managedObjectContext, viewContext)
            }
            Text("Select an item")
        }
    }

    /// The card's own name and its crew, joined into one caption line.
    private func subtitle(for rally: Rally) -> String? {
        let parts = [rally.cardName, rally.crewName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// MARK: - QR Scanner

/// Coordinator: receives AVFoundation callbacks and forwards the scanned string.
final class SARKQRCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: (String) -> Void
    private var hasScanned = false

    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        hasScanned = true
        DispatchQueue.main.async { self.onScan(value) }
    }
}

/// UIViewController that owns the AVCaptureSession and preview layer.
/// Named with SARK prefix to avoid conflicts with any existing ScannerViewController in the project.
final class SARKQRScannerVC: UIViewController {

    /// Set before the view loads — passed directly to AVCaptureMetadataOutput.
    var metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func setupSession() {
        let session = AVCaptureSession()

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            showUnavailableLabel()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        // Delegate is already set before viewDidLoad via makeUIViewController
        output.setMetadataObjectsDelegate(metadataDelegate, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func showUnavailableLabel() {
        let label = UILabel(frame: view.bounds)
        label.text = "Camera not available"
        label.textColor = .white
        label.textAlignment = .center
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }
}

/// SwiftUI wrapper around SARKQRScannerVC.
struct SARKQRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeCoordinator() -> SARKQRCoordinator {
        SARKQRCoordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> SARKQRScannerVC {
        let vc = SARKQRScannerVC()
        vc.metadataDelegate = context.coordinator   // set BEFORE view loads
        return vc
    }

    func updateUIViewController(_ uiViewController: SARKQRScannerVC, context: Context) {}
}

// MARK: - Add Rally View

struct AddRallyView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss

    @State private var code: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingScanner: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Enter the code to receive your Control Card")) {
                    HStack {
                        TextField("Code", text: $code)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.borderless) // Prevents the tap from submitting the form
                    }
                }

                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Add Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addRally() }
                }
            }
            .alert(isPresented: $showError) {
                Alert(title: Text("Error"),
                      message: Text(errorMessage),
                      dismissButton: .default(Text("OK")))
            }
            // QR Scanner sheet
            .sheet(isPresented: $showingScanner) {
                NavigationView {
                    ZStack {
                        SARKQRScannerView { scannedValue in
                            showingScanner = false
                            handleScannedCode(scannedValue)
                        }
                        .ignoresSafeArea()

                        VStack {
                            Spacer()
                            Text("Point the camera at the QR code")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                                .padding(.bottom, 40)
                        }
                    }
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingScanner = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - QR Code Handler

    /// Parses the scanned QR value. Expected format: "ADD:<code>"
    private func handleScannedCode(_ value: String) {
        let prefix = "ADD:"
        guard value.uppercased().hasPrefix(prefix) else {
            errorMessage = "Invalid QR code. Expected format: ADD:<code>"
            showError = true
            return
        }
        // Strip the prefix (case-insensitive) and use the remainder as the code
        code = String(value.dropFirst(prefix.count))
        // Automatically submit after a short delay so the user can see the filled code
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            addRally()
        }
    }

    // MARK: - Network Request

    /// Pulls the card behind the code out of the ORC points system and stores it
    /// locally. Nothing else is fetched: from here on the card is typed offline
    /// and only travels back when the crew finalizes it.
    private func addRally() {
        let trimmed = ApiConfig.normalize(code)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter or scan a code first."
            showError = true
            return
        }

        ORCPointsAPI.fetchCard(code: trimmed) { result in
            switch result {
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true

            case .success(let card):
                store(card)
            }
        }
    }

    /// Writes the looked-up card to Core Data, refusing a card the crew already
    /// has. A card is identified by its rally, its card number and its equipe —
    /// the card number alone repeats across rallies.
    private func store(_ card: CardLookup) {
        guard let eqNumber = Int16(exactly: card.eqNumber),
              let eqId = Int16(exactly: card.eqId),
              let cardId = Int16(exactly: card.cardId),
              let cardNumber = Int16(exactly: card.cardNumber) else {
            errorMessage = "This card has numbers this app cannot store."
            showError = true
            return
        }

        let fetchRequest: NSFetchRequest<Rally> = Rally.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "rallyCode ==[c] %@ AND cardId == %d AND eqNumber == %d",
            card.rallyCode, cardId, eqNumber
        )
        fetchRequest.fetchLimit = 1

        do {
            if try !viewContext.fetch(fetchRequest).isEmpty {
                errorMessage = "This control card is already added."
                showError = true
                return
            }

            let newRally = Rally(context: viewContext)
            newRally.rallyCode  = card.rallyCode
            // The rally's own name when the points system knows one; its code is
            // what is printed on the card, so it is the fallback.
            newRally.rallyName  = card.rallyName.isEmpty ? card.rallyCode : card.rallyName
            newRally.cardName   = card.cardName
            newRally.crewName   = card.crewName
            newRally.eqNumber   = eqNumber
            newRally.eqId       = eqId
            newRally.cardNumber = cardNumber
            newRally.cardId     = cardId
            // A code that has already been handed in gives back a card that can
            // be read but not sent again, so it is added closed.
            newRally.isFinalized = card.alreadySubmitted

            try viewContext.save()
            dismiss()

        } catch {
            errorMessage = "Could not store this control card."
            showError = true
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
