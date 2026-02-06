import SwiftUI
import Contacts

struct ContactPickerView: View {
    @Environment(\.dismiss) var dismiss
    var onContactsSelected: ([ContactInfo]) -> Void

    @State private var contacts: [InternalContact] = []
    @State private var selectedContactIds: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var permissionError = false

    var filteredContacts: [InternalContact] {
        if searchText.isEmpty {
            return contacts
        }
        let query = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return contacts.filter { contact in
            let name = contact.fullName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return name.contains(query)
        }
    }
    
    var groupedContacts: [String: [InternalContact]] {
        Dictionary(grouping: filteredContacts) { contact in
            String(contact.fullName.prefix(1)).uppercased()
        }
    }
    
    var sortedKeys: [String] {
        groupedContacts.keys.sorted()
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Carregando contatos...")
                } else if permissionError {
                    ContentUnavailableView(
                        "Acesso aos Contatos Negado",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Por favor, habilite o acesso aos contatos nas Configurações para importar pacientes.")
                    )
                } else if contacts.isEmpty {
                    ContentUnavailableView(
                        "Nenhum contato encontrado",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(sortedKeys, id: \.self) { key in
                                Section(header: Text(key)) {
                                    ForEach(groupedContacts[key] ?? []) { contact in
                                        ContactRow(
                                            contact: contact,
                                            isSelected: selectedContactIds.contains(contact.id)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            toggleSelection(for: contact)
                                        }
                                    }
                                }
                                .id(key)
                            }
                        }
                        .listStyle(.plain)
                        .overlay(alignment: .trailing) {
                            if !searchText.isEmpty {
                                EmptyView()
                            } else {
                                sectionIndex(proxy: proxy)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contatos")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar contato pelo nome")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                    .tint(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        finishSelection()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "ff6b00"))
                    }
                    .disabled(selectedContactIds.isEmpty)
                }
            }
            .onAppear {
                fetchContacts()
            }
        }
    }
    
    private func sectionIndex(proxy: ScrollViewProxy) -> some View {
        VStack {
            ForEach(sortedKeys, id: \.self) { letter in
                Button {
                    withAnimation {
                        proxy.scrollTo(letter, anchor: .top)
                    }
                } label: {
                    Text(letter)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 15)
                }
            }
        }
        .padding(.trailing, 4)
    }

    private func toggleSelection(for contact: InternalContact) {
        if selectedContactIds.contains(contact.id) {
            selectedContactIds.remove(contact.id)
        } else {
            selectedContactIds.insert(contact.id)
        }
    }

    private func finishSelection() {
        let selected = contacts.filter { selectedContactIds.contains($0.id) }
        let result = selected.map { $0.toContactInfo() }
        onContactsSelected(result)
        dismiss()
    }

    private func fetchContacts() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            
            do {
                let authorized = try await store.requestAccess(for: .contacts)
                guard authorized else {
                    await MainActor.run {
                        isLoading = false
                        permissionError = true
                    }
                    return
                }

                let keys = [
                    CNContactGivenNameKey,
                    CNContactFamilyNameKey,
                    CNContactPhoneNumbersKey,
                    CNContactEmailAddressesKey,
                    CNContactBirthdayKey,
                    CNContactThumbnailImageDataKey
                ] as [CNKeyDescriptor]

                let request = CNContactFetchRequest(keysToFetch: keys)
                request.sortOrder = .userDefault

                let accumulator = ContactAccumulator()
                
                try store.enumerateContacts(with: request) { contact, _ in
                    let fullName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    
                    if !fullName.isEmpty {
                        accumulator.contacts.append(InternalContact(contact: contact, fullName: fullName))
                    }
                }

                await MainActor.run {
                    self.contacts = accumulator.contacts.sorted { $0.fullName < $1.fullName }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    print("Error fetching contacts: \(error)")
                    self.isLoading = false
                    self.permissionError = true
                }
            }
        }
    }
}

// MARK: - Internal Models & Views

struct InternalContact: Identifiable {
    let id: String
    let fullName: String
    let phone: String?
    let email: String?
    let birthday: Date?
    let initials: String
    
    init(contact: CNContact, fullName: String) {
        self.id = contact.identifier
        self.fullName = fullName
        
        self.phone = contact.phoneNumbers.first?.value.stringValue
        self.email = contact.emailAddresses.first?.value as String?
        self.birthday = contact.birthday?.date
        
        // Initials
        let first = contact.givenName.prefix(1)
        let last = contact.familyName.prefix(1)
        var tempInitials = "\(first)\(last)".uppercased()
        if tempInitials.isEmpty {
             tempInitials = String(fullName.prefix(2)).uppercased()
        }
        self.initials = tempInitials
    }
    
    func toContactInfo() -> ContactInfo {
        ContactInfo(name: fullName, phone: phone, email: email, birthday: birthday)
    }
}

// Wrapper class to safely capture mutable state in closure
final class ContactAccumulator {
    var contacts: [InternalContact] = []
}

struct ContactRow: View {
    let contact: InternalContact
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? Color(hex: "ff6b00") : .gray.opacity(0.3))
            
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: "5c8ae6").opacity(0.8)) // Similar to screenshot blue/purple
                    .frame(width: 42, height: 42)
                
                Text(contact.initials)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            // Name
            Text(contact.fullName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
#Preview {
    ContactPickerView { _ in }
}
