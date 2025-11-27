//
//  EmailSettingsView.swift
//  domeai
//
//  Created for DomeAI email feature
//

import SwiftUI

struct EmailSettingsView: View {
    @EnvironmentObject var userSettings: UserSettings
    @Environment(\.dismiss) var dismiss
    @State private var emailText: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Your email address", text: $emailText)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Email Address")
                } footer: {
                    Text("Ray will use this email address when you ask him to send you information.")
                }
            }
            .navigationTitle("Email Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        userSettings.setEmail(emailText)
                        dismiss()
                    }
                }
            }
            .onAppear {
                emailText = userSettings.email ?? ""
            }
        }
    }
}

