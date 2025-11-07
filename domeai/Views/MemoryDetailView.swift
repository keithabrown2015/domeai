//
//  MemoryDetailView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UIKit

struct MemoryDetailView: View {
    let category: MemoryCategory
    
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var isRefreshing = false
    
    public init(category: MemoryCategory) {
        self.category = category
    }
    
    private var filteredMemories: [Memory] {
        viewModel.memories
            .filter { $0.category == category }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    private var formattedTimestamp: (Date) -> String = { date in
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            if filteredMemories.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Text(category.emoji)
                        .font(.system(size: 80))
                    
                    Text("No \(category.displayName) yet")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("Ask Ray to remember something!")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray.opacity(0.7))
                }
            } else {
                // Memories list
                List {
                    ForEach(filteredMemories) { memory in
                        MemoryRow(memory: memory, formattedTimestamp: formattedTimestamp(memory.timestamp))
                            .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.12)) // #1C1C1E
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteMemories)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .refreshable {
                    await refreshMemories()
                }
            }
        }
        .navigationTitle("\(category.emoji) \(category.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadMemoriesFromStorage()
        }
    }
    
    private func deleteMemories(at offsets: IndexSet) {
        let memoriesToDelete = offsets.map { filteredMemories[$0] }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Delete with animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for memory in memoriesToDelete {
                viewModel.deleteMemory(memory)
            }
        }
    }
    
    @MainActor
    private func refreshMemories() async {
        isRefreshing = true
        viewModel.loadMemoriesFromStorage()
        
        // Small delay to show refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        isRefreshing = false
    }
}

// MARK: - Memory Row

struct MemoryRow: View {
    let memory: Memory
    let formattedTimestamp: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Memory content
            Text(memory.content)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Timestamp
            Text(formattedTimestamp)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12)) // #1C1C1E
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var viewModel = ChatViewModel()
        
        var body: some View {
            NavigationStack {
                MemoryDetailView(category: .brain)
                    .environmentObject(viewModel)
            }
        }
    }
    
    return PreviewWrapper()
}
