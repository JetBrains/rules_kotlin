import Shared
import SwiftUI

/// Shows the greeting of the shared code, then the one it gives a moment later: Swift calls the
/// suspending Kotlin function greetLater() as an async function.
struct ContentView: View {
  @State private var greeting = Greeting().greet()

  var body: some View {
    Text(greeting)
      .task {
        greeting = (try? await Greeting().greetLater()) ?? greeting
      }
  }
}
