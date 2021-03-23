/* eslint-disable no-unused-vars */
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
const safeJsonStringify = require("safe-json-stringify");

let config = require("./postgreSQLconfig.json");
const Logger = require("./logger");
const logger = new Logger();

jsonSql.configure({ namedValues: false });
jsonSql.setDialect("postgresql");

// Use DATABASE_URL environment variable if set. (Heroku environments)
// Otherwise, continue to use the config file.
if (process.env.DATABASE_URL)
  config = { connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } }


logger.log(
  `Connecting to PostgreSQL database with config: ${safeJsonStringify(config)}`,
  "debug", "DATABASE"
);

const pool = new Pool(config);

pool.on("error", (err) => {
  // This should be non-critical. The database will clean up idle clients.
  logger.log(`An idle database client has experienced an error: ${err.stack}`, "error");
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
              pick_count_remaining INTEGER,
              listener_cache TEXT
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
function end(callback) {
  // Clean up the retry_queue. Restoring processes on next restart
  // will retry any action that was in-process.
  logger.log("cleaning up retry table entries...", undefined, "DATABASE");
  pool.query(`DELETE FROM retry_queue`, (err, data) => {
    logger.log(`Cleanup result: ${!err}`, undefined, "DATABASE");
    logger.log("Waiting for PostgreSQL connections to close...", undefined, "DATABASE");
    pool.end(() => {
      logger.log("Database client pool has ended", undefined, "DATABASE");
      callback(true);
    });
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
  logger.log(`Running query: ${safeJsonStringify(query)}`, "silly", "DATABASE");
  pool.query(query, function (err, data) {
    if (err)
      logger.log(`Database error: ${err.message}\n${Error().stack}`, "error", "DATABASE");
    if (callback)
      callback(!err, err || data);
  });
}

exports.query = query;
function query(table, fields, keyName, keyValue, operator, callback) {
  const query = {
    name: `query-${keyName}-${fields}`,
    text: `SELECT ${fields || "*"} FROM ${table} WHERE ${keyName} ${
      keyValue ? operator + " $1" : operator
    }`,
    values: keyValue ? [keyValue] : undefined
  };

  logger.log(`Running query: ${safeJsonStringify(query)}`, "silly", "DATABASE");
  pool.query(query, (err, data) => {
    if (err)
      logger.log(`Database error: ${err}\nQuery: ${query}\n${Error().stack}`, "error", "DATABASE");
    if (callback)
      callback(!err, err || data.rows);

  });
}

exports.update = update;
function update(table, keyName, keyValue, changes, callback, processNextQueuedUpdate) {
  let sql = jsonSql.build({
    type: "update", table: table,
    condition: { [keyName]: keyValue },
    modifier: { ...changes }
  });

  logger.log(`Running query: ${safeJsonStringify(sql)}`, "silly", "DATABASE");
  pool.query(sql.query, sql.values, function (err, result) {
    if (err) {
      logger.log(
        `Database error: ${err}\nQuery: ${safeJsonStringify(sql)}\n${Error().stack}`,
        "error", "DATABASE"
      );
    }
    if (callback)
      callback(!err, err || result);

    // If the queuing function was passed, call it with the unlock parameter.
    // This will process the next item in queue or globally unlock the status
    // update lockout.
    if (processNextQueuedUpdate)
      processNextQueuedUpdate(undefined, undefined, undefined, undefined, true);
  });
}

// Decrement a numeric key and return the new count.
exports.decrement = decrement;
function decrement(table, uuid, keyName, callback) {
  let querystring = `UPDATE ${table} SET ${keyName} = ${keyName} - 1 WHERE uuid = '${uuid}' and ${
    keyName} > 0`;

  logger.log(`Running query: ${querystring}`, "silly", "DATABASE");
  pool.query(querystring, function (err) {
    if (err) {
      logger.log(`Database error: ${err}\n${Error().stack}`, "error", uuid);
      callback(false, err);
    } else {
      query(table, ["pick_count_remaining"], "uuid", uuid, "=", callback);
    }
  });
}

exports.deleteDBEntry = deleteDBEntry;
function deleteDBEntry(table, keyName, keyValue, callback) {
  let sql = jsonSql.build({
    type: "remove", table: table,
    condition: { [keyName]: keyValue }
  });

  logger.log(`Running query: ${safeJsonStringify(sql)}`, "silly", "DATABASE");
  pool.query(sql.query, sql.values, function (err) {
    if (err) {
      logger.log(
        `An error occurred while running a query: ${safeJsonStringify(sql)}`,
        "error", "DATABASE"
      );
    }
    if (callback)
      callback(!err, err || this);
  });
}
