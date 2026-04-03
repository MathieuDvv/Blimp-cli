import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var cloudPhase = 0.0
    
    var body: some View {
        ZStack {
            // Elegant Watercolor Sky
            MeshGradientView()
                .ignoresSafeArea()
            
            // Floating Soft Clouds
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 250, height: 250)
                        .blur(radius: 60)
                        .offset(x: cloudPhase * geo.size.width - 100, y: -60)
                    
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 200, height: 200)
                        .blur(radius: 50)
                        .offset(x: -cloudPhase * geo.size.width + 100, y: geo.size.height / 2 + 50)
                }
            }
            .animation(.easeInOut(duration: 15).repeatForever(autoreverses: true), value: cloudPhase)
            .onAppear {
                cloudPhase = 1.0
            }
            
            VStack(spacing: 20) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    Text("BLIMP")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(4)
                }
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .padding(.top, 25)
                
                HStack(spacing: 24) {
                    // RAM / Gas Pressure
                    PastelCard(
                        title: "Gas Pressure",
                        value: monitor.usedRAM,
                        total: monitor.totalRAM,
                        isLoading: monitor.isFreeingRAM,
                        action: monitor.freeRAMAction,
                        buttonText: "Vent",
                        color: Color.blue
                    )
                    
                    // Storage / Cargo Weight
                    PastelCard(
                        title: "Cargo Weight",
                        value: monitor.freeableStorage,
                        total: monitor.totalStorage,
                        isLoading: monitor.isCleaningStorage,
                        action: monitor.cleanStorageAction,
                        buttonText: monitor.freeableStorage == 0 ? "Empty" : "Drop",
                        color: Color.pink
                    )
                }
                .padding(.horizontal, 25)
                .padding(.bottom, 25)
            }
        }
        .frame(width: 420, height: 300)
    }
}

struct MeshGradientView: View {
    @State private var isAnimating = false
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                isAnimating ? Color(red: 0.98, green: 0.85, blue: 0.92) : Color(red: 0.7, green: 0.85, blue: 0.98),
                isAnimating ? Color(red: 0.7, green: 0.85, blue: 0.98) : Color(red: 0.98, green: 0.95, blue: 0.9)
            ]),
            startPoint: isAnimating ? .topLeading : .bottomTrailing,
            endPoint: isAnimating ? .bottomTrailing : .topLeading
        )
        .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

struct PastelCard: View {
    let title: String
    let value: Double
    let total: Double
    let isLoading: Bool
    let action: () -> Void
    let buttonText: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color.primary.opacity(0.7))
            
            ZStack {
                Circle()
                    .stroke(lineWidth: 12)
                    .foregroundColor(color.opacity(0.1))
                
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(value / total) : 0)
                    .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .foregroundColor(color.opacity(0.6))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: value)
                
                VStack(spacing: 2) {
                    Text(formatBytes(value))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Color.primary.opacity(0.8))
                }
            }
            .frame(width: 100, height: 100)
            .padding(.vertical, 4)
            
            Button(action: action) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(buttonText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(disabledCondition ? Color.primary.opacity(0.3) : color.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 24)
            .background(
                Capsule()
                    .fill(Color.white.opacity(disabledCondition ? 0.3 : 0.6))
                    .shadow(color: color.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .disabled(isLoading || disabledCondition)
            .onHover { hovering in
                if hovering && !isLoading && !disabledCondition {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
        )
    }
    
    private var disabledCondition: Bool {
        title == "Cargo Weight" && value == 0
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    ContentView()
}
