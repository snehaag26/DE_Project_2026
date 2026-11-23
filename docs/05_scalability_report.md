# Phase 5 — Scalability report

## Status and benchmark evidence

The repository contains the 120,000-order seed archive but no `large_data/` directory or `large_data.zip`. The Phase 5 large dataset is therefore unavailable in this checkout. No large-dataset benchmark was run, and no large timing, growth ratio, execution plan, or storage number is reported here. The project instructions explicitly prohibit invented benchmark results.

The benchmark runner requires a PostgreSQL database. `psql`, `postgres`, and `initdb` are not installed in this environment, and Docker Desktop's daemon is not running. The required three-run benchmark and raw plan capture cannot be performed until PostgreSQL and the faculty large data are available.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth | Target | Status |
|---|---:|---:|---:|---|---|
| R01–R24, W01–W06 | Not measured here | Not measured | Not available | See README Phase 5.2 | Pending large data and PostgreSQL |

## 20× growth analysis

No measured growth comparison is possible without the large dataset and benchmark environment. Expected behavior is a design hypothesis only: selective B-tree lookups should grow roughly with index depth; queries scanning a fixed fraction of rows can grow close to the data multiplier; broad aggregation and correlated repeated scans can grow faster. These expectations must be checked against the three raw runs and plans before being presented as results.

## Partitioning design for 100× volume

[`sql/08_partitioning.sql`](../sql/08_partitioning.sql) provides a transactional migration that range-partitions `orders` by `ordered_at`, creates yearly partitions plus a default partition, and copies existing rows. Date-bounded reports can prune partitions. A partitioned primary key must include the partition key, so `orders` uses `(order_id, ordered_at)`; `order_items.ordered_at` is populated and added to its foreign key. An additional non-unique `order_id` index supports order-id-only lookups such as R23.

The migration's representative `EXPLAIN` is included as a commented command. Partition pruning has not been observed in this environment and must be confirmed after running the migration on PostgreSQL. The query text for date-filtered workloads should use direct half-open timestamp ranges; expressions such as `date_trunc` or casts on the partition column can prevent pruning.

## Sharding, replicas, and cache

- **Sharding:** customer-based sharding keeps the customer order view (R04) local, while seller-based queries such as R06 and R15 become cross-shard because an order can contain multiple sellers. Seller-based sharding reverses that tradeoff and makes customer order history cross-shard. Order-based sharding keeps order headers and lines together but distributes a customer's or seller's history across shards. For this workload, keep orders and lines co-located by order and use a routing or fan-out layer for customer and seller reports; choose a shard key only after measuring the cross-shard query share.
- **Read replicas:** stale-tolerant reporting and analytics (R08–R20, except operational freshness-sensitive R10/R13 as appropriate) can use replicas. Checkout and stock mutations (W01–W03), shipping (W05), and read-after-write order/product views should use the primary. Replica lag must be monitored for reports with freshness requirements.
- **Caching:** cache product/category browse and lookup results (R01/R02/R14/R24) with short expiry or invalidation on product changes. Avoid caching checkout, inventory mutations, or shipment state. Cached analytics need explicit freshness windows.

## Maintenance and retention

Provision future yearly partitions before each year boundary and monitor the default partition so new data does not accumulate there unnoticed. Keep autovacuum enabled; tune per-table scale factors only from observed dead-tuple and vacuum-duration metrics. Archive old closed partitions after retention and restore tests are defined. Refresh any future summary materialized views on a documented schedule and expose their data freshness.

## Conclusion

The partitioning and distribution design is documented, but readiness for 20× growth is **not yet demonstrated**. Required remaining evidence: load the faculty dataset into a separate PostgreSQL database, apply `sql/05_indexes.sql` and `sql/08_partitioning.sql` as appropriate, capture three runs of each optimized workload query, retain raw plans in `benchmarks/results/large/`, and record database/table/index sizes on both datasets. Then update this report with measured target outcomes and any scale-only fixes.
