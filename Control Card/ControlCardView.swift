import SwiftUI
import CoreData

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
    @State private var rows: [ControlCardRow] = (1...30).map { ControlCardRow(id: $0) }
    
    // Use a single alert state to manage both confirmation and submission alerts.
    @State private var activeAlert: ControlCardAlert? = nil
    
    // Focus state to manage which text field is active.
    @FocusState private var focusedField: Field?

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
                            .disabled(rally.isFinalized)
                        
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
                            .disabled(rally.isFinalized)
                        
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
                            .disabled(rally.isFinalized)
                        
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
                            .disabled(rally.isFinalized)
                    }
                }
            }
            if !rally.isFinalized {
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
        
        guard let url = URL(string: "https://www.sarkonline.com/wp-json/sarkcv/v1/insert") else {
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
