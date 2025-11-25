-- Creates a sorted array with the revision_ids.
-- The revision_ids represent the set of sha1 used when running these benchmarks.
WITH input_ids AS (
    SELECT ARRAY_AGG(x ORDER BY x) AS sorted_ids
    FROM UNNEST(%(rev_ids)s::int[]) x
),
-- Looks up an existing group_id in revisions_mm_groups whose members exactly match the input array.
matching_group AS (
    SELECT rmg.group_id
    FROM
        revisions_mm_groups rmg
    CROSS JOIN
        input_ids
    GROUP BY
        rmg.group_id, input_ids.sorted_ids
    HAVING
        ARRAY_AGG(rmg.submodule_revision_id
    ORDER BY
        rmg.submodule_revision_id) = input_ids.sorted_ids
    LIMIT 1
),
-- Inserts a new group_id if no matching group was found.
new_group AS (
    INSERT INTO group_ids
    SELECT
    WHERE NOT EXISTS (SELECT 1 FROM matching_group)
    RETURNING group_id
),
-- Inserts each revision_id paired with the new group_id into revisions_mm_groups.
-- Only runs if new_group produced a row, i.e. no matching group existed.
insert_revisions AS (
    INSERT INTO revisions_mm_groups (submodule_revision_id, group_id)
    SELECT UNNEST(%(rev_ids)s::int[]), new_group.group_id
    FROM new_group
    WHERE NOT EXISTS (SELECT 1 FROM matching_group)
    RETURNING group_id
)
-- Returns the group_id, whether it was found or newly created.
SELECT group_id FROM matching_group
UNION ALL
SELECT group_id FROM insert_revisions;
