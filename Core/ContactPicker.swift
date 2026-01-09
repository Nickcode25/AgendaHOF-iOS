import SwiftUI
import ContactsUI

/// Dados de um contato selecionado
struct ContactInfo: Equatable {
    let name: String
    let phone: String?
    let email: String?
    let birthday: Date?
}

/// Wrapper SwiftUI para CNContactPickerViewController
struct ContactPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onContactSelected: (ContactInfo) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(value: true)
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Nome completo
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""

            // Telefone (pegar o primeiro disponível)
            let phone = contact.phoneNumbers.first?.value.stringValue

            // Email (pegar o primeiro disponível)
            let email = contact.emailAddresses.first?.value as String?

            // Data de nascimento
            var birthday: Date?
            if let birthdayComponents = contact.birthday {
                birthday = Calendar.current.date(from: birthdayComponents)
            }

            let contactInfo = ContactInfo(
                name: name,
                phone: phone,
                email: email,
                birthday: birthday
            )

            parent.onContactSelected(contactInfo)
        }


        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // Usuário cancelou
        }
    }
}

/// Wrapper SwiftUI para CNContactPickerViewController com múltipla seleção
struct MultiContactPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onContactsSelected: ([ContactInfo]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(value: true)
        // Habilitar múltipla seleção (comportamento padrão quando não implementa didSelectContact único)
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: MultiContactPicker

        init(_ parent: MultiContactPicker) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let selectedContacts = contacts.map { contact -> ContactInfo in
                // Nome completo
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""

                // Telefone (pegar o primeiro disponível)
                let phone = contact.phoneNumbers.first?.value.stringValue

                // Email (pegar o primeiro disponível)
                let email = contact.emailAddresses.first?.value as String?
                
                // Data de nascimento
                var birthday: Date?
                if let birthdayComponents = contact.birthday {
                    birthday = Calendar.current.date(from: birthdayComponents)
                }

                return ContactInfo(
                    name: name,
                    phone: phone,
                    email: email,
                    birthday: birthday
                )
            }

            parent.onContactsSelected(selectedContacts)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // Usuário cancelou
        }
    }
}

/// Botão estilizado para importar contatos
struct ImportContactButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("Importar Contato")
            }
            .foregroundColor(.appPrimary)
        }
    }
}
