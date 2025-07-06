 import SwiftUI

 @main
 struct SidekickApp: App {
     var body: some Scene {
         MenuBarExtra("Sidekick", systemImage: "sparkle") {
             ContentView()
         }
         .menuBarExtraStyle(.window)
     }
 }
