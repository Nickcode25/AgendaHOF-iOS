import SwiftUI
import Contacts

struct CustomContactPickerView: View {
    @Environment(\.dismiss) var dismiss
    var onContactsSelected: ([ContactInfo]) -> Void
    
    @State private var contacts: [ContactInfo] = []
    @State private var searchText = ""
    @State private var selectedContacts: Set<String> = [] // ID based or Name based
    @State private var isLoading = true
    @State private var permissionError = false
    
    // Identificador único simples para seleção (usando nome + telefone como chave)
    private func contactId(_ contact: ContactInfo) -> String {
        return "\(contact.name)-\(contact.phone ?? "")"
    }

    var filteredContacts: [ContactInfo] {
        if searchText.isEmpty {
            return contacts
        } else {
            return contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                (contact.phone?.contains(searchText) ?? false)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if permissionError {
                    VStack(spacing: 16) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Acesso aos contatos negado")
                            .font(.headline)
                        Text("Por favor, habilite o acesso aos contatos nos Ajustes para importar seus pacientes.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Button("Abrir Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView("Carregando contatos...")
                } else {
                    List {
                        ForEach(filteredContacts, id: \.name) { contact in // Usando nome como ID para simplicidade na lista
                            HStack {
                                // Checkbox style integration
                                Image(systemName: selectedContacts.contains(contactId(contact)) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedContacts.contains(contactId(contact)) ? .appPrimary : .gray)
                                    .font(.system(size: 22))
                                
                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    if let phone = contact.phone {
                                        Text(phone)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.leading, 8)
                                
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(contact)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar contato")
                }
            }
            .navigationTitle("Importar Contatos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Importar (\(selectedContacts.count))") {
                        finishSelection()
                    }
                    .disabled(selectedContacts.isEmpty)
                    .fontWeight(.bold)
                }
            }
            .task {
                await fetchContacts()
            }
        }
    }
    
    private func toggleSelection(_ contact: ContactInfo) {
        let id = contactId(contact)
        if selectedContacts.contains(id) {
            selectedContacts.remove(id)
        } else {
            selectedContacts.insert(id)
        }
    }
    
    private func finishSelection() {
        let selected = contacts.filter { selectedContacts.contains(contactId($0)) }
        onContactsSelected(selected)
    }

    private func fetchContacts() async {
        let store = CNContactStore()
        
        // Verificar permissão
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted {
            permissionError = true
            isLoading = false
            return
        }
        
        if status == .notDetermined {
            do {
                try await store.requestAccess(for: .contacts)
                // Re-check status after request
                let newStatus = CNContactStore.authorizationStatus(for: .contacts)
                
                if #available(iOS 18.0, *) {
                    if newStatus == .limited {
                        // LIMITED ACCESS FLOW: User just selected contacts in system prompt.
                        // Auto-import them to avoid "Double Selection".
                        await fetchAndAutoImport(store: store)
                        return
                    }
                }
            } catch {
                permissionError = true
                isLoading = false
                return
            }
        } else {
             if #available(iOS 18.0, *) {
                 if status == .limited {
                     // Already limited, auto-import to avoid showing list again
                     await fetchAndAutoImport(store: store)
                     return
                 }
             }
        }
        
        // Buscar contatos
        isLoading = true
        
        // Move keys creation to background task to avoid capture warnings
        // Use Task.detached for background work properly
        Task.detached(priority: .userInitiated) {
             let store = CNContactStore() // Create new instance in background
             var keys: [Any] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactBirthdayKey]
             keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))
             
             let request = CNContactFetchRequest(keysToFetch: keys as! [CNKeyDescriptor])
             request.sortOrder = .userDefault
             
             var fetchedContacts: [ContactInfo] = []
             
             do {
                 try store.enumerateContacts(with: request) { contact, _ in
                     let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                     let phone = contact.phoneNumbers.first?.value.stringValue
                     let email = contact.emailAddresses.first?.value as String?
                     var birthday: Date?
                     if let birthdayComponents = contact.birthday {
                         birthday = Calendar.current.date(from: birthdayComponents)
                     }
                     
                     if !name.isEmpty {
                         fetchedContacts.append(ContactInfo(name: name, phone: phone, email: email, birthday: birthday))
                     }
                 }
                 
                 await MainActor.run {
                     self.contacts = fetchedContacts
                     self.isLoading = false
                 }
             } catch {
                 print("Erro ao buscar contatos: \(error)")
                 await MainActor.run {
                     self.isLoading = false
                 }
             }
        }
    }
    
    // Helper para Auto-Import (Limited Access)
    private func fetchAndAutoImport(store: CNContactStore) async {
        isLoading = true
        
        // Use detached task to avoid capturing non-sendable types in async context
        await Task.detached(priority: .userInitiated) { [onContactsSelected] in
            let store = CNContactStore()
            var keys: [Any] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactBirthdayKey]
            keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))
            
            let request = CNContactFetchRequest(keysToFetch: keys as! [CNKeyDescriptor])
            request.sortOrder = .userDefault
            
            var contacts: [ContactInfo] = []
            
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                    let phone = contact.phoneNumbers.first?.value.stringValue
                    let email = contact.emailAddresses.first?.value as String?
                    var birthday: Date?
                    if let birthdayComponents = contact.birthday {
                        birthday = Calendar.current.date(from: birthdayComponents)
                    }
                    
                    if !name.isEmpty {
                        contacts.append(ContactInfo(name: name, phone: phone, email: email, birthday: birthday))
                    }
                }
                
                let finalContacts = contacts
                await MainActor.run {
                    onContactsSelected(finalContacts)
                }
            } catch {
                print("Erro no auto-import: \(error)")
            }
        }.value
    }
}

#Preview {
    CustomContactPickerView { _ in }
}
