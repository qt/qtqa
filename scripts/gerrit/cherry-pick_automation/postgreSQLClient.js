/****************************************************************************
 **
 ** Copyright (C) 2020 The Qt Company Ltd.
 ** Contact: https://www.qt.io/licensing/
 **
 ** This file is part of the qtqa module of the Qt Toolkit.
 **
 ** $QT_BEGIN_LICENSE:LGPL$
 ** Commercial License Usage
 ** Licensees holding valid commercial Qt licenses may use this file in
 ** accordance with the commercial license agreement provided with the
 ** Software or, alternatively, in accordance with the terms contained in
 ** a written agreement between you and The Qt Company. For licensing terms
 ** and conditions see https://www.qt.io/terms-conditions. For further
 ** information use the contact form at https://www.qt.io/contact-us.
 **
 ** GNU Lesser General Public License Usage
 ** Alternatively, this file may be used under the terms of the GNU Lesser
 ** General Public License version 3 as published by the Free Software
 ** Foundation and appearing in the file LICENSE.LGPL3 included in the
 ** packaging of this file. Please review the following information to
 ** ensure the GNU Lesser General Public License version 3 requirements
 ** will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
 **
 ** GNU General Public License Usage
 ** Alternatively, this file may be used under the terms of the GNU
 ** General Public License version 2.0 or (at your option) the GNU General
 ** Public license version 3 or any later version approved by the KDE Free
 ** Qt Foundation. The licenses are as published by the Free Software
 ** Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
 ** included in the packaging of this file. Please review the following
 ** information to ensure the GNU General Public License requirements will
 ** be met: https://www.gnu.org/licenses/gpl-2.0.html and
 ** https://www.gnu.org/licenses/gpl-3.0.html.
 **
 ** $QT_END_LICENSE$
 **
 ****************************************************************************/

exports.id = "postgreSQLClient";
const { Pool } = require("pg");
const jsonSql = require("json-sql")();

let config = require("./postgreSQLconfig.json");

jsonSql.configure({ namedValues: false });
jsonSql.setDialect("postgresql");

// Use DATABASE_URL environment variable if set. (Heroku environments)
// Otherwise, continue to use the config file.
if (process.env.DATABASE_URL)
  config = { connectionString: process.env.DATABASE_URL, ssl: true };

const pool = new Pool(config);

pool.on("error", (err) => {
  // This should be non-critical. The database will clean up idle clients.
  console.trace("An idle database client has experienced an error", err.stack);
});

// Create our tables if they don't exist
pool.query(`CREATE TABLE IF NOT EXISTS processing_queue
            (
                uuid UUID PRIMARY KEY,
                changeid TEXT,
                state TEXT,
                revision TEXT,
                rawjson TEXT,
                cherrypick_results_json TEXT,
                pick_count_remaining INTEGER
            )
          `);

pool.query(`CREATE TABLE IF NOT EXISTS finished_requests
            (
                uuid UUID PRIMARY KEY,
                changeid TEXT,
                state TEXT,
                revision TEXT,
                rawjson TEXT,
                cherrypick_results_json TEXT,
                pick_count_remaining INTEGER
            )
          `);

pool.query(`CREATE TABLE IF NOT EXISTS retry_queue
            (
                uuid UUID PRIMARY KEY,
                retryaction TEXT,
                args TEXT
            )
          `);

// Exported functions
exports.end = end;
function end() {
  console.log("Waiting for PostgreSQL connections to close...");
  pool.end(function() {
    console.log("Database client pool has ended");
  });
}

exports.insert = insert;
function insert(table, columns, values, callback) {
  let valuecount_string;
  if (table == "processing_queue")
    valuecount_string = "$1,$2,$3,$4,$5,$6";
  else if (table == "retry_queue")
    valuecount_string = "$1,$2,$3";

  const query = {
    name: `insert-row-${table}`,
    text: `INSERT INTO ${table}(${columns}) VALUES(${valuecount_string})`,
    values: values
  };
  pool.query(query, function(err, data) {
    if (err)
      console.trace(err.message);
    if (callback)
      callback(!err, err ? err : data);
  });
}

exports.query = query;
function query(table, fields, keyName, keyValue, callback) {
  const query = {
    name: `query-${keyName}-${fields}`,
    text: `SELECT ${fields ? fields : "*"} FROM ${table} WHERE ${keyName} = $1`,
    values: [keyValue]
  };
  pool.query(query, (err, data) => {
    if (err)
      console.trace(err);
    if (callback) {
      let returndata = data.rows.length == 1 ? data.rows[0] : data.rows;
      callback(!err, err ? err : returndata);
    }
  });
}

exports.update = update;
function update(table, keyName, keyValue, changes, callback, processNextQueuedUpdate) {
  let sql = jsonSql.build({
    type: "update", table: table,
    condition: { [keyName]: keyValue },
    modifier: { ...changes }
  });

  pool.query(sql.query, sql.values, function(err, result) {
    if (callback)
      callback(!err, err ? err : result);

    // If the queuing function was passed, call it with the unlock parameter.
    // This will process the next item in queue or globally unlock the status
    // update lockout.
    if (processNextQueuedUpdate)
      processNextQueuedUpdate(undefined, undefined, undefined, undefined, true);
  });
}

exports.move = move;
function move(fromTable, toTable, keyName, keyValue, callback) {
  const query = {
    name: `query-move`,
    text: `INSERT INTO ${toTable} SELECT * FROM ${fromTable} WHERE ${keyName} = $1`,
    values: [keyValue]
  };
  pool.query(query, function(err) {
    if (err) {
      console.trace(err);
      callback(false, err);
    } else {
      deleteDBEntry(fromTable, keyName, keyValue, callback);
    }
  });
}

// Decrement a numeric key and return the new count.
exports.decrement = decrement;
function decrement(table, uuid, keyName, callback) {
  pool.query(
    `UPDATE ${table} SET ${keyName} = ${keyName} - 1 WHERE uuid = '${uuid}'`,
    function(err) {
      if (err) {
        console.trace(err);
        callback(false, err);
      } else {
        query(table, ["pick_count_remaining"], "uuid", uuid, callback);
      }
    }
  );
}

exports.deleteDBEntry = deleteDBEntry;
function deleteDBEntry(table, keyName, keyValue, callback) {
  let sql = jsonSql.build({
    type: "remove", table: table,
    condition: { [keyName]: keyValue }
  });

  pool.query(sql.query, sql.values, function(err) {
    if (err)
      console.trace(`An error occurred while running a query: ${JSON.stringify(sql)}`);
    if (callback)
      callback(!err, err ? err : this);
  });
}
