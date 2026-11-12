import SwiftUI
import UIKit

/// Presents Now Playing from UIKit the way Apple Music does (traced on iOS 27.2, see docs/original-app-analysis.md):
///
/// - **Open**: Music's own animator. The card grows out of the mini player on a critically damped spring (mass 1,
///   stiffness 333.33, damping 36.51; response 0.344 s, no overshoot), starting as Liquid Glass and filling in with the
///   player, with its content scaled to the card's width. Behind it the app only dims (black, ~12%); nothing behind
///   moves, blurs or bounces. (The system zoom transition's open overshoots and ramps a blur over the page.)
/// - **Close**: handed to the system zoom transition from the mini player, which morphs the card into the bar's
///   Liquid Glass with the system's landing bounce, exactly as before.
@MainActor
@Observable
final class NowPlayingPresenter: NSObject {
    static let shared = NowPlayingPresenter()

    /// True while Now Playing is open (the player idles while it's closed).
    private(set) var isPresented = false

    private var presented: UIHostingController<AnyView>?
    private var openAnimator = OpenAnimator()
    /// Built once and reused, already laid out, so opening doesn't wait for the player to be created (a visible
    /// stall on slower devices).
    private var cached: UIHostingController<AnyView>?

    private func controller() -> UIHostingController<AnyView> {
        if let cached { return cached }
        let content = AnyView(NowPlayingPresentation()
            .environment(AudioPlayer.shared)
            .environment(DownloadStore.shared)
            .environment(BookmarkStore.shared)
            .environment(NetworkMonitor.shared))
        let vc = UIHostingController(rootView: content)
        // Insets come from the window (see NowPlayingPresentation), not from the view's scaled frame.
        vc.safeAreaRegions = []
        vc.view.backgroundColor = .clear
        // Apple Music's presentation (traced 2026-11-12): a form sheet made full screen with the sheet controller's
        // private `wantsFullScreen`, not `.overFullScreen`. With `.overFullScreen` the zoom close treats the page
        // behind as pushed back and springs it out (the page jumped ~13 pt and slid back); as Music's sheet it stays.
        vc.modalPresentationStyle = .formSheet
        configureSheet(vc)
        cached = vc
        return vc
    }

    private func configureSheet(_ vc: UIViewController) {
        guard let sheet = vc.sheetPresentationController else { return }
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = false
        // `-[UISheetPresentationController _setWantsFullScreen:]`, set by KVC; Music has it on.
        let selector = NSSelectorFromString("_setWantsFullScreen:")
        if sheet.responds(to: selector) { sheet.setValue(true, forKey: "wantsFullScreen") }
    }

    /// Builds and lays out Now Playing ahead of time (call once the app is showing).
    func prepare() {
        guard cached == nil, let window else { return }
        let vc = controller()
        vc.view.frame = window.bounds
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
    }

    /// The controller while its close is still running (UIKit won't present it again until that has finished).
    private var dismissing: UIHostingController<AnyView>?
    /// What was last asked for; an open asked for during a close happens when the close finishes.
    private var wantsShow = false

    /// Shows or hides Now Playing to match `show`.
    func update(show: Bool) {
        wantsShow = show
        if show { present() } else { dismiss() }
    }

