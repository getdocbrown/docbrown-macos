import Foundation

public struct PullRequestSummary: Identifiable, Sendable {
    public var id: String { url }
    public var url: String
    public var title: String
    public var repository: String
    public var number: Int
    public var updated: String
    public var hasGitHubDate: Bool
    public var state: String
    public var authored: Bool
    public var contributed: Bool
    public var reviewed: Bool
    public var commented: Bool
    public var inferred: Bool
    public var organization: String { String(repository.split(separator: "/").first ?? "") }
    public var isInvolved: Bool { authored || contributed || reviewed || commented }
    public var involvement: [String] {
        var labels: [String] = []
        if authored { labels.append("Created by you") }
        if contributed { labels.append("Code contributed") }
        if reviewed { labels.append("Reviewed by you") }
        if commented { labels.append("Commented by you") }
        return labels.isEmpty ? [inferred ? "Branch match" : "Mentioned"] : labels
    }
    public static func filtered(_ items: [Self], includeReferences: Bool, organization: String = "", repository: String = "") -> [Self] {
        items.filter {
            (includeReferences || $0.isInvolved) && (organization.isEmpty || $0.organization == organization)
                && (repository.isEmpty || $0.repository == repository)
        }.sorted {
            if $0.updated != $1.updated { return $0.updated > $1.updated }
            if $0.number != $1.number { return $0.number > $1.number }
            return $0.url < $1.url
        }
    }
}

extension HistoryStore {
    /// Accepts either GitHub CLI JSON or the REST commit-to-PR response.
    public func recordPullRequest(_ pr: [String: Any], viewer: String, reviewed: Bool = false, commented: Bool = false) throws {
        guard let url = (pr["url"] as? String).flatMap({ $0.hasPrefix("https://github.com/") ? $0 : nil }) ?? pr["html_url"] as? String else { return }
        let author = (pr["author"] as? [String: Any])?["login"] as? String ?? (pr["user"] as? [String: Any])?["login"] as? String ?? ""
        let created = pr["createdAt"] as? String ?? pr["created_at"] as? String ?? ""
        let updated = pr["updatedAt"] as? String ?? pr["updated_at"] as? String ?? ""
        try execute("""
        INSERT INTO pull_requests VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(url) DO UPDATE SET
          title=CASE WHEN excluded.title<>'' THEN excluded.title ELSE pull_requests.title END,
          author=CASE WHEN excluded.author<>'' THEN excluded.author ELSE pull_requests.author END,
          state=CASE WHEN excluded.state<>'' THEN excluded.state ELSE pull_requests.state END,
          created_at=CASE WHEN excluded.created_at<>'' THEN excluded.created_at ELSE pull_requests.created_at END,
          updated_at=CASE WHEN excluded.updated_at<>'' THEN excluded.updated_at ELSE pull_requests.updated_at END,
          viewer=CASE WHEN excluded.viewer<>'' THEN excluded.viewer ELSE pull_requests.viewer END,
          authored=CASE WHEN excluded.viewer='' THEN pull_requests.authored WHEN excluded.author='' AND pull_requests.viewer=excluded.viewer THEN pull_requests.authored ELSE excluded.authored END,
          reviewed=CASE WHEN excluded.viewer='' THEN pull_requests.reviewed WHEN pull_requests.viewer=excluded.viewer THEN MAX(pull_requests.reviewed,excluded.reviewed) ELSE excluded.reviewed END,
          commented=CASE WHEN excluded.viewer='' THEN pull_requests.commented WHEN pull_requests.viewer=excluded.viewer THEN MAX(pull_requests.commented,excluded.commented) ELSE excluded.commented END
        """, [url, pr["title"] as? String ?? "", author, pr["state"] as? String ?? "", created, updated, viewer,
               !viewer.isEmpty && author.lowercased() == viewer.lowercased() ? 1 : 0, reviewed ? 1 : 0, commented ? 1 : 0])
    }

    public func pullRequestSummaries(includeInternal: Bool = false) throws -> [PullRequestSummary] {
        let result = try rows("""
        WITH visible_links AS (
          SELECT a.value AS url,a.title AS link_title,a.confidence,s.updated AS session_updated
          FROM associations a JOIN sessions s ON s.id=a.session_id
          WHERE a.kind='pr' \(includeInternal ? "" : "AND s.source_kind<>'internal'")
        ), candidates AS (
          SELECT url FROM visible_links UNION
          SELECT url FROM pull_requests WHERE authored=1 OR reviewed=1 OR commented=1
        )
        SELECT c.url,a.link_title,a.confidence,a.session_updated,
               p.title,p.state,p.created_at,p.updated_at,p.authored,p.reviewed,p.commented
        FROM candidates c LEFT JOIN visible_links a ON a.url=c.url
        LEFT JOIN pull_requests p ON p.url=c.url
        """)
        return Dictionary(grouping: result, by: { $0["url"] ?? "" }).compactMap { url, links in
            guard let parsed = URL(string: url), parsed.host == "github.com" else { return nil }
            let parts = parsed.pathComponents.filter { $0 != "/" }
            guard parts.count == 4, parts[2] == "pull", let number = Int(parts[3]), let row = links.first else { return nil }
            let githubDate = [row["updated_at"] ?? "", row["created_at"] ?? ""].first { !$0.isEmpty } ?? ""
            let title = row["title"].flatMap { $0.isEmpty ? nil : $0 }
                ?? links.sorted { ($0["confidence"] == "Confirmed" ? 0 : 1) < ($1["confidence"] == "Confirmed" ? 0 : 1) }.first?["link_title"] ?? "PR #\(number)"
            return PullRequestSummary(url: url, title: title, repository: "\(parts[0])/\(parts[1])", number: number,
                updated: githubDate.isEmpty ? links.compactMap { $0["session_updated"] }.max() ?? "" : githubDate,
                hasGitHubDate: !githubDate.isEmpty, state: row["state"] ?? "",
                authored: row["authored"] == "1", contributed: links.contains { $0["confidence"] == "Confirmed" },
                reviewed: row["reviewed"] == "1", commented: row["commented"] == "1",
                inferred: links.contains { $0["confidence"] == "Inferred" })
        }
    }
}
