-- Smoke test for vchord-on-Windows. Run after install + restart.
-- Usage:  psql -U postgres -d hindsight -f test-vchord.sql

\echo === vchord smoke test ===

-- 1. Create
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
\echo extensions installed:
SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector','vchord');

-- 2. Types created
\echo vchord types present:
SELECT typname FROM pg_type
WHERE typname IN ('rabitq4','rabitq8','sphere_vector','sphere_halfvec')
ORDER BY typname;

-- 3. Table with embedding + vchordrq index
DROP TABLE IF EXISTS vchord_smoke;
CREATE TABLE vchord_smoke (id serial PRIMARY KEY, embedding vector(8));
INSERT INTO vchord_smoke (embedding) VALUES
  ('[1,0,0,0,0,0,0,0]'),
  ('[0,1,0,0,0,0,0,0]'),
  ('[0,0,1,0,0,0,0,0]'),
  ('[0,0,0,1,0,0,0,0]'),
  ('[0.5,0.5,0,0,0,0,0,0]');

\echo creating vchordrq index:
CREATE INDEX vchord_smoke_idx ON vchord_smoke
  USING vchordrq (embedding vector_l2_ops);

\echo top-3 nearest to [1,0,0,0,0,0,0,0]:
SELECT id, embedding, embedding <-> '[1,0,0,0,0,0,0,0]' AS dist
FROM vchord_smoke
ORDER BY embedding <-> '[1,0,0,0,0,0,0,0]'
LIMIT 3;

DROP TABLE vchord_smoke;
\echo === smoke test complete ===
