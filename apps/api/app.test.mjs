import request from "supertest";
import { test } from "vitest";
import { app } from "./index.mjs";

test("Responds with a welcome message", async () => {
  await request(app)
    .get("/hello")
    .set("Accept", "application/json")
    .expect("Content-Type", /json/)
    .expect(200);
});

// Exercise the real route with credentials containing URL-sensitive characters.
test("Uses environment database credentials without URI interpolation", async () => {
  const { vi, expect } = await import("vitest");
  const { default: pg } = await import("pg");
  vi.stubEnv("DB_NAME", "ci-api-db");
  vi.stubEnv("DB_USER", "ci-api-user");
  vi.stubEnv("DB_PASSWORD", "pass:@/'$?");
  const client = { connect: vi.fn(), query: vi.fn().mockResolvedValue({ rows: [{ message: "hello world from postgres" }] }), end: vi.fn() };
  const constructor = vi.spyOn(pg, "Client").mockImplementation(() => client);
  try {
    await request(app).get("/hello-pg").expect(200, { message: "hello world from postgres" });
    expect(constructor).toHaveBeenCalledWith(expect.objectContaining({ database: "ci-api-db", user: "ci-api-user", password: "pass:@/'$?" }));
    expect(client.end).toHaveBeenCalled();
  } finally {
    vi.restoreAllMocks();
    vi.unstubAllEnvs();
  }
});
