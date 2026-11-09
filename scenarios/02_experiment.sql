-- Phase 0 hand experiment. Run with psql; watch "Execution Time" at the bottom of each plan.
-- Run each EXPLAIN a few times; the first run is slower while caches warm.

\echo '=== BEFORE: no index on orders.user_id ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 500;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 500;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 500;

\echo '=== Applying fix: CREATE INDEX ==='
CREATE INDEX idx_orders_user_id ON orders (user_id);
ANALYZE orders;

\echo '=== AFTER: index on orders.user_id ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 500;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 500;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 500;

-- Reset so the experiment can be re-run.
DROP INDEX idx_orders_user_id;
