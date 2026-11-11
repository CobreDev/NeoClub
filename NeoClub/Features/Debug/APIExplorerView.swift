import SwiftUI

/// Development screen for poking at endpoints and viewing raw JSON.
struct APIExplorerView: View {
    @Environment(AppModel.self) private var app
    @State private var method = "GET"
    @State private var path = "/viewer"
    @State private var query = ""
    @State private var body_ = ""
    @State private var output = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    Picker("Method", selection: $method) {
                        ForEach(["GET", "POST", "PUT"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Path", text: $path).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Query (a=1&b=2)", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("JSON body", text: $body_, axis: .vertical).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("X-VIEWER-ID", text: Binding(
                        get: { APIClient.shared.viewerID ?? "" },
                        set: { APIClient.shared.viewerID = $0.isEmpty ? nil : $0 }))
                    Button(loading ? "Sending…" : "Send") { Task { await send() } }.disabled(loading)
                }
                Section("Response") {
                    Text(output).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            .navigationTitle("API Explorer")
            .toolbar { Button("Sign Out") { Task { await app.signOut() } } }
        }
    }

    private func send() async {
        loading = true
        defer { loading = false }
        var q: [String: String?] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { q[kv[0]] = kv[1] }
        }
        do {
            let data = try await APIClient.shared.raw(method, path, query: q, body: body_.isEmpty ? nil : Data(body_.utf8))
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                output = String(decoding: pretty, as: UTF8.self)
            } else {
                output = String(decoding: data, as: UTF8.self)
            }
        } catch {
            output = error.localizedDescription
        }
    }
}
