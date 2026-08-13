import SwiftUI

struct ContentView: View {
    @State private var viewModel = ContentViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(viewModel.title)
                .font(.largeTitle)
                .bold()
                .accessibilityIdentifier("AppTitleLabel")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
