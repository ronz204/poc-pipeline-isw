import { env } from "@secrets";
import { uuidv7 } from "uuidv7";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

const url = env.POSTGRES_RUNNER_URL;
const client = postgres(url, { prepare: false });

export type Drizzler = typeof drizzler;
export const drizzler = drizzle({ client });
export const generateId = () => uuidv7();
