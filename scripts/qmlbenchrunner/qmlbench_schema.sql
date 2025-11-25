-- Drop all tables in reverse dependency order to avoid FK constraint errors.
DROP TABLE IF EXISTS qmlbench_results CASCADE;
DROP TABLE IF EXISTS graphics_apis CASCADE;
DROP TABLE IF EXISTS suites CASCADE;
DROP TABLE IF EXISTS hosts_qml CASCADE;
DROP TABLE IF EXISTS branches_qml CASCADE;
DROP TABLE IF EXISTS submodules_qml CASCADE;
DROP TABLE IF EXISTS benchmarks_qml CASCADE;
DROP TABLE IF EXISTS group_ids CASCADE;
DROP TABLE IF EXISTS run_details_qml CASCADE;
DROP TABLE IF EXISTS submodule_revisions CASCADE;
DROP TABLE IF EXISTS revisions_mm_groups CASCADE;
DROP TABLE IF EXISTS staging_qml_results CASCADE;

-- Lookup tables for run metadata.
CREATE TABLE branches_qml (
   branch_qml_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   branch TEXT NOT NULL,
   UNIQUE (branch)
);

CREATE TABLE hosts_qml (
   host_qml_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   host_name TEXT NOT NULL,
   UNIQUE (host_name)
);

CREATE TABLE graphics_apis (
   graphics_api_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   graphics_api TEXT NOT NULL,
   UNIQUE (graphics_api)
);

CREATE TABLE suites (
   suite_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   suite TEXT NOT NULL,
   UNIQUE (suite)
);

CREATE TABLE benchmarks_qml (
   benchmark_qml_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   benchmark TEXT NOT NULL,
   UNIQUE (benchmark)
);

-- Submodule revisions and grouping.
-- Each submodule_revision is a unique (submodule, sha1) pair.
-- A group represents a set of submodule_revisions that were used together in a run,
-- stored as a many-to-many relationship in revisions_mm_groups.
CREATE TABLE submodules_qml (
   submodule_qml_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   submodule TEXT NOT NULL,
   UNIQUE (submodule)
);

CREATE TABLE submodule_revisions (
   submodule_revision_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   submodule_qml_id int REFERENCES submodules_qml(submodule_qml_id) NOT NULL,
   sha1 TEXT NOT NULL,
   UNIQUE (submodule_qml_id, sha1)
);

CREATE TABLE group_ids (
   group_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY
);

CREATE TABLE revisions_mm_groups (
   submodule_revision_id int REFERENCES submodule_revisions(submodule_revision_id) NOT NULL,
   group_id int REFERENCES group_ids(group_id) NOT NULL,
   UNIQUE (submodule_revision_id, group_id)
);

-- Unique combination of host, graphics API, branch, and submodule revision group for a run.
CREATE TABLE run_details_qml (
  run_details_qml_id int PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  host_qml_id int REFERENCES hosts_qml(host_qml_id) NOT NULL,
  graphics_api_id int REFERENCES graphics_apis(graphics_api_id) NOT NULL,
  branch_qml_id int REFERENCES branches_qml(branch_qml_id) NOT NULL,
  group_id int REFERENCES group_ids(group_id) NOT NULL,
  UNIQUE (host_qml_id, graphics_api_id, branch_qml_id, group_id)
);

-- Main results hypertable, partitioned and compressed by run_on.
CREATE TABLE qmlbench_results (
  "run_on" TIMESTAMPTZ NOT NULL,
  benchmark_qml_id int REFERENCES benchmarks_qml(benchmark_qml_id) NOT NULL,
  run_details_qml_id int REFERENCES run_details_qml(run_details_qml_id) NOT NULL,
  suite_id int REFERENCES suites(suite_id) NOT NULL,
  mean DOUBLE PRECISION,
  cov DOUBLE PRECISION,
  std_dev DOUBLE PRECISION,
  iterations int
) WITH (
  tsdb.hypertable,
  tsdb.compress,
  tsdb.partition_column='run_on',
  tsdb.compress_segmentby='benchmark_qml_id, run_details_qml_id, suite_id',
  tsdb.chunk_interval='180 day',
  tsdb.compress_orderby = 'run_on DESC'
);

-- Staging table for bulk-loading raw results before normalization into qmlbench_results.
CREATE TABLE IF NOT EXISTS staging_qml_results (
    run_on TIMESTAMPTZ,
    benchmark TEXT,
    suite TEXT,
    run_details_qml_id INT,
    iterations INT,
    mean DOUBLE PRECISION,
    cov DOUBLE PRECISION,
    std_dev DOUBLE PRECISION
);

-- Automatically compress chunks older than 180 days.
SELECT add_compression_policy(
  'qmlbench_results',
  INTERVAL '180 days',
  if_not_exists => true
);

-- Seed a placeholder revision group for historic data that predates submodule tracking.
INSERT INTO submodules_qml (submodule) VALUES ('historic data');
INSERT INTO submodule_revisions (submodule_qml_id, sha1) VALUES (1, 'historic data');
INSERT INTO group_ids DEFAULT VALUES;
INSERT INTO revisions_mm_groups (group_id, submodule_revision_id) VALUES (1, 1);

-- Supports lookups on run_details_qml by the most common filter columns.
CREATE INDEX ON run_details_qml (host_qml_id, branch_qml_id, graphics_api_id);
