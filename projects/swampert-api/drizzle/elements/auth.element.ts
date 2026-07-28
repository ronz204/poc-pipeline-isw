import { pgSchema, pgRole } from "drizzle-orm/pg-core";

export const runner = pgRole("runner").existing();
export const auth = pgSchema("auth");