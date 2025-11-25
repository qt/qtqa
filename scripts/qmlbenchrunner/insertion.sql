-- Insert benchmark if not exists
INSERT INTO benchmarks_qml (benchmark)
SELECT DISTINCT s.benchmark
FROM staging_qml_results s
WHERE NOT EXISTS (
    SELECT 1 FROM benchmarks_qml b
    WHERE b.benchmark = s.benchmark
);

-- Insert suite if not exists
INSERT INTO suites (suite)
SELECT DISTINCT s.suite
FROM staging_qml_results s
WHERE NOT EXISTS (
    SELECT 1 FROM suites su
    WHERE su.suite = s.suite
);

-- Insert results in qmlbench_results
INSERT INTO qmlbench_results (
    run_on,
    benchmark_qml_id,
    suite_id,
    run_details_qml_id,
    mean,
    cov,
    std_dev,
    iterations
)
SELECT
    NOW() as run_on,
    b.benchmark_qml_id,
    su.suite_id,
    s.run_details_qml_id,
    s.mean,
    s.cov,
    s.std_dev,
    s.iterations
FROM staging_qml_results s
JOIN benchmarks_qml b        ON b.benchmark = s.benchmark
JOIN suites su           ON su.suite = s.suite
