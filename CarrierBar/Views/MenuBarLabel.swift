import SwiftUI

/// What sits in the menu bar: "74° · 72°" once data arrives, a thermometer before that.
struct MenuBarLabel: View {
    let store: ThermostatStore

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if store.menuBarTitle != nil {
            // A menu bar label shows only one image, so the snowflake is drawn into it too.
            Image(nsImage: coloredTitleImage)
                .accessibilityLabel(accessibilityText)
        } else {
            Image(systemName: "snowflake")
                .accessibilityLabel("Carrier thermostats")
        }
    }

    /// The menu bar turns SwiftUI labels into template images, which drops any color.
    /// Rendering the temperatures into a non-template image keeps blue/orange per unit.
    private var coloredTitleImage: NSImage {
        let renderer = ImageRenderer(content: coloredTitle.environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false
        return image
    }

    private var coloredTitle: some View {
        HStack(spacing: 0) {
            Image(systemName: "snowflake")
                .foregroundStyle(.primary)
                .padding(.trailing, 4)
            ForEach(Array(store.thermostats.enumerated()), id: \.element.id) { index, thermostat in
                if index > 0 {
                    Text("·").foregroundStyle(.primary)
                }
                Text(DisplayFormat.temperature(thermostat.roomTemperature))
                    .foregroundStyle(color(for: thermostat.conditioning))
            }
        }
        .fixedSize()
        .font(Font(NSFont.menuBarFont(ofSize: 0)).monospacedDigit())
    }

    private func color(for conditioning: Thermostat.Conditioning) -> Color {
        switch conditioning {
        case .cooling: .blue
        case .heating: .orange
        case .idle, .unknown: .primary
        }
    }

    private var accessibilityText: String {
        store.thermostats
            .map { "\($0.name) \(DisplayFormat.temperature($0.roomTemperature))" }
            .joined(separator: ", ")
    }
}
