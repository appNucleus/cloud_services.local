"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");

const port = Number(process.env.PORT || 8080);
const cognitoEndpoint = new URL(process.env.COGNITO_ENDPOINT || "http://cognito:9229/");
const indexPath = path.join(__dirname, "index.html");

function sendJson(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff"
  });
  res.end(body);
}

function sendText(res, status, body, contentType = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "Content-Type": contentType,
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff"
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.setEncoding("utf8");
    req.on("data", chunk => {
      data += chunk;
      if (data.length > 65536) {
        reject(new Error("Request body is too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch {
        reject(new Error("Request body must be valid JSON"));
      }
    });
    req.on("error", reject);
  });
}

function cognito(target, payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload || {});
    const request = http.request({
      hostname: cognitoEndpoint.hostname,
      port: cognitoEndpoint.port || 80,
      path: cognitoEndpoint.pathname || "/",
      method: "POST",
      headers: {
        "Content-Type": "application/x-amz-json-1.1",
        "X-Amz-Target": `AWSCognitoIdentityProviderService.${target}`,
        "Content-Length": Buffer.byteLength(body)
      },
      timeout: 5000
    }, response => {
      let raw = "";
      response.setEncoding("utf8");
      response.on("data", chunk => { raw += chunk; });
      response.on("end", () => {
        let parsed = {};
        if (raw) {
          try { parsed = JSON.parse(raw); }
          catch { parsed = { message: raw }; }
        }
        if ((response.statusCode || 500) >= 400) {
          const err = new Error(parsed.message || parsed.Message || `Cognito Local returned HTTP ${response.statusCode}`);
          err.statusCode = response.statusCode || 502;
          err.details = parsed;
          return reject(err);
        }
        resolve(parsed);
      });
    });
    request.on("timeout", () => request.destroy(new Error("Cognito Local request timed out")));
    request.on("error", reject);
    request.end(body);
  });
}

function requireString(value, name) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!normalized) {
    const err = new Error(`${name} is required`);
    err.statusCode = 400;
    throw err;
  }
  return normalized;
}

function routeParts(url) {
  return url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
}

async function handleApi(req, res, url) {
  const parts = routeParts(url);

  if (req.method === "GET" && url.pathname === "/api/health") {
    await cognito("ListUserPools", { MaxResults: 1 });
    return sendJson(res, 200, { ok: true });
  }

  if (req.method === "GET" && url.pathname === "/api/pools") {
    return sendJson(res, 200, await cognito("ListUserPools", { MaxResults: 60 }));
  }

  if (parts.length === 3 && parts[0] === "api" && parts[1] === "pools" && req.method === "GET") {
    return sendJson(res, 200, await cognito("DescribeUserPool", {
      UserPoolId: requireString(parts[2], "User pool ID")
    }));
  }

  if (req.method === "POST" && url.pathname === "/api/pools") {
    const input = await readJson(req);
    const name = requireString(input.name, "Pool name");
    return sendJson(res, 201, await cognito("CreateUserPool", { PoolName: name }));
  }

  if (parts.length === 3 && parts[0] === "api" && parts[1] === "pools" && req.method === "DELETE") {
    await cognito("DeleteUserPool", { UserPoolId: requireString(parts[2], "User pool ID") });
    return sendJson(res, 200, { ok: true });
  }

  if (parts.length === 4 && parts[0] === "api" && parts[1] === "pools" && parts[3] === "users" && req.method === "GET") {
    return sendJson(res, 200, await cognito("ListUsers", { UserPoolId: requireString(parts[2], "User pool ID"), Limit: 60 }));
  }

  if (parts.length === 4 && parts[0] === "api" && parts[1] === "pools" && parts[3] === "users" && req.method === "POST") {
    const input = await readJson(req);
    const userPoolId = requireString(parts[2], "User pool ID");
    const username = requireString(input.username, "Username");
    const fullName = requireString(input.fullName, "Full name");
    const password = requireString(input.password, "Password");
    const email = typeof input.email === "string" ? input.email.trim() : "";
    const attributes = [
      { Name: "name", Value: fullName }
    ];

    if (email) {
      attributes.push({ Name: "email", Value: email });
      attributes.push({ Name: "email_verified", Value: "true" });
    }

    const createPayload = {
      UserPoolId: userPoolId,
      Username: username,
      TemporaryPassword: password,
      MessageAction: "SUPPRESS"
    };
    if (attributes.length) createPayload.UserAttributes = attributes;

    const created = await cognito("AdminCreateUser", createPayload);
    if (input.permanent !== false) {
      await cognito("AdminSetUserPassword", {
        UserPoolId: userPoolId,
        Username: username,
        Password: password,
        Permanent: true
      });
    }
    return sendJson(res, 201, created);
  }

  if (parts.length === 5 && parts[0] === "api" && parts[1] === "pools" && parts[3] === "users" && req.method === "DELETE") {
    await cognito("AdminDeleteUser", {
      UserPoolId: requireString(parts[2], "User pool ID"),
      Username: requireString(parts[4], "Username")
    });
    return sendJson(res, 200, { ok: true });
  }

  if (parts.length === 6 && parts[0] === "api" && parts[1] === "pools" && parts[3] === "users" && parts[5] === "password" && req.method === "POST") {
    const input = await readJson(req);
    await cognito("AdminSetUserPassword", {
      UserPoolId: requireString(parts[2], "User pool ID"),
      Username: requireString(parts[4], "Username"),
      Password: requireString(input.password, "Password"),
      Permanent: input.permanent !== false
    });
    return sendJson(res, 200, { ok: true });
  }

  return sendJson(res, 404, { message: "Not found" });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");

    if (url.pathname.startsWith("/api/")) {
      return await handleApi(req, res, url);
    }

    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      const html = fs.readFileSync(indexPath, "utf8");
      return sendText(res, 200, html, "text/html; charset=utf-8");
    }

    return sendText(res, 404, "Not found\n");
  } catch (err) {
    const status = Number.isInteger(err.statusCode) && err.statusCode >= 400 && err.statusCode < 600 ? err.statusCode : 502;
    return sendJson(res, status, {
      message: err.message || "Request failed",
      details: err.details || undefined
    });
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Cognito Local admin UI listening on http://0.0.0.0:${port}; backend ${cognitoEndpoint.href}`);
});
