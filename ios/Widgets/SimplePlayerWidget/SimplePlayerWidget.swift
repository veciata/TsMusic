import WidgetKit
import SwiftUI
import home_widget

struct SimplePlayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimplePlayerEntry {
        SimplePlayerEntry(
            title: "TS Music",
            artist: "Not playing",
            isPlaying: false
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
        return SimplePlayerEntry(title: title, artist: artist, isPlaying: isPlaying)
    }
}

struct SimplePlayerEntry: TimelineEntry {
    let date = Date()
    let title: String
    let artist: String
    let isPlaying: Bool
}

struct SimplePlayerWidgetEntryView : View {
    var entry: SimplePlayerProvider.Entry

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
            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Image(systemName: "forward.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
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
