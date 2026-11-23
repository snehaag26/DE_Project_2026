-- Phase 5 design migration: range-partition orders by ordered_at.
-- Run after loading the unpartitioned schema and data, in a maintenance window.
-- The default partition preserves rows outside the explicitly provisioned years.

\set ON_ERROR_STOP on
BEGIN;
SET search_path TO amazon;

-- A partitioned primary key must include the partition key. Carry ordered_at
-- into order_items so its order reference remains enforceable.
ALTER TABLE order_items ADD COLUMN ordered_at TIMESTAMPTZ;
UPDATE order_items oi
SET ordered_at = o.ordered_at
FROM orders o
WHERE o.order_id = oi.order_id;
ALTER TABLE order_items ALTER COLUMN ordered_at SET NOT NULL;

-- Preserve the existing rows while replacing orders with a partitioned parent.
ALTER TABLE order_items DROP CONSTRAINT fk_order_items_order;
ALTER TABLE orders RENAME TO orders_unpartitioned;

CREATE TABLE orders (
    order_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id BIGINT REFERENCES addresses(address_id) ON DELETE RESTRICT,
    ordered_at TIMESTAMPTZ NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    status VARCHAR(30) NOT NULL,
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    CONSTRAINT pk_orders PRIMARY KEY (order_id, ordered_at),
    CONSTRAINT chk_order_payment CHECK (payment_method IN
        ('CARD','COD','EMI','GIFT_CARD','NETBANKING','UPI')),
    CONSTRAINT chk_order_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_order_status CHECK (status IN
        ('CANCELLED','DELIVERED','OUT_FOR_DELIVERY','PACKED','PLACED','RETURNED','SHIPPED')),
    CONSTRAINT chk_order_shipping_time CHECK (shipped_at IS NULL OR shipped_at >= ordered_at),
    CONSTRAINT chk_order_delivery_time CHECK
        (delivered_at IS NULL OR shipped_at IS NULL OR delivered_at >= shipped_at)
) PARTITION BY RANGE (ordered_at);

CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');
CREATE TABLE orders_2026 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
CREATE TABLE orders_2027 PARTITION OF orders
    FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2028-01-01 00:00:00+00');
CREATE TABLE orders_2028 PARTITION OF orders
    FOR VALUES FROM ('2028-01-01 00:00:00+00') TO ('2029-01-01 00:00:00+00');
CREATE TABLE orders_default PARTITION OF orders DEFAULT;

INSERT INTO orders
    (order_id, customer_id, address_id, ordered_at, payment_method, total_amount,
     status, shipped_at, delivered_at)
SELECT order_id, customer_id, address_id, ordered_at, payment_method, total_amount,
       status, shipped_at, delivered_at
FROM orders_unpartitioned;

DROP TABLE orders_unpartitioned;
ALTER TABLE order_items
    ADD CONSTRAINT fk_order_items_order_partitioned
    FOREIGN KEY (order_id, ordered_at) REFERENCES orders(order_id, ordered_at)
    ON DELETE RESTRICT;

-- Keep order-id-only lookups (for example R23) efficient. Time-range queries
-- can prune partitions, including R06/R09/R20/R21 when predicates are sargable.
CREATE INDEX ix_orders_order_id ON orders (order_id);
CREATE INDEX ix_order_items_order_date ON order_items (order_id, ordered_at);
ANALYZE orders;
ANALYZE order_items;
COMMIT;

-- Verify pruning with a representative date-bounded query:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT order_id FROM amazon.orders
-- WHERE ordered_at >= TIMESTAMPTZ '2026-06-01 00:00:00+00'
--   AND ordered_at <  TIMESTAMPTZ '2026-07-01 00:00:00+00';
-- The plan should name only orders_2026 (and not orders_2025/2027/2028).
