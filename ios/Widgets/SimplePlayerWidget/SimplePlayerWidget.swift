import WidgetKit
import SwiftUI
import home_widget

struct SimplePlayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimplePlayerEntry {
        SimplePlayerEntry(
            title: "TS Music",
            artist: "Not playing",
            isPlaying: false,
            isOnline: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimplePlayerEntry) -> ()) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimplePlayerEntry>) -> ()) {
        let entry = loadEntry()
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }

    private func loadEntry() -> SimplePlayerEntry {
        let data = HomeWidgetPlugin.getData()
        let title = data?["widget_title"] as? String ?? "TS Music"
        let artist = data?["widget_artist"] as? String ?? "Not playing"
        let isPlaying = data?["widget_is_playing"] as? Bool ?? false
        let isOnline = data?["widget_is_online"] as? Bool ?? false
        let primaryColor = data?["widget_primary_color"] as? Int ?? 0x1DB954
        return SimplePlayerEntry(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            isOnline: isOnline,
            primaryColor: primaryColor
        )
    }
}

struct SimplePlayerEntry: TimelineEntry {
    let date = Date()
    let title: String
    let artist: String
    let isPlaying: Bool
    let isOnline: Bool
    let primaryColor: Int
}

struct SimplePlayerWidgetEntryView : View {
    var entry: SimplePlayerProvider.Entry

    private var accentColor: Color {
        let r = Double((entry.primaryColor >> 16) & 0xFF) / 255.0
        let g = Double((entry.primaryColor >> 8) & 0xFF) / 255.0
        let b = Double(entry.primaryColor & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !entry.isOnline {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }
            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundColor(accentColor)
            if !entry.isOnline {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct SimplePlayerWidget: Widget {
    let kind: String = "SimplePlayerWidgetProvider"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimplePlayerProvider()) { entry in
            SimplePlayerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TS Music Player")
        .description("Control your music from the home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
