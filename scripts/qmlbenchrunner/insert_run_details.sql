WITH
-- Insert host if not exists
host_row AS (
    INSERT INTO hosts_qml (host_name)
    SELECT %(host)s
    WHERE NOT EXISTS (
        SELECT 1 FROM hosts_qml h WHERE h.host_name = %(host)s
    )
    RETURNING host_qml_id
),
host_qml_id_final AS (
    SELECT host_qml_id FROM host_row
    UNION ALL
    SELECT host_qml_id FROM hosts_qml WHERE host_name = %(host)s
),

-- Insert graphics_api if not exists
graphics_row AS (
    INSERT INTO graphics_apis (graphics_api)
    SELECT %(graphics_api)s
    WHERE NOT EXISTS (
        SELECT 1 FROM graphics_apis g WHERE g.graphics_api = %(graphics_api)s
    )
    RETURNING graphics_api_id
),
graphics_id_final AS (
    SELECT graphics_api_id FROM graphics_row
    UNION ALL
    SELECT graphics_api_id FROM graphics_apis WHERE graphics_api = %(graphics_api)s
),

-- Insert branch if not exists
branch_row AS (
    INSERT INTO branches_qml (branch)
    SELECT %(branch)s
    WHERE NOT EXISTS (
        SELECT 1 FROM branches_qml b WHERE b.branch = %(branch)s
    )
    RETURNING branch_qml_id
),
branch_qml_id_final AS (
    SELECT branch_qml_id FROM branch_row
    UNION ALL
    SELECT branch_qml_id FROM branches_qml WHERE branch = %(branch)s
),

-- Insert run_details_qml if not exists
run_details_insert AS (
    INSERT INTO run_details_qml (host_qml_id, graphics_api_id, branch_qml_id, group_id)
    SELECT h.host_qml_id, g.graphics_api_id, b.branch_qml_id, %(group_id)s
    FROM host_qml_id_final h, graphics_id_final g, branch_qml_id_final b
    WHERE NOT EXISTS (
        SELECT 1
        FROM run_details_qml r
        WHERE r.host_qml_id = h.host_qml_id
          AND r.graphics_api_id = g.graphics_api_id
          AND r.branch_qml_id = b.branch_qml_id
          AND r.group_id = %(group_id)s
    )
    RETURNING run_details_qml_id
),
run_details_qml_id_final AS (
    SELECT run_details_qml_id FROM run_details_insert
    UNION ALL
    SELECT r.run_details_qml_id
    FROM run_details_qml r
    JOIN host_qml_id_final h ON r.host_qml_id = h.host_qml_id
    JOIN graphics_id_final g ON r.graphics_api_id = g.graphics_api_id
    JOIN branch_qml_id_final b ON r.branch_qml_id = b.branch_qml_id
    WHERE r.group_id = %(group_id)s
)

SELECT run_details_qml_id FROM run_details_qml_id_final;
