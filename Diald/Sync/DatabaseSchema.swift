import Foundation
import PowerSync

/// Local SQLite schema for data that must remain available without a network.
/// PowerSync adds each table's `id` column automatically.
enum DatabaseSchema {
    static let profiles = Table(
        name: "profiles",
        columns: [
            .text("username"),
            .text("display_name"),
            .text("created_at"),
            .text("updated_at"),
            .text("deleted_at"),
        ]
    )

    static let beans = Table(
        name: "beans",
        columns: [
            .text("owner_id"),
            .text("name"),
            .text("roaster"),
            .text("origin"),
            .text("process"),
            .text("variety"),
            .text("roast_level"),
            .text("roast_date"),
            .text("tasting_notes"),
            .text("archived_at"),
            .text("created_at"),
            .text("updated_at"),
            .text("deleted_at"),
        ],
        indexes: [
            Index(
                name: "beans_owner_updated",
                columns: [
                    IndexedColumn.ascending("owner_id"),
                    IndexedColumn.descending("updated_at"),
                ]
            ),
        ]
    )

    static let brewSessions = Table(
        name: "brew_sessions",
        columns: [
            .text("owner_id"),
            .text("bean_id"),
            .text("method"),
            .text("title"),
            .real("dose_grams"),
            .real("yield_grams"),
            .real("water_grams"),
            .text("grind_setting"),
            .real("water_temperature_c"),
            .integer("extraction_seconds"),
            .integer("rating"),
            .integer("acidity"),
            .integer("sweetness"),
            .integer("body"),
            .integer("clarity"),
            .text("notes"),
            .text("brewed_at"),
            .text("created_at"),
            .text("updated_at"),
            .text("deleted_at"),
        ],
        indexes: [
            Index(
                name: "brew_sessions_owner_brewed",
                columns: [
                    IndexedColumn.ascending("owner_id"),
                    IndexedColumn.descending("brewed_at"),
                ]
            ),
        ]
    )

    /// Read-only server state. The app never writes either table locally.
    static let extractionCreationQuotas = Table(
        name: "extraction_creation_quotas",
        columns: [
            .integer("lifetime_count"),
            .text("updated_at"),
        ]
    )

    static let iapEntitlements = Table(
        name: "iap_entitlements",
        columns: [
            .text("product_id"),
            .text("bundle_id"),
            .text("original_transaction_id"),
            .text("transaction_id"),
            .text("status"),
            .text("expires_at"),
            .text("revoked_at"),
            .text("environment"),
            .text("signed_at"),
            .text("verified_at"),
            .text("verification_source"),
            .text("updated_at"),
        ]
    )

    /// Device-only ledger used to reserve free allowance while creations are
    /// waiting in PowerSync's upload queue.
    static let pendingExtractions = Table(
        name: "pending_extractions",
        columns: [
            .text("user_id"),
            .integer("expected_lifetime_count"),
            .text("state"),
            .text("created_at"),
        ],
        localOnly: true
    )

    static let schema = Schema(tables: [
        profiles,
        beans,
        brewSessions,
        extractionCreationQuotas,
        iapEntitlements,
        pendingExtractions,
    ])
}
