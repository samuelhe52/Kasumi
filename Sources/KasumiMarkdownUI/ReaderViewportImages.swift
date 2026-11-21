import Foundation
import KasumiMarkdown

/// The installed viewport owns one local decode slot and four remote slots.
@MainActor final class ReaderViewportImages {
    private weak var snapshot: RenderedDocument?
    private var visible: [ReaderImageRegion] = []
    private var local: ArraySlice<ReaderImageRegion> = []
    private var remote: ArraySlice<ReaderImageRegion> = []
    private var loads: [UUID: (region: ReaderImageRegion, task: Task<Void, Never>)] = [:]

    deinit { for load in loads.values { load.task.cancel() } }

    func isTracking(_ rendered: RenderedDocument?) -> Bool { snapshot === rendered && !visible.isEmpty }

    func update(
        _ rendered: RenderedDocument, in viewport: CGRect, overscan: CGFloat, tableOffsets: [Int: CGFloat],
        invalidate: @escaping (ReaderImageRegion) -> Void, relayout: @escaping () -> Void
    ) {
        guard rendered.hasReaderImages else { stop(); return }
        let regions = rendered.readerImageRegions(in: viewport.insetBy(dx: 0, dy: -overscan), tableOffsets: tableOffsets)
        guard snapshot !== rendered || visible != regions else { return }
        let previous = snapshot === rendered ? visible : []
        snapshot = rendered
        visible = regions
        for (id, load) in loads where !regions.contains(where: { $0.sharesRaster(with: load.region) }) {
            load.task.cancel()
            loads.removeValue(forKey: id)
        }

        let tables = rendered.tables
        var nearLocal: [ReaderImageRegion] = []
        var nearRemote: [ReaderImageRegion] = []
        var farLocal: [ReaderImageRegion] = []
        var farRemote: [ReaderImageRegion] = []
        for region in regions {
            if rendered.hasReaderImageResult(for: region) {
                // A tile may have painted a placeholder before this cached image entered the viewport.
                if !previous.contains(region) { invalidate(region) }
                continue
            }
            let tableY = region.tableID.map { tables[$0].frame.minY } ?? 0
            let onScreen = region.rect.minY + tableY < viewport.maxY && region.rect.maxY + tableY > viewport.minY
            if region.isRemote {
                if onScreen { nearRemote.append(region) } else { farRemote.append(region) }
            } else if onScreen {
                nearLocal.append(region)
            } else {
                farLocal.append(region)
            }
        }
        nearLocal.append(contentsOf: farLocal)
        nearRemote.append(contentsOf: farRemote)
        local = nearLocal[...]
        remote = nearRemote[...]
        drain(invalidate: invalidate, relayout: relayout)
    }

    func stop() {
        snapshot = nil
        visible = []
        local = []
        remote = []
        for load in loads.values { load.task.cancel() }
        loads.removeAll()
    }

    private func drain(invalidate: @escaping (ReaderImageRegion) -> Void, relayout: @escaping () -> Void) {
        guard let snapshot else { return }
        if !loads.values.contains(where: { !$0.region.isRemote }) {
            _ = start(in: snapshot, remote: false, invalidate: invalidate, relayout: relayout)
        }
        var remoteCount = loads.values.reduce(into: 0) { if $1.region.isRemote { $0 += 1 } }
        while remoteCount < 4, start(in: snapshot, remote: true, invalidate: invalidate, relayout: relayout) {
            remoteCount += 1
        }
    }

    private func start(
        in snapshot: RenderedDocument, remote: Bool,
        invalidate: @escaping (ReaderImageRegion) -> Void, relayout: @escaping () -> Void
    ) -> Bool {
        while let region = remote ? self.remote.popFirst() : local.popFirst() {
            guard !snapshot.hasReaderImageResult(for: region),
                !loads.values.contains(where: { $0.region.sharesRaster(with: region) })
            else { continue }
            let id = UUID()
            let task = Task(priority: .userInitiated) { [weak self] in
                let result = await snapshot.prepareReaderResource(region)
                guard let self, self.loads.removeValue(forKey: id) != nil, !Task.isCancelled else { return }
                switch result {
                case .none: break
                case .pixels:
                    for occurrence in self.visible where occurrence.sharesRaster(with: region) { invalidate(occurrence) }
                case .geometry:
                    relayout()
                    return
                }
                self.drain(invalidate: invalidate, relayout: relayout)
            }
            loads[id] = (region, task)
            return true
        }
        return false
    }
}
