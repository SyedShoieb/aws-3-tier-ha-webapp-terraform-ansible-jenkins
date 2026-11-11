"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createServer,
  closeDatabasePool
} = require("./server");

test("application health endpoint returns healthy", async (t) => {
  const server = createServer();

  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });

  t.after(async () => {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    });

    await closeDatabasePool();
  });

  const address = server.address();
  const response = await fetch(
    `http://127.0.0.1:${address.port}/health`
  );

  assert.equal(response.status, 200);

  const body = await response.json();

  assert.equal(body.status, "healthy");
  assert.equal(body.service, "application");
});

test("unknown endpoints return 404", async (t) => {
  const server = createServer();

  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });

  t.after(async () => {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    });
  });

  const address = server.address();
  const response = await fetch(
    `http://127.0.0.1:${address.port}/not-a-real-endpoint`
  );

  assert.equal(response.status, 404);

  const body = await response.json();

  assert.equal(body.error, "Not found");
});