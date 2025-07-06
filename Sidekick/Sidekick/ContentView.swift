import SwiftUI

// Define a struct for messages to provide a unique ID for ForEach
struct Message: Identifiable, Hashable {
    let id = UUID()
    let content: String
}

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var messages: [Message] = [] // Changed to array of Message structs
    @State private var conversationHistory: [[String: Any]] = [] // For Gemini's context

    // IMPORTANT: Replace "YOUR_GEMINI_API_KEY" with your actual API key.
    private let geminiClient = GeminiAPIClient(apiKey: "AIzaSyAqiug0s7LvcQBlRm2jNJpNqLx1fD58Opc")
    private let shellExecutor = ShellCommandExecutor()

    var body: some View {
        VStack {
            // Display area for messages
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(messages) { message in // Using default Identifiable id
                        Text(message.content) // Access content property
                            .padding(8)
                            .background(message.content.hasPrefix("You:") ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }

            // Input field and send button
            HStack {
                TextField("Ask Sidekick or run command (!cmd)", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }

    func sendMessage() {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if userMessage.isEmpty {
            return
        }

        messages.append(Message(content: "You: " + userMessage)) // Create Message object
        inputText = "" // Clear input immediately

        Task {
            if userMessage.starts(with: "!") {
                // It's a direct shell command
                let command = String(userMessage.dropFirst())
                do {
                    let output = try await shellExecutor.execute(command)
                    messages.append(Message(content: "Shell Output: " + (output.isEmpty ? "(empty output)" : output))) // Create Message object
                    // Do NOT send direct shell commands to Gemini for conversation
                } catch {
                    messages.append(Message(content: "Shell Error: \(error.localizedDescription)")) // Create Message object
                    print("Shell Command Error: \(error)")
                }
            } else {
                // It's a Gemini API query, potentially involving tool calls
                await handleGeminiQuery(userMessage)
            }
        }
    }

    private func handleGeminiQuery(_ query: String) async {
        do {
            // Add user message to conversation history for Gemini
            conversationHistory.append(["role": "user", "parts": [["text": query]]])

            let response = try await geminiClient.generateContent(prompt: query, history: conversationHistory)

            switch response {
            case .text(let textResponse):
                messages.append(Message(content: "Sidekick: " + textResponse)) // Create Message object
                // Add Gemini's text response to history
                conversationHistory.append(["role": "model", "parts": [["text": textResponse]]])

            case .toolCall(let name, let args):
                messages.append(Message(content: "Sidekick: (Executing tool: \(name) with args: \(args))")) // Create Message object
                if name == "execute_shell_command", let command = args["command"] as? String {
                    do {
                        let toolOutput = try await shellExecutor.execute(command)
                        messages.append(Message(content: "Tool Output: " + (toolOutput.isEmpty ? "(empty output)" : toolOutput))) // Create Message object

                        // CORRECTED: Send tool output back to Gemini as part of the conversation
                        conversationHistory.append([
                            "role": "function",
                            "parts": [
                                [
                                    "functionResponse": [
                                        "name": name,
                                        "response": [
                                            "result": toolOutput // API expects a dictionary for response
                                        ]
                                    ]
                                ]
                            ]
                        ])

                        // Get Gemini's final response based on tool output
                        await handleGeminiQuery("continue") // Send a dummy prompt to get Gemini to continue

                    } catch {
                        let errorMsg = "Tool Error: \(error.localizedDescription)"
                        messages.append(Message(content: errorMsg)) // Create Message object
                        // Send error back to Gemini
                        conversationHistory.append([
                            "role": "function",
                            "parts": [
                                [
                                    "functionResponse": [
                                        "name": name,
                                        "response": [
                                            "error": errorMsg
                                        ]
                                    ]
                                ]
                            ]
                        ])
                        await handleGeminiQuery("continue") // Send a dummy prompt to get Gemini to continue
                    }
                } else {
                    let errorMsg = "Sidekick: Unknown tool or invalid arguments: \(name) \(args)"
                    messages.append(Message(content: errorMsg)) // Create Message object
                    // Send error back to Gemini
                    conversationHistory.append([
                        "role": "function",
                        "parts": [
                            [
                                "functionResponse": [
                                    "name": name,
                                    "response": [
                                        "error": errorMsg
                                    ]
                                ]
                            ]
                        ]
                    ])
                    await handleGeminiQuery("continue") // Send a dummy prompt to get Gemini to continue
                }
            }
        } catch {
            messages.append(Message(content: "Sidekick Error: \(error.localizedDescription)")) // Create Message object
            print("Gemini API Error: \(error)")
        }
    }
}
