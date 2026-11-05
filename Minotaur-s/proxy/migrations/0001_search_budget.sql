CREATE TABLE IF NOT EXISTS search_budget (
  period TEXT PRIMARY KEY,
  production INTEGER NOT NULL DEFAULT 0 CHECK(production BETWEEN 0 AND 800),
  evaluation INTEGER NOT NULL DEFAULT 0 CHECK(evaluation BETWEEN 0 AND 200),
  minute INTEGER NOT NULL,
  burst INTEGER NOT NULL DEFAULT 0,
  CHECK(production + evaluation <= 1000)
);
