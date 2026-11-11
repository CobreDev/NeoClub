import SwiftUI

/// "Who's listening?" screen in AIO navy with the honeycomb pattern and club logo.
struct ProfilePickerView: View {
    @Environment(AppModel.self) private var app
    @State private var pinProfile: Profile?

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 24)]

    var body: some View {
        ZStack {
            AIOBackdrop()
            ScrollView {
                VStack(spacing: 28) {
                    BrandImage(name: "club_logo_2026")
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .padding(.top, 40)
                    Text("Who's listening?")
                        .font(.jacoby(34))
                        .foregroundStyle(.white)
                    if let error = app.profileError {
                        VStack(spacing: 12) {
                            Text(error).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                            Button("Try Again") { Task { await app.loadProfiles() } }
                                .buttonStyle(.glassProminent)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(app.profiles) { profile in
                            Button {
                                if profile.hasPIN { pinProfile = profile } else { app.activate(profile, pin: nil) }
                            } label: {
                                ProfileBadge(profile: profile, size: 104)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    Button("Sign Out") { Task { await app.signOut() } }
                        .font(.univers(15))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 12)
                }
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $pinProfile) { profile in
            PINEntryView(profile: profile) { pin in
                pinProfile = nil
                app.activate(profile, pin: pin)
            }
            .presentationDetents([.medium])
        }
    }
}

/// Navy backdrop with the AIO honeycomb texture.
struct AIOBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.aioDeepNavy, .aioOcean], startPoint: .top, endPoint: .bottom)
            BrandImage(name: "honeycomb")
                .scaledToFill()
                .opacity(0.08)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

struct ProfileBadge: View {
    let profile: Profile
    var size: CGFloat = 104
    var showsName = true

    private static let palette: [Color] = [.aioBlue, .aioYellow, .aioRed, .aioSky, .aioOcean]

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Self.palette[profile.viewerID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.palette.count].gradient)
                if let url = profile.pictureURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initials }
                        .clipShape(Circle())
                } else {
                    initials
                }
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: size > 50 ? 3 : 1.5))
            .shadow(color: .black.opacity(0.25), radius: size > 50 ? 8 : 2, y: size > 50 ? 4 : 1)
            if showsName { HStack(spacing: 4) {
                Text(profile.displayName)
                    .font(.universBold(17))
                    .lineLimit(1)
                if profile.hasPIN { Image(systemName: "lock.fill").font(.caption) }
            }
            .foregroundStyle(.white)
            }
        }
    }

    private var initials: some View {
        Text(String(profile.displayName.prefix(1)).uppercased())
            .font(.jacoby(size * 0.45))
            .foregroundStyle(.white)
    }
}

struct PINEntryView: View {
    let profile: Profile
    let onVerified: (String) -> Void
    @State private var pin = ""
    @State private var checking = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter PIN for \(profile.displayName)")
                .font(.universBold(20))
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding()
                .background(.quaternary, in: .rect(cornerRadius: 14))
                .focused($focused)
                .frame(maxWidth: 220)
            if failed { Text("That PIN didn't work.").foregroundStyle(.red).font(.callout) }
            Button {
                Task {
                    checking = true
                    let ok = await AIOService.verifyPIN(pin, for: profile.viewerID)
                    checking = false
                    if ok { onVerified(pin) } else { failed = true; pin = "" }
                }
            } label: {
                Group { if checking { ProgressView() } else { Text("Continue") } }
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.glassProminent)
            .disabled(pin.count < 4 || checking)
        }
        .padding(32)
        .onAppear { focused = true }
    }
}
