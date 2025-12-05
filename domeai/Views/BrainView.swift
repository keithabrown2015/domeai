//
//  BrainView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import Combine

struct BrainView: View {
    var onDismiss: (() -> Void)?
    @StateObject private var viewModel = BrainViewModel()
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Existing content
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                } else if viewModel.items.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Text("🧠")
                            .font(.system(size: 80))
                        
                        Text("No Brain notes yet")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text("Ask Ray to save something!")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                } else {
                    List {
                        ForEach(viewModel.items) { item in
                            BrainItemRow(item: item)
                                .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.12))
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                    .refreshable {
                        await viewModel.loadItems()
                    }
                }
            }
            
            // High-contrast floating Back to Ray button overlay
            Button(action: { onDismiss?() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.red)
                    
                    Text("Back to Ray")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.yellow)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 18)
                .background(
                    Color.black.opacity(0.75)
                        .blur(radius: 1)
                )
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 4)
            }
            .padding(.top, 35)
            .padding(.leading, 20)
            .zIndex(9999)
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadItems()
        }
    }
}

// MARK: - Brain Item Row

struct BrainItemRow: View {
    let item: RayItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
            
            // Content preview
            Text(item.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.gray)
                .lineLimit(3)
            
            // Subzone and timestamp
            HStack {
                if let subzone = item.subzone, !subzone.isEmpty {
                    Text(subzone.capitalized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.2))
                        )
                }
                
                Spacer()
                
                Text(formatDate(item.created_at))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
        )
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - Brain View Model

@MainActor
class BrainViewModel: ObservableObject {
    @Published var items: [RayItem] = []
    @Published var isLoading = false
    
    func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let url = URL(string: "\(Config.vercelBaseURL)/api/ray-items") else {
            print("❌ Invalid URL for ray-items")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Failed to fetch ray-items: \(response)")
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let fetchedItems = try decoder.decode([RayItem].self, from: data)
            
            // Filter to only brain zone items (should be all, but just in case)
            items = fetchedItems.filter { $0.zone == "brain" }
            
            print("✅ Loaded \(items.count) Brain items")
        } catch {
            print("❌ Error loading Brain items: \(error)")
        }
    }
}

// MARK: - Ray Item Model

struct RayItem: Identifiable, Codable {
    let id: String
    let created_at: String
    let title: String
    let content: String
    let zone: String
    let subzone: String?
    let kind: String
    let tags: String?
    let source: String
}

#Preview {
    NavigationStack {
        BrainView()
    }
}

