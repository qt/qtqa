/* eslint-disable no-unused-vars */
/****************************************************************************
 **
 ** Copyright (C) 2023 The Qt Company Ltd.
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

exports.id = "core_benchmarks_server";

const { default: axios } = require("axios");
const { response } = require("express");
const { DatabaseError } = require("pg");
const { ReadyForQueryMessage } = require("pg-protocol/dist/messages");
const safeJsonStringify = require("safe-json-stringify");
const socketio = require("socket.io");
const toBool = require("to-bool");
const moment = require("moment");
const express = require("express");
const uuidv1 = require("uuidv1");
const net = require("net");
const onChange = require("on-change");


const gerritTools = require("../../gerritRESTTools");
const postgreSQLClient = require("../../postgreSQLClient");
const config = require("./config.json");
const { testCachePredicate } = require("axios-cache-interceptor");
const e = require("express");


function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}


postgreSQLClient.pool.query(`CREATE TABLE IF NOT EXISTS core_benchmarks
  (
    integration_id TEXT PRIMARY KEY,
    integration_timestamp TIMESTAMP WITHOUT TIME ZONE,
    integration_url TEXT,
    integration_data TEXT,
    branch TEXT,
    work_sha TEXT,
    agents TEXT[],
    done BOOL[],
    job_done BOOL,
    timestamp TIMESTAMP WITHOUT TIME ZONE
  )
`);

postgreSQLClient.pool.query(`CREATE TABLE IF NOT EXISTS core_benchmarks_agents
  (
    agent_id TEXT PRIMARY KEY,
    last_connected TIMESTAMP WITHOUT TIME ZONE
  )
`);


const Status = {
  New: 'new',
  Git: 'git',
  Configure: 'configure',
  Build: 'build',
  Test: 'test',
  Results: 'results',
  Done: 'done',
  Idle: 'idle'
}

class Work {
  constructor(o={}) {
    this.integrationId = o.integrationId;
    this.integrationTimestamp = o.integrationTimestamp;
    this.integrationURL = o.integrationURL,
    this.integrationData = o.integrationData;
    this.branch = o.branch;
    this.sha = o.sha;
    this.status = o.status || Status.Idle;
    this.detailMessage = o.detailMessage;
    this.updateTimestamp = o.updateTimestamp;
  }
}

class Agent {
  constructor(socket, lastConnected) {
    this.socket = socket;
    this.currentJob = new Work();
    this.workQueue = [];
    this.online = false;
    this.lastConnected = lastConnected;
  }
}

let webViewers = {}  // save sockets by ID.

// Target object for watch proxy. Watching the object allows sending of
// realtime updates to web viewer users.
let _agents = {};
const agents = onChange(_agents, () => {
  //push the update to connected agents
  const agentData = Object.keys(_agents).map((agent) => {
    return {
      agent: agent,
      currentJob: _agents[agent].currentJob,
      online: _agents[agent].online,
      lastConnected: _agents[agent].lastConnected
    }
  });
  for (const id in webViewers) {
    webViewers[id].emit('agentData', agentData);
  }
});

function enqueueWork(agentId, workData) {
  console.log(`enqueue work ${workData.integrationId} to ${agentId}`);
  if (agents[agentId])
    agents[agentId].workQueue.push(workData);
  else
    console.log(`Cannot enqueue ${workData.integrationId} to ${agentId} because it is stale.`)
}

// TODO: Need to be able to queue for agents known, but not currently connected.
// On first connect, safe the agent name somewhere persistent.

let integrationIdsInProcess = [];  // Fast memory access locally
let _integrationJobsDone = [];  // Short-term memory for completed jobs.
const integrationJobsDone = onChange(_integrationJobsDone, () => {
  for (const id in webViewers) {
    webViewers[id].emit('workLogData', _integrationJobsDone);
  }
});



let dbQueue = {};
let dbQueueLocks = {};

function enqueueDBAction(uuid, integrationId, targetFunction, args, unlock = false) {
  if (unlock) {
    console.log(`enqueueDBAction run with unlock=true`, "silly");
  } else {
    console.log(
      `New DB request: func: ${targetFunction.name}, Data: ${safeJsonStringify(args)}`,
      "debug", uuid
    );
  }
  if (uuid && targetFunction && args) {
    if (!dbQueue[integrationId])
      dbQueue[integrationId] = [];
    dbQueue[integrationId].push({ targetFunction: targetFunction, args: args });
  }

  if (!dbQueueLocks[integrationId] || unlock) {
    dbQueueLocks[integrationId] = true;
    if (dbQueue[integrationId].length > 0) {
      let action = dbQueue[integrationId].shift();
      action.args.push(enqueueDBAction);
      action.targetFunction.apply(null, action.args);
    } else {
      delete dbQueue[integrationId];
      delete dbQueueLocks[integrationId];
    }
  }
}


// Query database for integrationId and get status of any jobs for that ID.
function dbCheckIfWorkNeeded(uuid, integrationId, agents, timestamp) {
  return new Promise(function(resolve, reject) {
    if (integrationIdsInProcess.includes(integrationId)) {
      reject("in_progress");
      return;
    }

    // Feature proposal: Determine platforms to run tests on.
    integrationIdsInProcess.push(integrationId);
    console.log(timestamp);
    let doneVals = [];
    doneVals.length = agents.length;
    doneVals.fill(false);
    enqueueDBAction(uuid, integrationId, postgreSQLClient.insert,
      [
        "core_benchmarks",
        ["integration_id","work_sha","integration_timestamp","agents","done",
         "job_done", "timestamp"],
        [integrationId, null, timestamp, agents, doneVals, false,
          new Date(Date.now()).toISOString()],
        (success, rows) => {
          if (success)
            resolve() // DB insert successful.
          else
            reject(rows);  // Rows is a DBError in the error case
        },
      ]
    );
  });
}

function collectIntegrationId(uuid, fullChangeId) {
  return new Promise(function(resolve, reject) {
    gerritTools.findIntegrationIDFromChange(uuid, fullChangeId, null, (integrationId, timestamp) => {
      if (integrationId)
        resolve([integrationId, timestamp]);
      else
        reject(`Error locating Integration ID from ${fullChangeId}`);
    })
  });
}

function getWorkFromIntegration(uuid, integrationId, timestamp, isRetry) {
  if (isRetry)
    console.log(`Retrying COIN query for ${integrationId}`);
  return new Promise(function(resolve, reject) {
    axios.get(`https://testresults.qt.io/coin/api/taskDetail?id=${integrationId}`)
    .then((response) => {
      let task = response.data.tasks.pop();
      if (task.final_sha) {

        let integrationData = [];
        for (const change in task.tested_changes) {
          integrationData.push({
            subject: task.tested_changes[change].subject,
            sha: task.tested_changes[change].sha,
            url: `https://codereview.qt-project.org/c/qt%2Fqtbase/+/${task.tested_changes[change].change_number}`
          })
        }
        let work = new Work({
          integrationId: integrationId,
          integrationTimestamp: timestamp,
          integrationURL: task.self_url,
          integrationData: integrationData,
          branch: task.branch,
          sha: task.final_sha
        })
        enqueueDBAction(uuid, integrationId, postgreSQLClient.update,
          [
            "core_benchmarks", "integration_id", integrationId,
            {
              integration_id: work.integrationId,
              integration_timestamp: work.integrationTimestamp,
              integration_url: work.integrationURL,
              integration_data: Buffer.from(safeJsonStringify(integrationData)).toString('base64'),
              branch: work.branch,
              work_sha: work.sha
            },
            null
          ])
        console.log(`resolving work for ${integrationId}, timestamp: ${timestamp}`);
        console.log("work object: ", work)
        resolve(work);
      } else if (isRetry) {
        reject(`No final_sha in COIN after 30 seconds.`);
      } else {
        setTimeout(() => getWorkFromIntegration(uuid, integrationId, timestamp, true)
        .then((work) => resolve(work))
        .catch((error) => reject(error)),
        30000);
      }
    }).catch((error) => {
      reject(error);
    })
  });
}

class core_benchmarks_server {
  constructor(notifier) {
    this.notifier = notifier;
    this.logger = notifier.logger;
    this.retryProcessor = notifier.retryProcessor;

    this.ready = this.ready.bind(this);
    this.recover = this.recover.bind(this);
    this.processMerge = this.processMerge.bind(this);
    this.handleStatusUpdate = this.handleStatusUpdate.bind(this);
    this.onConnection = this.onConnection.bind(this);

    this.io = socketio(notifier.server.server,
    // +!+!+!+!+!+!+! DEVELOPMENT BLOCK. REMOVE! +!+!+!+!+!+!+!+!+!+!
    // +!+!+!+!+!+!+! DEVELOPMENT BLOCK. REMOVE! +!+!+!+!+!+!+!+!+!+!
    {
      cors: {
        origin: "https://qt-bots-status-site.herokuapp.com",
        methods: ["GET", "POST"]
      }
    }
    // +!+!+!+!+!+!+! END DEVELOPMENT BLOCK. +!+!+!+!+!+!+!+!+!+!
    );
    this.io.use((socket, next) => {
      if (socket.handshake.auth.clientType == "agent") {
        if (socket.handshake.auth.hostname) {
          if (socket.handshake.auth.secret == process.env["CORE_BENCHMARKS_AUTH_TOKEN"]) {
            next();
          } else {
            next(new Error("Invalid authorization token"));
          }
        } else {
          next(new Error("No hostname for agent provided."));
        }
      } else if (socket.handshake.auth.clientType == "browser") {
        // Browsers have limited access and do not require authentication.
        next();
      } else {
        next(new Error("Unsupported client type"));
      }
    });


    this.recover();
  }

  ready() {
    this.notifier.server.app.use("/core-benchmarks", express.json());
    this.notifier.server.app.post("/core-benchmarks", (req, res) => this.processMerge(req, res));
    this.io.on('connection', (socket) => {this.onConnection(socket)});
    console.log("Core Benchmarks initialized and listening for work.")
    console.log("Integrations in process: " + integrationIdsInProcess);
  }

  recover() {
    new Promise((resolve, reject) => {
      postgreSQLClient.query("core_benchmarks_agents", "*", "agent_id", null, "IS NOT NULL",
        (success, rows) => {
          if (success && rows.length) {
            for (const i in rows) {
              if (moment(rows[i].last_connected).isAfter(moment().subtract(7, 'days'))) {
                agents[rows[i].agent_id] = new Agent(null, rows[i].last_connected);
              } else {
                // Agent is stale and hasn't connected in a week. Delete it so we stop
                // queuing work for it!
                postgreSQLClient.deleteDBEntry("core_benchmarks_agents", "agent_id", rows[i].agent_id);
              }
            }
            console.log(`Recovered agents: ${Object.keys(agents)}`)
          }
          resolve();
        }
      );
    }).then(() => {
      postgreSQLClient.deleteDBEntry("core_benchmarks", "integration_timestamp",
        moment().subtract('7 days').toISOString(),
        (success, rows) => {
          console.log(success);  // responds with message DELETE <row count>
          postgreSQLClient.query("core_benchmarks", "*", "done", null, `&& '{"false"}'`,
          (success, rows) => {
            if (success && rows.length) {
              let sorted = rows.sort((a,b) =>
                Date.parse(a.timestamp) - Date.parse(b.timestamp));
              for (const i in sorted) {
                // console.log(`Recovery row: ${safeJsonStringify(sorted[i])}`);
                integrationIdsInProcess.push(sorted[i].integration_id);
                for (const j in sorted[i].agents) {
                  try {
                    enqueueWork(sorted[i].agents[j],
                      new Work({
                        integrationId: sorted[i].integration_id,
                        integrationTimestamp: sorted[i].integration_timestamp,
                        integrationURL: sorted[i].integration_url,
                        integrationData: JSON.parse(Buffer.from(sorted[i].integration_data, 'base64')),
                        branch: sorted[i].branch,
                        sha: sorted[i].work_sha
                      }));
                    } catch (e) {
                      console.log(e, safeJsonStringify(sorted[i]));
                    }
                }
              }
              this.ready();
            } else {
              console.log(`No work to recover. ${success}`);
              this.ready();
              return;
            }
          }
        );
        // Also query for the top 20 done integrations.
        // This runs parallel to the above then() block and does not block the server from starting.
        postgreSQLClient.query("core_benchmarks", "*", "job_done", null,
          "= true ORDER BY timestamp LIMIT 20", (success, rows) => {
          if (!rows.length)
            return;  // No done work in database.
          for (const i in rows) {
            if (integrationJobsDone.length > 19)
              integrationJobsDone.shift();
            integrationJobsDone.push(rows[i]);
          }
          console.log("Integrations completed testing: "
          + integrationJobsDone.map(j => j.integration_id));
        });
      });
    })
  }

  processMerge(req, res) {
    console.log("process merge...")
    // IP validate the request so that only gerrit can send us messages.
    let gerritIPv4 = envOrConfig("GERRIT_IPV4");
    let gerritIPv6 = envOrConfig("GERRIT_IPV6");
    if (!process.env.IGNORE_IP_VALIDATE) {
      // Filter requests to only receive from an expected gerrit instance.
      let clientIp = req.headers["x-forwarded-for"] || req.connection.remoteAddress;
      if (net.isIPv4(clientIp) && clientIp != gerritIPv4) {
        res.sendStatus(401);
        return false;
      } else if (net.isIPv6(clientIp) && clientIp != gerritIPv6) {
        res.sendStatus(401);
        return false;
      } else if (!net.isIP(clientIp)) {
        // ERROR, but don't exit.
        this.logger.log(
          `FATAL: Incoming request appears to have an invalid origin IP: ${clientIp}`,
          "warn"
        );
        res.sendStatus(500); // Try to send a status anyway.
        return false;
      }
    }
    res.sendStatus(200);
    req = req.body;
    req.uuid = uuidv1(); // used for tracking and database access.
    req.fullChangeID = encodeURIComponent(`${req.change.project}~${req.change.branch}~${req.change.id}`);
    req.change.fullChangeID = req.fullChangeID;
    if (!["qt/qtbase", "tqtc/qt-qtbase"].includes(req.change.project)) {
      return;  // Only process changes from qtbase.
    }
    collectIntegrationId(req.uuid, req.fullChangeID)
    .then(([integrationId, timestamp]) => {
      let workAgents = Object.keys(agents);
      dbCheckIfWorkNeeded(req.uuid, integrationId, workAgents, timestamp)
      .then(() => {
        console.log("DB Insert successful")
        getWorkFromIntegration(req.uuid, integrationId, timestamp)
        .then(work => workAgents.forEach((agent) => enqueueWork(agent, work)))
        .catch((error) => console.log(`No SHA available from integration ${integrationId}: ${error}`));
      })
      .catch((error) => {
        if (error == "in_progress")
          console.log(`integration ID ${integrationId} already queued.`);
        else
          console.log(error);
      })
    }).catch(() => console.log("Can't find an integrationId")); // OK to do nothing if we can't find an integration ID anyway.
  }

  handleStatusUpdate(agentName, status) {
    console.log(`Status update received from ${agentName} status: ${safeJsonStringify(status)}`);
    if (status.status == Status.Done.valueOf()) {
      enqueueDBAction("CORE_BENCH", status.integrationId, postgreSQLClient.query,
        [
          "core_benchmarks", "agents,done", "integration_id", status.integrationId,
          "=",
          (success, rows) => {
            if (!success || !rows.length) {
              console.log(`Error querying for ${status.integrationId}: ${rows}`);
              return;
            } else {
              let data = rows[0];
              const agentIndex = data.agents.indexOf(agentName);
              data.done[agentIndex] = true;
              let updates = {done: data.done};
              if (!data.done.some((e) => e))  // No agents with outstanding work.
                updates.job_done = true;
              enqueueDBAction("CORE_BENCH", status.integrationId, postgreSQLClient.update,
                [ "core_benchmarks", "integration_id", status.integrationId, updates, null ]
              );
            }
          }
        ]
      );
    }
    if (status.updateTimestamp < agents[agentName].currentJob.updateTimestamp) {
      console.log(`WARN: Update '${status.status}' for ${agentName} is stale!`);
      return;  // The update is stale. It probably arrived out-of-order.
    }
    agents[agentName].currentJob = new Work(status);
  }

  onConnection(socket) {
    console.log("new connection. Type: " + socket.handshake.auth.clientType)
    if (socket.handshake.auth.clientType == "agent") {
      const agentName = socket.handshake.auth.hostname;
      // A new agent has connected.
      const lastConnected = new Date(Date.now()).toISOString();
      let newAgent;
      if (!agents[agentName]) {
        console.log(agentName + " connected!");
        newAgent = new Agent(socket, lastConnected);
        postgreSQLClient.insert("core_benchmarks_agents", ["agent_id", "last_connected"],
          [agentName, lastConnected]);
      } else {
        console.log(agentName + " reconnected!");
        newAgent = agents[agentName];
        postgreSQLClient.update("core_benchmarks_agents", "agent_id", agentName,
                  {last_connected: lastConnected});
      }
      newAgent.online = true;
      newAgent.lastConnected = lastConnected;
      agents[agentName] = newAgent; // Update all at once so only one update is sent to clients.


      socket.on('statusUpdate', (status) => this.handleStatusUpdate(agentName, status));

      // +!+!+!+!+!+!+! DEVELOPMENT BLOCK. REMOVE! +!+!+!+!+!+!+!+!+!+!
      socket.on('mockItem', (body) => {
        console.log("mockItem called.")

        if (!agents[agentName].workQueue.length) {
          let tempWork = new Work({integrationId: "1682362890", sha: "e3fdd9715fa220d909689def10e9b72c14083e09", branch: "dev"});
          if (!integrationIdsInProcess.includes(tempWork.integrationId)) {
            integrationIdsInProcess.push(tempWork.integrationId);
            enqueueWork(agentName, tempWork);
          }
        }
      });
      // +!+!+!+!+!+!+! END DEVELOPMENT BLOCK. +!+!+!+!+!+!+!+!+!+!

      socket.on('fetchWork', () => {
        console.log("fetchWork called");
        if (agents[agentName].workQueue.length) {
            socket.emit('sendWork', agents[agentName].workQueue.shift());
        }
      });

      // +!+!+!+!+!+!+! DEVELOPMENT BLOCK. REMOVE! +!+!+!+!+!+!+!+!+!+!
      socket.on('queryWork', () => {
        console.log("queryWork called");
          socket.emit('sendWork', agents[agentName].workQueue.at(0));
      });
      // +!+!+!+!+!+!+! END DEVELOPMENT BLOCK. +!+!+!+!+!+!+!+!+!+!

      socket.on('disconnect', (reason) => {
        if (reason && reason == "shutdown") {
          delete agents[agentName];  // Intentional shut down means do not queue new work.
        } else {
          console.log(`${agentName} disconnected.`);
          agents[agentName].online = false;
          agents[agentName].currentJob = new Work();
        }
      });
    } else if (socket.handshake.auth.clientType == "browser") {
      console.log(`new browser connected. SocketId: ${socket.id}`);
      webViewers[socket.id] = socket;

      socket.on('getAgents', () => {
        socket.emit('agentData', Object.keys(agents).map((agent) => {
          return {
            agent: agent,
            currentJob: agents[agent].currentJob,
            online: agents[agent].online,
            lastConnected: agents[agent].lastConnected
          }
        }));
      });

      socket.on('getWorkLog', () => {
        socket.emit('workLogData', integrationJobsDone);
      })

      socket.on('disconnect', () => {
        console.log(`Browser disconnected. SocketId: ${socket.id}`);
        delete webViewers[socket.id];
      })
    }
  }
/* eslint-disable no-unused-vars */

 }

 module.exports = core_benchmarks_server;
