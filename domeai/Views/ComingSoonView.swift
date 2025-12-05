//
//  ComingSoonView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI

struct ComingSoonView: View {
    var onDismiss: (() -> Void)?
    let emoji: String
    let title: String
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Existing content
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text(emoji)
                        .font(.system(size: 80))
                    
                    Text("\(title) Coming Soon")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("This feature is under development")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.gray)
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
        .navigationTitle("\(emoji) \(title)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(onDismiss: {}, emoji: "⏰", title: "Nudges")
    }
}

