import SwiftUI

/// "Who's listening?" screen in AIO navy with the honeycomb pattern and club logo.
struct ProfilePickerView: View {
    @Environment(AppModel.self) private var app
    @State private var pinProfile: Profile?

    // Two columns on iPhone, more on iPad; each cell sized so names never collide.
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                BrandImage(name: "club_logo_2026")
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .padding(.top, 24)
                Text("Who's listening?")
                    .font(.jacoby(32))
                    .foregroundStyle(.white)
                if let error = app.profileError {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await app.loadProfiles() } }
                            .aioPrimaryButton()
                    }
                }
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(app.profiles) { profile in
                        Button {
                            if profile.hasPIN { pinProfile = profile } else { app.activate(profile, pin: nil) }
                        } label: {
                            ProfileBadge(profile: profile, size: 104, isCurrent: profile.id == app.profile?.id)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(profile.displayName + (profile.hasPIN ? ", PIN protected" : ""))
                        .accessibilityAddTraits(profile.id == app.profile?.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 24)
                Button("Sign Out") { Task { await app.signOut() } }
                    .font(.univers(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Backdrop in .background so it can never widen the layout.
        .background { AIOBackdrop() }
        .overlay(alignment: .topTrailing) {
            // Opened from Account with a profile already active: allow backing out without switching.
            if app.profile != nil {
                Button("Cancel") { app.phase = .ready }
                    .font(.universBold(17))
                    .buttonStyle(.glass)
                    .padding(.trailing, 20)
                    .padding(.top, 8)
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

/// Navy backdrop with the AIO honeycomb texture (tiled, so it never affects layout size).
struct AIOBackdrop: View {
    var body: some View {
        LinearGradient(colors: [.aioDeepNavy, .aioOcean], startPoint: .top, endPoint: .bottom)
            .overlay {
                if let honeycomb = UIImage(named: "honeycomb") {
                    Image(uiImage: honeycomb).resizable(resizingMode: .tile).opacity(0.05).blendMode(.screen)
                }
            }
            .ignoresSafeArea()
    }
}

struct ProfileBadge: View {
    let profile: Profile
    var size: CGFloat = 104
    var showsName = true
    var isCurrent = false

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
            .overlay(Circle().stroke(isCurrent ? Color.aioYellow : .white.opacity(0.85), lineWidth: isCurrent ? 4 : (size > 50 ? 3 : 1.5)))
            .shadow(color: .black.opacity(0.25), radius: size > 50 ? 8 : 2, y: size > 50 ? 4 : 1)
            if showsName { HStack(spacing: 4) {
                Text(profile.displayName)
                    .font(.universBold(17))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if profile.hasPIN { Image(systemName: "lock.fill").font(.caption).opacity(0.8) }
            }
            .foregroundStyle(isCurrent ? Color.aioYellow : .white)
            .frame(maxWidth: size + 40)
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
