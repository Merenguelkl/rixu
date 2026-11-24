import CoreGraphics

enum DockEdge: String {
    case bottom, left, right

    func distance(to point: CGPoint, inside screen: CGRect) -> CGFloat {
        switch self {
        case .bottom: point.y - screen.minY
        case .left: point.x - screen.minX
        case .right: screen.maxX - point.x
        }
    }

    func reservedSpace(screen: CGRect, workArea: CGRect) -> CGFloat {
        switch self {
        case .bottom: workArea.minY - screen.minY
        case .left: workArea.minX - screen.minX
        case .right: screen.maxX - workArea.maxX
        }
    }
}

struct DockPlacement {
    let edge: DockEdge
    let screen: CGRect
    let workArea: CGRect
    let tileSize: CGFloat
    var magnifiedTileSize: CGFloat = 0

    func contains(_ point: CGPoint) -> Bool {
        let depth = max(edge.reservedSpace(screen: screen, workArea: workArea) + 4,
                        max(tileSize, magnifiedTileSize) + 16)
        return screen.contains(point) && edge.distance(to: point, inside: screen) <= depth
    }

    func frame(near point: CGPoint) -> CGRect {
        let click = contains(point) ? point : nil
        let visibleDock = edge.reservedSpace(screen: screen, workArea: workArea)
        let dockDepth = if let click {
            max(visibleDock, edge.distance(to: click, inside: screen) + 16,
                visibleDock < tileSize * 0.75 ? tileSize + 8 : 0)
        } else {
            max(visibleDock, tileSize + 8)
        }

        var area = workArea
        switch edge {
        case .bottom:
            let lowerEdge = max(area.minY, screen.minY + dockDepth)
            area = CGRect(x: area.minX, y: lowerEdge, width: area.width, height: area.maxY - lowerEdge)
        case .left:
            let leadingEdge = max(area.minX, screen.minX + dockDepth)
            area = CGRect(x: leadingEdge, y: area.minY, width: area.maxX - leadingEdge, height: area.height)
        case .right:
            area.size.width = min(area.width, screen.maxX - dockDepth - area.minX)
        }
        return PanelPlacement.dock(edge, alignment: click, in: area)
    }
}

enum PanelPlacement {
    private static let panelSize = CGSize(width: 388, height: 562)
    private static let gap: CGFloat = 8

    static func menuBar(anchor: CGRect, in workArea: CGRect) -> CGRect {
        let area = workArea.insetBy(dx: gap, dy: gap)
        let hasAnchor = anchor.midY >= workArea.maxY - 48
            && anchor.midX >= workArea.minX && anchor.midX <= workArea.maxX
        let top = hasAnchor ? min(anchor.minY - gap, area.maxY) : area.maxY
        let center = hasAnchor ? anchor.midX : area.maxX - 40
        let size = CGSize(width: min(panelSize.width, area.width),
                          height: min(panelSize.height, top - area.minY))
        return CGRect(x: clamped(center - size.width / 2, to: area.minX...(area.maxX - size.width)),
                      y: top - size.height, width: size.width, height: size.height)
    }

    static func dock(_ edge: DockEdge, alignment: CGPoint?, in workArea: CGRect) -> CGRect {
        let area = workArea.insetBy(dx: gap, dy: gap)
        let size = CGSize(width: min(panelSize.width, area.width), height: min(panelSize.height, area.height))
        let x = (alignment?.x ?? area.midX) - size.width / 2
        let y = (alignment?.y ?? area.midY) - size.height / 2
        let origin: CGPoint
        switch edge {
        case .bottom:
            origin = CGPoint(x: clamped(x, to: area.minX...(area.maxX - size.width)), y: area.minY)
        case .left:
            origin = CGPoint(x: area.minX, y: clamped(y, to: area.minY...(area.maxY - size.height)))
        case .right:
            origin = CGPoint(x: area.maxX - size.width, y: clamped(y, to: area.minY...(area.maxY - size.height)))
        }
        return CGRect(origin: origin, size: size)
    }

    private static func clamped(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
