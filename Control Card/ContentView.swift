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
                                        Text("\(item.rallyName ?? "") - EQ: \(item.eqNumber)")
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
            guard let url = URL(string: "https://sarkonline.com/wp-json/control-cards/v1/update-code") else {
                errorMessage = "Invalid URL."
                showError = true
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // Send the code as form-encoded data
            let postString = "code=\(code)"
            request.httpBody = postString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else { return }
                
                if httpResponse.statusCode == 200, let data = data {
                    // Try to parse the JSON response
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let success = json["success"] as? Bool, success {
                            
                            // Retrieve returned rally_code and eq_number.
                            let returnedRallyCode = json["rally_code"] as? String ?? ""
                            let returnedEqNumber = json["eq_number"] as? String ?? "0"
                            
                            // Create a new Rally object and set its properties.
                            let newRally = Rally(context: viewContext)
                            newRally.rallyCode = returnedRallyCode
                            newRally.rallyName = returnedRallyCode
                            newRally.eqNumber = Int16(returnedEqNumber) ?? 0
                            newRally.isFinalized = false
                            
                            try viewContext.save()
                            DispatchQueue.main.async {
                                dismiss()
                            }
                        } else {
                            DispatchQueue.main.async {
                                errorMessage = "Invalid response from server."
                                showError = true
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            errorMessage = "Failed to parse response: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                } else if httpResponse.statusCode == 400 {
                    // Display error when the code is already used.
                    DispatchQueue.main.async {
                        errorMessage = "The code has already been used."
                        showError = true
                    }
                } else {
                    // Handle any other unexpected HTTP status codes.
                    DispatchQueue.main.async {
                        errorMessage = "Unexpected error: HTTP \(httpResponse.statusCode)"
                        showError = true
                    }
                }
            }.resume()
        }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
