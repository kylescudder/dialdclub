import SwiftUI

struct AILabLogo: View {
    let lab: AILab
    var size: CGFloat = 34

    var body: some View {
        Group {
            switch lab.id {
            case "openai":
                Image("OpenAIBlossom")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .background(.white, in: tile)
            case "anthropic":
                Image("AnthropicLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .background(.white, in: tile)
            case "google":
                Image("GoogleLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .background(.white, in: tile)
            default:
                Text(monogram)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(4)
                    .background(Theme.Colors.surfaceElevated, in: tile)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
    }

    private var monogram: String {
        switch lab.id {
        case "xai": "x"
        case "meta": "M"
        case "mistral": "Mi"
        case "deepseek": "DS"
        case "cohere": "Co"
        case "ai21": "21"
        case "qwen": "Q"
        case "moonshot": "K"
        case "minimax": "MM"
        case "perplexity": "P"
        case "bedrock": "AWS"
        case "azure": "AZ"
        case "groq": "Gq"
        case "together": "T"
        case "fireworks": "Fw"
        case "nvidia": "N"
        case "openrouter": "OR"
        default: "AI"
        }
    }
}

struct AIProviderLogo: View {
    let provider: AIProvider
    var size: CGFloat = 32

    var body: some View {
        AILabLogo(
            lab: provider == .openAI
                ? AILab.fallback.first { $0.provider == .openAI }!
                : AILab.fallback.first { $0.provider == .anthropic }!,
            size: size
        )
    }
}
