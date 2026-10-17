/// Splits `totalCount` rows into pages of `pageSize`, numbered from 0. There's always at
/// least one page, so an empty list still has a page to show.
public struct Pagination: Equatable, Sendable {
    public let pageSize: Int
    public let totalCount: Int

    public init(pageSize: Int, totalCount: Int) {
        self.pageSize = max(1, pageSize)
        self.totalCount = max(0, totalCount)
    }

    public var pageCount: Int { max(1, (totalCount + pageSize - 1) / pageSize) }

    /// `page` limited to the pages that exist — rows can be purged while a later page shows.
    public func clamped(_ page: Int) -> Int { min(max(page, 0), pageCount - 1) }

    /// The number of rows before `page`, for a query's `OFFSET`.
    public func offset(of page: Int) -> Int { clamped(page) * pageSize }

    public func hasPrevious(_ page: Int) -> Bool { clamped(page) > 0 }

    public func hasNext(_ page: Int) -> Bool { clamped(page) < pageCount - 1 }

    /// Which rows `page` shows, e.g. "11–20 of 23".
    public func rangeLabel(of page: Int) -> String {
        guard totalCount > 0 else { return "0 of 0" }
        let first = offset(of: page) + 1
        let last = min(first + pageSize - 1, totalCount)
        return "\(first)–\(last) of \(totalCount)"
    }
}
