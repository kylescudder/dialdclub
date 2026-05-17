import Lottie
import SwiftUI

struct LottieAnimationView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let view = Lottie.LottieAnimationView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.loopMode = loopMode
        view.backgroundBehavior = .pauseAndRestore
        if let animation = loadAnimation() {
            view.animation = animation
            view.play()
        }
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView.subviews.first as? Lottie.LottieAnimationView else { return }
        view.loopMode = loopMode
        if !view.isAnimationPlaying { view.play() }
    }

    private func loadAnimation() -> LottieAnimation? {
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            return LottieAnimation.filepath(url.path)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Animations") {
            return LottieAnimation.filepath(url.path)
        }
        return LottieAnimation.named(name)
    }
}
