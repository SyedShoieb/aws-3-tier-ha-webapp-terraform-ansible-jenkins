"use strict";

const http = require("node:http");
const os = require("node:os");

const {
  SecretsManagerClient,
  GetSecretValueCommand
} = require("@aws-sdk/client-secrets-manager");

const mysql = require("mysql2/promise");

const PORT = Number(process.env.PORT || 4000);
const HOST = "0.0.0.0";
const AWS_REGION = process.env.AWS_REGION || "ap-south-1";
const DB_SECRET_ARN = process.env.DB_SECRET_ARN;
const DB_NAME = process.env.DB_NAME || "webappdb";

const secretsClient = new SecretsManagerClient({
  region: AWS_REGION
});

let cachedSecret;
let pool;

function sendJson(res, statusCode, data) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });

  res.end(JSON.stringify(data, null, 2));
}

async function getDatabaseCredentials() {
  if (cachedSecret) {
    return cachedSecret;
  }

  if (!DB_SECRET_ARN) {
    throw new Error("DB_SECRET_ARN is not configured");
  }

  const result = await secretsClient.send(
    new GetSecretValueCommand({
      SecretId: DB_SECRET_ARN
    })
  );

  if (!result.SecretString) {
    throw new Error("Database secret has no SecretString");
  }

  const secret = JSON.parse(result.SecretString);

  if (!secret.host || !secret.username || !secret.password) {
    throw new Error("Database secret is missing required fields");
  }

  cachedSecret = {
    host: secret.host,
    username: secret.username,
    password: secret.password,
    port: Number(secret.port || 3306)
  };

  return cachedSecret;
}

async function getDatabasePool() {
  if (pool) {
    return pool;
  }

  const credentials = await getDatabaseCredentials();

  pool = mysql.createPool({
    host: credentials.host,
    port: credentials.port,
    user: credentials.username,
    password: credentials.password,
    database: DB_NAME,
    waitForConnections: true,
    connectionLimit: 5,
    queueLimit: 0,
    enableKeepAlive: true,
    connectTimeout: 5000
  });

  return pool;
}

async function checkDatabase() {
  const database = await getDatabasePool();

  const [rows] = await database.query(
    "SELECT NOW() AS database_time"
  );

  return {
    status: "connected",
    databaseTime: rows[0].database_time
  };
}

function createServer() {
  return http.createServer(async (req, res) => {
    const pathname = new URL(
      req.url,
      `http://${req.headers.host || "localhost"}`
    ).pathname;

    if (req.method !== "GET") {
      return sendJson(res, 405, {
        error: "Method not allowed"
      });
    }

    if (pathname === "/health") {
      return sendJson(res, 200, {
        status: "healthy",
        service: "application",
        timestamp: new Date().toISOString()
      });
    }

    if (pathname === "/api/info") {
      return sendJson(res, 200, {
        application: "AWS 3-Tier Highly Available Web Application",
        service: "Node.js application tier",
        hostname: os.hostname(),
        timestamp: new Date().toISOString()
      });
    }

    if (pathname === "/api" || pathname === "/api/db-health") {
      try {
        const database = await checkDatabase();

        return sendJson(res, 200, {
          message: "Application and database are working.",
          service: "Node.js application tier",
          database
        });
      } catch (error) {
        // Log diagnostic details, but never return credentials to clients.
        console.error("Database request failed:", error.message);

        return sendJson(res, 503, {
          error: "Database is currently unavailable",
          service: "application"
        });
      }
    }

    return sendJson(res, 404, {
      error: "Not found",
      availableEndpoints: [
        "/health",
        "/api",
        "/api/info",
        "/api/db-health"
      ]
    });
  });
}

async function closeDatabasePool() {
  if (pool) {
    const currentPool = pool;
    pool = undefined;
    await currentPool.end();
  }
}

if (require.main === module) {
  const server = createServer();

  server.listen(PORT, HOST, () => {
    console.log(`Application listening on ${HOST}:${PORT}`);
  });

  let shuttingDown = false;

  async function shutdown() {
    if (shuttingDown) {
      return;
    }

    shuttingDown = true;

    server.close(async () => {
      try {
        await closeDatabasePool();
        await secretsClient.destroy();
        process.exit(0);
      } catch (error) {
        console.error("Shutdown failed:", error.message);
        process.exit(1);
      }
    });
  }

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

module.exports = {
  createServer,
  closeDatabasePool
};