    private var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }

    private var root: UIViewController? {
        var vc = window?.rootViewController
        while let next = vc?.presentedViewController, next !== presented { vc = next }
        return vc
    }

    /// The mini player's glass container in the tab bar (the source the card grows from and lands in).
    func accessoryView() -> UIView? {
        guard let window else { return nil }
        var stack: [UIView] = [window]
        while let v = stack.popLast() {
            if String(describing: type(of: v)).contains("TabAccessoryContainer") { return v }
            stack.append(contentsOf: v.subviews)
        }
        return nil
    }

    private func present() {
        // Reopened while the last close is still landing: presenting the same controller then makes UIKit throw
        // (it ran the deferred present inside the close's completion and crashed). Open once it has finished.
        guard presented == nil, dismissing == nil, let root else { return }
        let vc = controller()
        guard vc.presentingViewController == nil else { return }
        vc.preferredTransition = nil
        vc.modalPresentationStyle = .formSheet
        configureSheet(vc)
        vc.transitioningDelegate = self
        openAnimator.source = accessoryView()?.convert(accessoryView()?.bounds ?? .zero, to: nil)
        presented = vc
        isPresented = true
        root.present(vc, animated: true)
    }

    private func dismiss() {
        guard let vc = presented else { return }
        presented = nil
        isPresented = false
        // The close is the system zoom transition into the bar (its Liquid Glass landing).
        vc.transitioningDelegate = nil
        let options = UIViewController.Transition.ZoomOptions()
        options.dimmingColor = .black.withAlphaComponent(0.12)
        options.dimmingVisualEffect = nil
        vc.preferredTransition = .zoom(options: options) { [weak self] _ in self?.accessoryView() }
        dismissing = vc
        vc.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.dismissing = nil
            if self.wantsShow { self.present() }
        }
    }

}

extension NowPlayingPresenter: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        openAnimator
    }
}

/// Apple Music's open: card from the bar's frame to full screen on its spring, content scaled with the card's width,
/// glass first, flat dim behind.
@MainActor
private final class OpenAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    var source: CGRect?

    /// Music's spring: mass 1, stiffness 333.33, damping 36.51 (critically damped, response 0.344 s).
    static let spring = UISpringTimingParameters(mass: 1, stiffness: 333.3333, damping: 36.5148, initialVelocity: .zero)

    nonisolated func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.51 }

    nonisolated func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        MainActor.assumeIsolated { run(ctx) }
    }

    private func run(_ ctx: UIViewControllerContextTransitioning) {
        guard let toView = ctx.view(forKey: .to), let toVC = ctx.viewController(forKey: .to) else { ctx.completeTransition(false); return }
        let container = ctx.containerView
        let full = ctx.finalFrame(for: toVC).isEmpty ? container.bounds : ctx.finalFrame(for: toVC)
        let start = source.map { container.convert($0, from: nil) }
            ?? CGRect(x: full.minX + 16, y: full.maxY - 110, width: full.width - 32, height: 48)

        // Flat dim behind (Music's UIDimmingView), no blur.
        let dim = UIView(frame: container.bounds)
        dim.backgroundColor = .black
        dim.alpha = 0
        container.addSubview(dim)

        // The card: a clipping view that grows from the bar, glass underneath, the player scaled to its width.
        let card = UIView(frame: start)
        card.clipsToBounds = true
        card.layer.cornerCurve = .continuous
        card.layer.cornerRadius = start.height / 2
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.frame = card.bounds
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        card.addSubview(glass)
        container.addSubview(card)

        // A view controller's view resizes with its parent by default; inside the growing card that made the player
        // grow by the card's growth on top of its full size (SwiftUI laid it out too tall, contents off the card).
        let mask = toView.autoresizingMask
        toView.autoresizingMask = []
        toView.frame = full
        toView.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        let s0 = start.width / max(1, full.width)
        toView.transform = CGAffineTransform(scaleX: s0, y: s0)
        toView.center = CGPoint(x: start.width / 2, y: 0)
        card.addSubview(toView)
        // The glass sits over the player and fades off it (fading the player itself in left SwiftUI not drawing its
        // contents until the transition ended).
        card.bringSubviewToFront(glass)

        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: Self.spring)
        animator.addAnimations {
            card.frame = full
            card.layer.cornerRadius = 0
            toView.transform = .identity
            toView.center = CGPoint(x: full.width / 2, y: 0)
            dim.alpha = 0.12
        }
        // The player fills in over the glass quickly, as Music's content does.
        UIView.animate(withDuration: 0.12, delay: 0.03, options: [.curveEaseOut]) { glass.alpha = 0 }
        animator.addCompletion { _ in
            // Hand the presented view back to the container at full screen; drop the scaffolding.
            toView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            toView.transform = .identity
            toView.frame = full
            toView.autoresizingMask = mask
            container.addSubview(toView)
            card.removeFromSuperview()
            dim.removeFromSuperview()
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
