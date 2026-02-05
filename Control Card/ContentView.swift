import SwiftUI
import CoreData

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
                    .frame(height: 100) // Adjust the height as needed
                    .padding(.vertical) // Optional: add some vertical padding
                
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
                                        Text("\(item.rallyName ?? "") - KAART: \(item.cardNumber) - EQ: \(item.eqNumber)").textCase(.uppercase)
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

struct AddRallyView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss

    @State private var code: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""


    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Enter the code to receive your Control Card")) {
                    TextField("code", text: $code)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("Add Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRally()
                    }
                }
            }
            .alert(isPresented: $showError) {
                Alert(title: Text("Error"),
                      message: Text(errorMessage),
                      dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func addRally() {
        var components = URLComponents(
            string: "https://orc.sarkonline.com/umbraco/surface/controlekaart/getEquipeByAppCode"
        )
        components?.queryItems = [
            URLQueryItem(name: "appcode", value: code)
        ]

        guard let url = components?.url else {
            errorMessage = "Invalid URL."
            showError = true
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                let data = data,
                httpResponse.statusCode == 200
            else {
                DispatchQueue.main.async {
                    errorMessage = "Unexpected server response."
                    showError = true
                }
                return
            }

            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let status = json["rallycode"] as? String,
                    status != ""
                else {
                    DispatchQueue.main.async {
                        errorMessage = "Invalid response from server."
                        showError = true
                    }
                    return
                }

                let rallyCode = json["rallycode"] as? String ?? ""
                let equipeNr = json["equipenr"] as? Int ?? 0
                let equipeId = json["equipeid"] as? Int ?? 0
                let kaartNr = json["kaartnr"] as? Int ?? 0
                let kaartId = json["kaartid"] as? Int ?? 0

                viewContext.perform {
                    //DUPLICATE CHECK
                    let fetchRequest: NSFetchRequest<Rally> = Rally.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "cardId == %d AND eqId == %d", kaartId, equipeId)
                    fetchRequest.fetchLimit = 1

                    do {
                        let existing = try viewContext.fetch(fetchRequest)
                        if !existing.isEmpty {
                            DispatchQueue.main.async {
                                errorMessage = "This control card is already added."
                                showError = true
                            }
                            return
                        }

                        //Safe to insert
                        let newRally = Rally(context: viewContext)
                        newRally.rallyCode = rallyCode
                        newRally.rallyName = rallyCode
                        newRally.eqNumber = Int16(equipeNr)
                        newRally.eqId = Int16(equipeId)
                        newRally.cardNumber = Int16(kaartNr)
                        newRally.cardId = Int16(kaartId)
                        newRally.isFinalized = false

                        try viewContext.save()

                        DispatchQueue.main.async {
                            dismiss()
                        }

                    } catch {
                        DispatchQueue.main.async {
                            errorMessage = "Database error while checking duplicates."
                            showError = true
                        }
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to parse response."
                    showError = true
                }
            }
        }.resume()
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
