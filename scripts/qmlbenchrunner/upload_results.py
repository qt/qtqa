#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

import os
import sys
import pandas as pd
import json
import psycopg2
from io import StringIO

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INSERTION_SQL_PATH = os.path.join(SCRIPT_DIR, "insertion.sql")
RUN_DETAILS_INSERTION_SQL_PATH = os.path.join(SCRIPT_DIR, "insert_run_details.sql")
REVISIONS_MM_GROUPS_INSERTION_SQL_PATH = os.path.join(SCRIPT_DIR, "insert_revisions_mm_groups.sql")

def bulk_insert_results(conn, df):
    '''
    Inserts into staging table a bulk of results and then merges it into the main table.

    :param conn: Connection to database using psycopg2.
    :param df: Pandas dataframa containing the results of benchmark run.
    '''
    # Buffer is an in-memory text buffer which we fill with the df values, needed for copy_from.
    buffer = StringIO()
    df.to_csv(buffer, index=False, header=False)
    buffer.seek(0)      # Move cursor of the buffer back to the beginning.

    with conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE staging_qml_results")
        cur.copy_from(buffer, "staging_qml_results", sep=",", columns=df.columns)   # Copies buffer into table
        with open(INSERTION_SQL_PATH, "r") as f:
            query = f.read()
            cur.execute(query)

def insert_run_info(conn, branch, host, graphics_api, sha1_list):
    '''
    The insertion process:
    1. Store submodules and associate each with its sha1 in submodule_revisions.
    2. Look up the set of submodule_revision_ids in revisions_mm_groups.
    3. If no matching group exists, create a new group_id and insert the set.
    4. Insert branch, host, graphics API, and group_id into run_details_qml.

    :param conn: psycopg2 database connection.
    :param sha1_list: Comma-separated "module-sha1" pairs (e.g. 'qtbase-abc123,qtdeclarative-def456').
    '''
    # Inserts a submodule if not found and returns its submodule_id
    query_submodule = """ WITH inserted AS (
                            INSERT INTO submodules_qml (submodule)
                            SELECT %(submodule)s
                            WHERE NOT EXISTS (
                                SELECT 1 FROM submodules_qml WHERE submodule = %(submodule)s
                            )
                            RETURNING submodule_qml_id, submodule
                        )
                        SELECT submodule_qml_id, submodule
                        FROM
                            inserted
                        UNION ALL
                            SELECT
                                submodule_qml_id,
                                submodule
                            FROM
                                submodules_qml
                            WHERE
                                submodule = %(submodule)s;
                    """
    # Inserts sha1 for a submodule if not found and returns its submodule_revision_id
    query_revisions = """ WITH inserted AS (
                            INSERT INTO submodule_revisions (submodule_qml_id, sha1)
                            SELECT %(submodule_qml_id)s, %(sha1)s
                            WHERE NOT EXISTS (
                                SELECT 1 FROM submodule_revisions
                                WHERE
                                    submodule_qml_id = %(submodule_qml_id)s
                                AND
                                    sha1 = %(sha1)s
                            )
                            RETURNING submodule_revision_id
                        )
                        SELECT
                            submodule_revision_id
                        FROM
                            inserted
                        UNION ALL
                            SELECT
                                submodule_revision_id
                            FROM
                                submodule_revisions
                            WHERE
                                submodule_qml_id = %(submodule_qml_id)s
                            AND
                                sha1 = %(sha1)s
                """

    rev_ids = []
    with conn.cursor() as cur:
        # Split elements of sha1_list into module and sha
        for item in sha1_list[0].split(","):
            module, sha = item.split("-", 1)
            module = module.strip(" '")
            sha = sha.strip(" '")

            cur.execute(query_submodule, {"submodule": module})
            module_id = cur.fetchone()[0]

            cur.execute(query_revisions, {"submodule_qml_id" : module_id, "sha1" : sha})
            rev_ids.append(cur.fetchone()[0])

        with open(REVISIONS_MM_GROUPS_INSERTION_SQL_PATH, "r") as f:
            query = f.read()
        cur.execute(query, {"rev_ids": rev_ids})
        group_id = cur.fetchone()[0]

        data = {
            "host": host,
            "graphics_api": graphics_api,
            "branch": branch,
            "group_id": group_id
        }

        with open(RUN_DETAILS_INSERTION_SQL_PATH, "r") as f:
            query = f.read()

        cur.execute(query, data)
        run_details_id = cur.fetchone()[0]

    return run_details_id

def submit_output(filename, branch, host_name, sha1_list):
    print("Loading %s" % filename)

    with open(filename, "r") as f:
        tree = json.load(f)

    if 'vulkan' in tree.keys():
        graphics_api = 'vulkan'
    else:
        graphics_api = 'opengl'

    rows = []
    # Retrieve benchmark values from filename
    for key in tree:
        if key.endswith(".qml"):
            mean = 0
            standardDeviation = 0
            coefficientOfVariation = 0

            # key is benchmarks/auto/<suite>/benchmark.qml
            # dirname will trim off the last part and then we
            # retrieve the suite. Does not differentiate
            # between creation/quick.image and creation/quick.item
            # and saves both under creation.
            benchmarkSuite = os.path.dirname(key)
            prefix = "benchmarks/auto/"
            cutPos = benchmarkSuite.find(prefix)
            if cutPos != -1:
                benchmarkSuite = benchmarkSuite[cutPos + len(prefix):]
                benchmarkSuite = benchmarkSuite.lstrip("/").split("/", 1)[0]

            try:
                mean = tree[key]["average"]
                standardDeviation = tree[key]["standard-deviation-all-samples"]
                coefficientOfVariation = tree[key]["coefficient-of-variation"]
                iterations = tree[key]["samples-in-average"]
            except:
                # Catch exceptions in order to keep other results and
                # be able to upload them.
                print("Test %s was malformed (empty run?)" % key, file=sys.stderr)
                # Skip this iteration as there is no result
                continue

            basename = key.split("/")[-1]

            rows.append({
                "benchmark": basename,
                "suite": benchmarkSuite,
                "mean": mean,
                "std_dev": standardDeviation,
                "cov": coefficientOfVariation,
                "iterations": iterations
            })

    df = pd.DataFrame(rows)

    conn_info = f'''host=benchmark-postgres.ci.qt.io
                    dbname=benchmarks
                    user={os.environ["TIMESCALEDBUSER"]}
                    password={os.environ["TIMESCALEDBPASSWORD"]}
                    port=5432
                '''
    n = len(df)
    inserted = 0
    batch_size = n if n < 25000 else 25000

    with psycopg2.connect(conn_info) as conn:
        run_details = insert_run_info(conn, branch, host_name, graphics_api, sha1_list)
        df["run_details_qml_id"] = run_details

        # Insert benchmark results in batches
        for start in range(0, n, batch_size):
            batch = df.iloc[start:start+batch_size]

            bulk_insert_results(conn, batch)

            inserted += batch.shape[0]

        with conn.cursor() as cur:
            cur.execute("TRUNCATE TABLE staging_qml_results")

        print(f"Successfully inserted {inserted} rows")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("filename", help = "The .json file to post")
    parser.add_argument("branch", help = "The Qt branch tested")
    parser.add_argument("host_name", help = "Our unique hardware ID (e.g. linux_imx6_eskil)")
    parser.add_argument("sha1",  nargs="+", help = "Comma-separated module SHA-1 pairs in format "
                                                   "'module-sha1,module-sha1' (e.g. 'qtbase-abc123,qtdeclarative-def456')")
    args = parser.parse_args(sys.argv[1:])

    submit_output(args.filename, args.branch, args.host_name, args.sha1)
