-- Phase 0 seed: skewed e-commerce data. Idempotent: drops and recreates.
-- Deliberately NO index on orders.user_id (that is the planted fault).

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;

CREATE TABLE users (
    id         integer PRIMARY KEY,
    email      text NOT NULL,
    created_at timestamptz NOT NULL
);

INSERT INTO users (id, email, created_at)
SELECT g,
       'user' || g || '@example.com',
       now() - (random() * interval '730 days')
FROM generate_series(1, 100000) AS g;

CREATE TABLE orders (
    id           integer PRIMARY KEY,
    user_id      integer NOT NULL,
    status       text NOT NULL,
    total_amount numeric(10, 2) NOT NULL,
    created_at   timestamptz NOT NULL
);

-- 1,000,000 orders. user_id = floor(100000 * random()^3) + 1 is heavily skewed
-- toward low ids: user 1 gets thousands of orders, most users get only a few.
INSERT INTO orders (id, user_id, status, total_amount, created_at)
SELECT g,
       floor(100000 * power(random(), 3))::int + 1,
       (ARRAY['pending', 'paid', 'shipped', 'delivered', 'cancelled'])[1 + floor(random() * 5)::int],
       round((random() * 500)::numeric, 2),
       now() - (random() * interval '730 days')
FROM generate_series(1, 1000000) AS g;

ANALYZE users;
ANALYZE orders;

-- Sanity check: show the skew.
SELECT count(*) AS total_orders, count(DISTINCT user_id) AS distinct_users FROM orders;
SELECT user_id, count(*) AS orders FROM orders GROUP BY user_id ORDER BY orders DESC LIMIT 5;
